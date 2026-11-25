import Foundation

/// LZ4 block-format codec, pure Swift.
///
/// The original LVL0 segments are stored with LZ4 block compression (the
/// Android build decompressed them with LZ4 before parsing the terrain). The
/// editor must also be able to re-compress a segment after a geometry edit, so
/// both directions live here; the decoder is the critical path at load time.
///
/// Reference: https://github.com/lz4/lz4/blob/dev/doc/lz4_Block_format.md
enum LZ4Error: Error, CustomStringConvertible {
    case truncated(String)
    case corrupt(String)

    var description: String {
        switch self {
        case let .truncated(where_): return "LZ4 stream truncated: \(where_)"
        case let .corrupt(where_): return "LZ4 stream corrupt: \(where_)"
        }
    }
}

enum LZ4 {
    /// Decompresses a block whose uncompressed length is not recorded — this is
    /// how `BstBaked.meshes` stores its `LOD0` section: a bare LZ4 block with no
    /// size prefix. `limit` bounds the output so a hostile block cannot exhaust
    /// memory.
    static func decompress(_ input: Data, limit: Int = 256 << 20) throws -> Data {
        let out = try decode(input, limit: limit)
        guard out.count <= limit else {
            throw LZ4Error.corrupt("decoded \(out.count) bytes, limit was \(limit)")
        }
        return out
    }

    /// Decompresses a block when the exact uncompressed size is known.
    static func decompress(_ input: Data, expectedSize: Int) throws -> Data {
        guard expectedSize >= 0 else { throw LZ4Error.corrupt("negative expected size") }
        let out = try decode(input, limit: expectedSize)
        guard out.count == expectedSize else {
            throw LZ4Error.corrupt("decoded \(out.count) bytes, expected \(expectedSize)")
        }
        return out
    }

    private static func decode(_ input: Data, limit: Int) throws -> Data {
        var out = [UInt8]()
        out.reserveCapacity(min(limit, 1 << 20))

        try input.withUnsafeBytes { (raw: UnsafeRawBufferPointer) throws in
            guard let base = raw.baseAddress?.assumingMemoryBound(to: UInt8.self) else {
                throw LZ4Error.truncated("empty input")
            }
            var i = 0
            let n = raw.count

            func readLength(baseLength: Int) throws -> Int {
                var length = baseLength
                if length == 15 {
                    while true {
                        guard i < n else { throw LZ4Error.truncated("length extension") }
                        let b = base[i]; i += 1
                        length += Int(b)
                        if b != 255 { break }
                    }
                }
                return length
            }

            while i < n {
                let token = base[i]; i += 1
                let literalLength = try readLength(baseLength: Int(token >> 4))
                guard literalLength <= n - i else {
                    throw LZ4Error.truncated("literal run at \(i)")
                }
                out.append(contentsOf: UnsafeBufferPointer(start: base + i, count: literalLength))
                i += literalLength

                // A block ends right after the literals of the final sequence.
                if i >= n { break }

                guard i + 2 <= n else { throw LZ4Error.truncated("match offset") }
                let offset = Int(base[i]) | (Int(base[i + 1]) << 8)
                i += 2
                guard offset > 0, offset <= out.count else {
                    throw LZ4Error.corrupt("match offset \(offset) at output \(out.count)")
                }
                let matchLength = try readLength(baseLength: Int(token & 0x0F)) + 4
                var src = out.count - offset
                guard matchLength <= limit - out.count else {
                    throw LZ4Error.corrupt("match overruns the \(limit)-byte limit")
                }
                for _ in 0..<matchLength {
                    out.append(out[src])
                    src += 1
                }
            }
        }

        return Data(out)
    }

    /// Compresses `input` into a valid LZ4 block. Greedy matching with a small
    /// hash table; deterministic and adequate for the segment sizes involved.
    static func compress(_ input: Data) -> Data {
        guard !input.isEmpty else { return Data() }
        let bytes = [UInt8](input)
        let n = bytes.count

        if n < 13 {
            return literalBlock(bytes)
        }

        var out = [UInt8]()
        out.reserveCapacity(n / 2 + 16)

        let hashBits = 16
        let hashSize = 1 << hashBits
        var table = [Int](repeating: 0, count: hashSize)
        table.withUnsafeMutableBufferPointer { buffer in
            for i in buffer.indices { buffer[i] = -1 }
        }

        func hash(_ p: Int) -> Int {
            let v = UInt32(bytes[p]) | (UInt32(bytes[p + 1]) << 8)
                | (UInt32(bytes[p + 2]) << 16) | (UInt32(bytes[p + 3]) << 24)
            return Int((v &* 2654435761) >> (32 - hashBits))
        }

        var anchor = 0
        var i = 0
        let matchLimit = n - 12 // last match must start at least 12 bytes before the end

        while i < matchLimit {
            let h = hash(i)
            let candidate = table[h]
            table[h] = i

            if candidate < 0 || i - candidate > 65535
                || bytes[candidate] != bytes[i]
                || bytes[candidate + 1] != bytes[i + 1]
                || bytes[candidate + 2] != bytes[i + 2]
                || bytes[candidate + 3] != bytes[i + 3] {
                i += 1
                continue
            }

            // Extend the match.
            var matchLength = 4
            while i + matchLength < n && bytes[candidate + matchLength] == bytes[i + matchLength] {
                matchLength += 1
            }
            // The 5 trailing bytes must remain literals.
            if i + matchLength > n - 5 {
                matchLength = n - 5 - i
                if matchLength < 4 {
                    i += 1
                    continue
                }
            }

            let literalLength = i - anchor
            let offset = i - candidate
            emitSequence(literalLength: literalLength, matchLength: matchLength - 4,
                         offset: offset, anchor: anchor, i: i, out: &out, bytes: bytes)

            // Insert hashes for the matched region.
            let matchEnd = i + matchLength
            var q = i + 1
            while q < matchEnd && q < matchLimit {
                table[hash(q)] = q
                q += 1
            }
            i = matchEnd
            anchor = i
        }

        let tail = n - anchor
        if tail > 0 {
            // Final literal run, with a zero match length token.
            out.append(UInt8(min(tail, 15) << 4))
            if tail >= 15 {
                var remaining = tail - 15
                while remaining >= 255 { out.append(255); remaining -= 255 }
                out.append(UInt8(remaining))
            }
            out.append(contentsOf: bytes[anchor..<n])
        }
        return Data(out)
    }

    private static func literalBlock(_ bytes: [UInt8]) -> Data {
        var out = [UInt8]()
        out.append(UInt8(min(bytes.count, 15) << 4))
        if bytes.count >= 15 {
            var remaining = bytes.count - 15
            while remaining >= 255 { out.append(255); remaining -= 255 }
            out.append(UInt8(remaining))
        }
        out.append(contentsOf: bytes)
        return Data(out)
    }

    private static func emitSequence(literalLength: Int, matchLength: Int, offset: Int,
                                     anchor: Int, i: Int, out: inout [UInt8], bytes: [UInt8]) {
        let tokenHigh = UInt8(min(literalLength, 15) << 4)
        let tokenLow = UInt8(min(matchLength, 15))
        out.append(tokenHigh | tokenLow)
        if literalLength >= 15 {
            var remaining = literalLength - 15
            while remaining >= 255 { out.append(255); remaining -= 255 }
            out.append(UInt8(remaining))
        }
        out.append(contentsOf: bytes[anchor..<i])
        out.append(UInt8(offset & 0xFF))
        out.append(UInt8((offset >> 8) & 0xFF))
        if matchLength >= 15 {
            var remaining = matchLength - 15
            while remaining >= 255 { out.append(255); remaining -= 255 }
            out.append(UInt8(remaining))
        }
    }
}
