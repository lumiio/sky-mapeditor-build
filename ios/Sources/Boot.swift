import Foundation

/// 启动埋点：每个关键步骤落盘，闪退后下次启动能看出断在哪一步。
enum Boot {
    static var framed = false
    static var url: URL {
        let dir = URL(fileURLWithPath: NSHomeDirectory()).appendingPathComponent("Documents", isDirectory: true)
        try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        return dir.appendingPathComponent("boot.log")
    }

    static func log(_ s: String) {
        let line = "[\(Date())] \(s)\n"
        NSLog("SKYBOOT: \(s)")
        if let h = try? FileHandle(forWritingTo: url) {
            h.seekToEndOfFile()
            h.write(line.data(using: .utf8)!)
            // 被系统直接 SIGKILL（jetsam / watchdog）时，缓冲区里的行会丢；同步落盘才能看清断在哪
            try? h.synchronizeFile()
            try? h.close()
        } else {
            try? line.write(to: url, atomically: true, encoding: .utf8)
        }
    }

    static func reset() {
        try? "".write(to: url, atomically: true, encoding: .utf8)
    }

    static func tail(_ n: Int = 12) -> String {
        guard let s = try? String(contentsOf: url, encoding: .utf8) else { return "" }
        return s.split(separator: "\n").suffix(n).joined(separator: "\n")
    }
}
