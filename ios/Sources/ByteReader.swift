import Foundation

/// Bounds-checked little-endian reader over a `Data` slice.
///
/// The original binary formats (TGCL / LVL0 / Terrain) are little-endian and
/// contain nested, variable-length records, so every read is validated instead
/// of trusting offsets from the file header.
enum ByteReadError: Error, CustomStringConvertible {
    case outOfBounds(offset: Int, need: Int, have: Int)
    case badMagic(expected: String, got: String, offset: Int)
    case unterminatedString(offset: Int)
    case invalid(String)

    var description: String {
        switch self {
        case let .outOfBounds(offset, need, have):
            return "read out of bounds at \(offset): need \(need) byte(s), only \(have) left"
        case let .badMagic(expected, got, offset):
            return "bad magic at \(offset): expected \(expected), got \(got)"
        case let .unterminatedString(offset):
            return "unterminated C string starting at \(offset)"
        case let .invalid(message):
            return "invalid format: \(message)"
        }
    }
}

struct ByteReader {
    let data: Data
    private(set) var pos: Int

    init(_ data: Data, pos: Int = 0) {
        self.data = data
        self.pos = pos
    }

    var count: Int { data.count }
    var remaining: Int { max(0, data.count - pos) }
    var isAtEnd: Bool { pos >= data.count }

    private mutating func require(_ n: Int) throws {
        guard n >= 0, pos + n <= data.count else {
            throw ByteReadError.outOfBounds(offset: pos, need: n, have: remaining)
        }
    }

    mutating func seek(to offset: Int) throws {
        guard offset >= 0, offset <= data.count else {
            throw ByteReadError.outOfBounds(offset: offset, need: 0, have: data.count)
        }
        pos = offset
    }

    mutating func skip(_ n: Int) throws {
        try require(n)
        pos += n
    }

    mutating func u8() throws -> UInt8 {
        try require(1)
        defer { pos += 1 }
        return data[pos]
    }

    mutating func u16() throws -> UInt16 {
        try require(2)
        defer { pos += 2 }
        return UInt16(data[pos]) | (UInt16(data[pos + 1]) << 8)
    }

    mutating func u32() throws -> UInt32 {
        try require(4)
        defer { pos += 4 }
        return UInt32(data[pos])
            | (UInt32(data[pos + 1]) << 8)
            | (UInt32(data[pos + 2]) << 16)
            | (UInt32(data[pos + 3]) << 24)
    }

    mutating func i32() throws -> Int32 {
        Int32(bitPattern: try u32())
    }

    mutating func f32() throws -> Float {
        Float(bitPattern: try u32())
    }

    mutating func u32(at offset: Int) throws -> UInt32 {
        try require(offset - pos)
        guard offset + 4 <= data.count else {
            throw ByteReadError.outOfBounds(offset: offset, need: 4, have: data.count - offset)
        }
        return UInt32(data[offset])
            | (UInt32(data[offset + 1]) << 8)
            | (UInt32(data[offset + 2]) << 16)
            | (UInt32(data[offset + 3]) << 24)
    }

    /// Copies `n` bytes starting at the cursor.
    mutating func bytes(_ n: Int) throws -> Data {
        try require(n)
        defer { pos += n }
        return data.subdata(in: pos..<(pos + n))
    }

    /// Skips a NUL-terminated string and returns its UTF-8 contents.
    mutating func cString() throws -> String {
        let start = pos
        var end = pos
        while end < data.count, data[end] != 0 { end += 1 }
        guard end < data.count else {
            throw ByteReadError.unterminatedString(offset: start)
        }
        pos = end + 1
        return String(decoding: data[start..<end], as: UTF8.self)
    }

    /// A u32 byte count followed by that many UTF-8 bytes. This is the string
    /// encoding inside `BstBaked.meshes` (bake names), and it is *not* the same
    /// as TGCL's NUL-terminated names.
    mutating func lengthPrefixedString(limit: Int = 1 << 20) throws -> String {
        let start = pos
        let length = Int(try u32())
        guard length <= limit else {
            throw ByteReadError.invalid("length-prefixed string claims \(length) bytes at \(start)")
        }
        return String(decoding: try bytes(length), as: UTF8.self)
    }

    /// A stable string for log output.
    func hex(at offset: Int, length: Int) -> String {
        guard offset >= 0, offset + length <= data.count else { return "<oob>" }
        return data.subdata(in: offset..<(offset + length)).map { String(format: "%02X", $0) }.joined()
    }
}

/// Small helpers used by the format layer.
enum FormatUtil {
    static func fourCC(_ value: UInt32) -> String {
        let bytes = [UInt8(value & 0xFF), UInt8((value >> 8) & 0xFF),
                     UInt8((value >> 16) & 0xFF), UInt8((value >> 24) & 0xFF)]
        return String(bytes: bytes, encoding: .ascii) ?? String(format: "%08X", value)
    }

    static func fourCC(_ value: UInt32, littleEndian: Bool) -> String {
        littleEndian ? fourCC(value) : fourCC(value.byteSwapped)
    }

    static func asciiUInt32(_ s: String) -> UInt32 {
        var result: UInt32 = 0
        for (i, b) in Array(s.utf8.prefix(4)).enumerated() {
            result |= UInt32(b) << (8 * i)
        }
        return result
    }

    static func roundUp(_ n: Int, to alignment: Int) -> Int {
        (n + alignment - 1) / alignment * alignment
    }
}
