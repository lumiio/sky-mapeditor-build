import Foundation

/// 把游戏原始 `Data` 目录就地转成引擎要的资源。
///
/// 以前这条路只能离线走：`native/terrain.mjs`、`export-scene.mjs` 在电脑上把游戏文件
/// 转成 `<level>.terrain.bin` + `<level>.terrain.meta.json`，再打进 App 包里。现在搬进 App——
///
/// 1. 用文件 App 把游戏的 `Data` 目录放进 App 的 `Documents/Data`（Info.plist 已开文件共享）；
/// 2. 下次启动自动在 `Documents/Assets` 里生成与离线包同格式的文件；
/// 3. `GameAssets.root` 指向 `Documents/Assets`，引擎其余代码一行都不用改。
///
/// 格式来源不是猜的：`BstBaked.meshes` 的解析见 `LVL0.swift`，那是照着编辑器
/// 0.3.1 自己的实现写的，并在它自带的 33 张图上 33/33 校验过。
enum GameAssets {
    /// 生成完成标记。有它就认为 `Documents/Assets` 可用。
    static let marker = ".game-source"
    /// 原版地形顶点步长（36 字节，见 `LVL0Document`）。
    static let vertexStride = 36
    /// 材质 id 在顶点流里的字节偏移（低字节是主材质）。
    static let materialByteOffset = 16
    /// 顶点坐标在顶点流里的偏移。
    static let positionByteOffset = 0

    static var documents: URL {
        URL(fileURLWithPath: NSHomeDirectory()).appendingPathComponent("Documents", isDirectory: true)
    }
    static var localRoot: URL { documents.appendingPathComponent("Assets", isDirectory: true) }
    static var gameDataRoot: URL { documents.appendingPathComponent("Data", isDirectory: true) }

    static var bundledRoot: URL? {
        Bundle.main.url(forResource: "Assets", withExtension: nil)
    }

    /// 引擎读资源的根目录：生成过就用 `Documents/Assets`，否则退回 App 包里的 `Assets`。
    static var root: URL? {
        FileManager.default.fileExists(atPath: localRoot.appendingPathComponent(marker).path)
            ? localRoot : bundledRoot
    }

    /// 某一关卡该从哪个根目录读：本地生成过这张图就用 `Documents/Assets`，
    /// 否则退回 App 包（纯 prefab 关卡例如烛窟只存在于包里）。
    static func root(forLevel level: String) -> URL? {
        let fm = FileManager.default
        if fm.fileExists(atPath: localRoot.appendingPathComponent(marker).path),
           fm.fileExists(atPath: localRoot.appendingPathComponent("\(level).terrain.bin").path) {
            return localRoot
        }
        return bundledRoot
    }

    /// 在 `root` 下找一个资源文件；两条路都不存在时返回 nil。
    static func url(_ relativePath: String) -> URL? {
        guard let root else { return nil }
        let candidate = root.appendingPathComponent(relativePath)
        return FileManager.default.fileExists(atPath: candidate.path) ? candidate : nil
    }

    // MARK: - 生成结果

    struct Report {
        var built: [String] = []
        var skipped: [String] = []
        var failed: [(name: String, reason: String)] = []
        var vertices = 0
        var indices = 0
        /// 顺带用 TGCL 解析器把每张图的 `Objects.level.bin` 走一遍，验证格式，也留个计数。
        var tgclLevels = 0
        var tgclNodes = 0
        var tgclClasses = 0
        var seconds: Double = 0

        var summary: String {
            var line = "原始数据 \(built.count) 张已生成"
            if !skipped.isEmpty { line += " · \(skipped.count) 张无地形" }
            if !failed.isEmpty { line += " · \(failed.count) 张失败" }
            line += " · \(vertices) 顶点 / \(indices / 3) 三角"
            if tgclLevels > 0 {
                line += " · TGCL \(tgclLevels) 张 / \(tgclNodes) 节点 / \(tgclClasses) 类"
            }
            return line
        }
    }

    // MARK: - 探测

    static func hasGameData() -> Bool {
        FileManager.default.fileExists(atPath: gameDataRoot.appendingPathComponent("Levels").path)
    }

    /// `Documents/Data/Levels` 下所有带 `BstBaked.meshes` 的目录名。
    static func mapNamesInGameData() -> [String] {
        let levels = gameDataRoot.appendingPathComponent("Levels", isDirectory: true)
        let entries = (try? FileManager.default.contentsOfDirectory(at: levels,
                                                                   includingPropertiesForKeys: nil,
                                                                   options: [.skipsHiddenFiles])) ?? []
        return entries.compactMap { dir -> String? in
            let meshes = dir.appendingPathComponent("BstBaked.meshes")
            return FileManager.default.fileExists(atPath: meshes.path) ? dir.lastPathComponent : nil
        }.sorted()
    }

    /// 已经生成好的关卡名（`Documents/Assets/*.terrain.bin`）。
    static func localLevels() -> [String] {
        let fm = FileManager.default
        guard fm.fileExists(atPath: localRoot.path) else { return [] }
        let entries = (try? fm.contentsOfDirectory(at: localRoot, includingPropertiesForKeys: nil,
                                                   options: [.skipsHiddenFiles])) ?? []
        let suffix = ".terrain.bin"
        return entries.compactMap { url -> String? in
            let name = url.lastPathComponent
            guard name.hasSuffix(suffix) else { return nil }
            return String(name.dropLast(suffix.count))
        }.sorted()
    }

    /// 首次（或换过数据）才生成，已有标记就跳过。返回 nil 表示没有原始数据可处理。
    @discardableResult
    static func buildIfNeeded() -> Report? {
        guard hasGameData() else { return nil }
        if FileManager.default.fileExists(atPath: localRoot.appendingPathComponent(marker).path) {
            return nil
        }
        return build()
    }

    // MARK: - 生成

    static func build() -> Report {
        let started = Date()
        let fm = FileManager.default
        var report = Report()

        do {
            try fm.createDirectory(at: localRoot, withIntermediateDirectories: true)
        } catch {
            report.failed.append(("Assets", "创建目录失败：\(error)"))
            return report
        }
        copyStaticResources()

        for name in mapNamesInGameData() {
            let mapDir = gameDataRoot.appendingPathComponent("Levels/\(name)", isDirectory: true)
            let meshesURL = mapDir.appendingPathComponent("BstBaked.meshes")

            // TGCL 只做校验与计数：它不影响地形，坏了也不该拖累出图。
            if let levelData = try? Data(contentsOf: mapDir.appendingPathComponent("Objects.level.bin")) {
                do {
                    let document = try TGCLDocument(data: levelData)
                    report.tgclLevels += 1
                    report.tgclNodes += document.nodes.count
                    report.tgclClasses += document.classes.count
                } catch {
                    Boot.log("TGCL 解析失败 \(name): \(error)")
                }
            }

            guard let data = try? Data(contentsOf: meshesURL) else {
                report.failed.append((name, "BstBaked.meshes 读不到"))
                continue
            }
            do {
                let document = try LVL0Document(data: data)
                guard document.firstMesh(of: .terrain) != nil else {
                    // 纯 prefab 关卡（例如烛窟）的地形来自 Objects.level.bin 的 TerrainBlobPrefab，
                    // 由离线 terrain.mjs 程序化生成，这里没有可直接用的顶点流。
                    report.skipped.append(name)
                    continue
                }
                let counts = try materialize(level: name, document: document)
                report.built.append(name)
                report.vertices += counts.vertices
                report.indices += counts.indices
                Boot.log("生成 \(name): \(counts.vertices) 顶点 / \(counts.indices / 3) 三角")
            } catch {
                report.failed.append((name, "\(error)"))
            }
        }

        if !report.built.isEmpty {
            try? "\(report.built.count)".write(to: localRoot.appendingPathComponent(marker),
                                               atomically: true, encoding: .utf8)
        }
        report.seconds = Date().timeIntervalSince(started)
        return report
    }

    /// 把 App 包里那份静态资源搬过来：贴图、体积云、metallib、材质表。
    /// 生成出来的 `Documents/Assets` 必须是自洽的，否则引擎换了根目录就找不到贴图。
    private static func copyStaticResources() {
        let fm = FileManager.default
        guard let bundle = bundledRoot else {
            Boot.log("缺 Assets：无法复制静态资源")
            return
        }
        let destData = localRoot.appendingPathComponent("Data", isDirectory: true)
        if !fm.fileExists(atPath: destData.path) {
            let src = bundle.appendingPathComponent("Data", isDirectory: true)
            if fm.fileExists(atPath: src.path) {
                do { try fm.copyItem(at: src, to: destData) }
                catch { Boot.log("复制 Data 失败: \(error)") }
            } else {
                Boot.log("App 包里没有 Assets/Data")
            }
        }
        let entries = (try? fm.contentsOfDirectory(at: bundle, includingPropertiesForKeys: nil,
                                                   options: [.skipsHiddenFiles])) ?? []
        for src in entries where src.lastPathComponent.hasSuffix(".materials.json") {
            let dst = localRoot.appendingPathComponent(src.lastPathComponent)
            if !fm.fileExists(atPath: dst.path) {
                try? fm.copyItem(at: src, to: dst)
            }
        }
    }

    // MARK: - 单图生成

    /// 把一张图的 LVL0 地形 + 裙边写成引擎现在读的那两样东西：
    /// `<level>.terrain.bin`（`[u32 顶点数][u32 索引数][顶点×36][索引×u32]`）和
    /// `<level>.terrain.meta.json`（索引区间按材质分组）。另外补一个纯地形 manifest。
    @discardableResult
    private static func materialize(level: String, document: LVL0Document)
        throws -> (vertices: Int, indices: Int) {

        var vertices = Data()
        var source: [UInt32] = []

        for kind in [LVL0Document.Kind.terrain, .skirt] {
            for mesh in document.meshes(of: kind) where mesh.vertexCount > 0 {
                let raw = document.vertexData(of: mesh)
                guard raw.count >= mesh.vertexByteCount, mesh.stride >= vertexStride else { continue }
                let base = UInt32(vertices.count / vertexStride)
                var offset = 0
                while offset + vertexStride <= raw.count {
                    // 裙边 40 字节里的前 36 字节与地形顶点同构，多的 userData1 丢掉。
                    vertices.append(raw.subdata(in: offset..<(offset + vertexStride)))
                    offset += mesh.stride
                }
                for index in mesh.indices {
                    source.append(index + base)
                }
            }
        }

        let vertexCount = vertices.count / vertexStride
        guard vertexCount > 0, source.count >= 3 else {
            throw ByteReadError.invalid("\(level): 地形没有任何可绘制的三角形")
        }

        // 按材质把三角形分桶。原版就是一个材质一个批次，这里也保证每个材质一段连续区间，
        // 免得几百个交替区间变成几百次 draw。
        var buckets = [[UInt32]](repeating: [], count: 256)
        var used = [Bool](repeating: false, count: 256)
        var cursor = 0
        while cursor + 2 < source.count {
            let vertex = Int(source[cursor])
            let byteOffset = vertices.startIndex + vertex * vertexStride + materialByteOffset
            let material = byteOffset < vertices.endIndex ? Int(vertices[byteOffset]) : 0
            used[material] = true
            buckets[material].append(source[cursor])
            buckets[material].append(source[cursor + 1])
            buckets[material].append(source[cursor + 2])
            cursor += 3
        }

        var indices: [UInt32] = []
        indices.reserveCapacity(source.count)
        var ranges: [[String: Any]] = []
        for material in 0..<256 where used[material] {
            let bucket = buckets[material]
            guard !bucket.isEmpty else { continue }
            ranges.append([
                "start": indices.count,
                "count": bucket.count,
                "material": material,
                "name": "mat\(material)",
            ])
            indices.append(contentsOf: bucket)
        }

        // 包围盒：引擎的取景和相机都靠它。
        var lo = SIMD3<Float>(repeating: .greatestFiniteMagnitude)
        var hi = SIMD3<Float>(repeating: -.greatestFiniteMagnitude)
        var offset = 0
        while offset + vertexStride <= vertices.count {
            let p = SIMD3<Float>(readFloat(vertices, offset + positionByteOffset),
                                 readFloat(vertices, offset + positionByteOffset + 4),
                                 readFloat(vertices, offset + positionByteOffset + 8))
            if p.x.isFinite, p.y.isFinite, p.z.isFinite {
                lo = SIMD3(min(lo.x, p.x), min(lo.y, p.y), min(lo.z, p.z))
                hi = SIMD3(max(hi.x, p.x), max(hi.y, p.y), max(hi.z, p.z))
            }
            offset += vertexStride
        }
        let bounds: [Float] = [lo.x, lo.y, lo.z, hi.x, hi.y, hi.z]

        // 1) 顶点 + 索引
        var blob = Data(capacity: 8 + vertices.count + indices.count * 4)
        appendUInt32(&blob, UInt32(vertexCount))
        appendUInt32(&blob, UInt32(indices.count))
        blob.append(vertices)
        for index in indices { appendUInt32(&blob, index) }
        let binURL = localRoot.appendingPathComponent("\(level).terrain.bin")
        try blob.write(to: binURL, options: .atomic)

        // 2) 元数据（引擎按 material 分组选着色器家族）
        let meta: [String: Any] = [
            "level": level,
            "stride": vertexStride,
            "vertexCount": vertexCount,
            "indexCount": indices.count,
            "ranges": ranges,
        ]
        let metaURL = localRoot.appendingPathComponent("\(level).terrain.meta.json")
        try JSONSerialization.data(withJSONObject: meta).write(to: metaURL, options: .atomic)

        // 3) 纯地形 manifest：ranges 留空，引擎就不去找 .verts/.idx
        let manifest: [String: Any] = [
            "level": level,
            "seaLevel": -5.0,
            "vertices": vertexCount,
            "indices": indices.count,
            "stride": vertexStride,
            "bounds": bounds,
            "focus": bounds,
            "ranges": [Any](),
        ]
        let manifestURL = localRoot.appendingPathComponent("\(level).json")
        try JSONSerialization.data(withJSONObject: manifest).write(to: manifestURL, options: .atomic)

        // 4) 材质表：原版整关共用一张，缺了就借包内那份，否则状态栏会显示“材质 —”
        let materialURL = localRoot.appendingPathComponent("\(level).materials.json")
        if !FileManager.default.fileExists(atPath: materialURL.path) {
            let fallback = localRoot.appendingPathComponent("CandleSpace.materials.json")
            if FileManager.default.fileExists(atPath: fallback.path) {
                try? FileManager.default.copyItem(at: fallback, to: materialURL)
            }
        }

        return (vertexCount, indices.count)
    }

    // MARK: - 小工具

    private static func readFloat(_ data: Data, _ offset: Int) -> Float {
        guard offset >= 0, offset + 4 <= data.count else { return .nan }
        let base = data.startIndex + offset
        let bits = UInt32(data[base]) | (UInt32(data[base + 1]) << 8)
            | (UInt32(data[base + 2]) << 16) | (UInt32(data[base + 3]) << 24)
        return Float(bitPattern: bits)
    }

    private static func appendUInt32(_ data: inout Data, _ value: UInt32) {
        data.append(UInt8(value & 0xFF))
        data.append(UInt8((value >> 8) & 0xFF))
        data.append(UInt8((value >> 16) & 0xFF))
        data.append(UInt8((value >> 24) & 0xFF))
    }
}

extension Notification.Name {
    /// 游戏原始 `Data` 已经转成引擎资源，界面可以并关卡列表了。
    static let skyGameAssetsReady = Notification.Name("SkyGameAssetsReady")
}

/// 关卡中文名。生成出来的关卡没有现成名字，这里补一份；没收录的直接用目录名。
enum LevelNames {
    static func chinese(_ id: String) -> String {
        table[id] ?? id
    }

    private static let table: [String: String] = [
        "CandleSpace": "烛窟",
        "CandleSpaceEnd": "烛窟终章",
        "CarryLand": "运土",
        "CarryLand2": "运土 二",
        "CarryLand3": "运土 三",
        "Dawn": "黎明",
        "DayEnd": "白昼终章",
        "DayHubCave": "白昼洞窟",
        "Dusk": "黄昏",
        "DuskGraveyard": "黄昏墓园",
        "DuskMid": "黄昏中枢",
        "Dusk_CrabField": "螃蟹田",
        "HubReveal": "云巢",
        "Night": "夜",
        "NightEnd": "夜终章",
        "NightEntrance": "夜入口",
        "Prairie_ButterflyFields": "蝶原",
        "Prairie_Cave": "草原洞窟",
        "Prairie_NestAndKeeper": "巢与守望者",
        "Prairie_Village": "草原村",
        "Rain": "雨林",
        "RainEnd": "雨林终章",
        "RainForest": "雨林深处",
        "RainMid": "雨林中枢",
        "SkyHub2": "云巢 二",
        "Storm": "风暴",
        "StormEnd": "风暴终章",
        "Sunset": "日落",
        "SunsetEnd": "日落终章",
        "SunsetEnd2": "日落终章 二",
        "SunsetRace": "日落赛道",
        "TitleWater": "标题水面",
        "WorldEmpty": "空世界",
        "Dawn_TrialsAir": "风试炼",
        "Dawn_TrialsEarth": "土试炼",
        "Night_JarCave": "罐洞",
        "AR_WheatField": "麦田",
    ]
}
