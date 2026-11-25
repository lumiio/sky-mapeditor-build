import Foundation

/// Reader for `BstBaked.meshes` (magic "LVL0") — one map's baked geometry.
///
/// As with `TGCL`, this is no longer inferred: `assets/runtime/server.cjs` in
/// `com.sky.editor 0.3.1-android-preview` contains the reader, and this file
/// mirrors it. Two earlier assumptions were wrong and are called out below.
///
/// Container:
///
///     0    magic "LVL0"
///     4    version u32       51 or 52
///     8    sectionCount u8   (≤ 10)
///     9    3 bytes of padding
///     12   sectionCount × { tag[4], offset u32, length u32 }
///
/// The `LOD0` section is a **bare LZ4 block** — there is no uncompressed-size
/// word in front of it. (An earlier revision read one and produced garbage.)
///
/// Inside the decompressed `LOD0`, in order:
///
///   1. bakes: count u32; each { name (u32 length + UTF-8), guid u32,
///      submeshCount u32, uniform u8 }, each submesh { vertexCount u32,
///      indexBytes u32, light block (12 bytes when uniform, else
///      vertexCount × 12), index block (indexBytes) }
///   2. terrains: count u32; each { linkedId u32, flags u8, bounds 6×f32,
///      vertexCount u32, indexCount u32, vertices ×36, collision (u32 length +
///      bytes), gridBounds 6×f32, cellSize f32, dimensions 3×u32,
///      patchCount u32 + (count, raw) u32 pairs, edgeCount u32,
///      edgePairCount u32, edgeReferenceCount u32, pairs ×{u16,u16},
///      edge list ×u16, slot counts ×u32, then indices }
///   3. cloud, if the leading u32 is non-zero: origin 3×i32, dimensions 3×i32,
///      sparse block, active-block coordinates, three volume tables,
///      sunOcclusionScale f32, two resolutions u32, then a proxy mesh
///      (vertexCount ×16, indexCount ×u16)
///   4. skirts: count u32; each { vertexCount u32, vertices ×40, indexCount u32,
///      indices u16 }
///   5. occluders: count u32; each { vertexCount u32, indexCount u32,
///      vertices ×16, indices u16 }
///
/// The whole section must be consumed exactly; the editor refuses the file
/// otherwise, so an over- or under-run here is a parse bug, not a warning.
///
/// Vertices keep the game's own layout, which the Metal vertex descriptor
/// consumes unchanged:
///
///     +0  position float3     +12 normal snorm4      +16 materialIds u8×4
///     +20 weights u8×4        +24 light0 u8×4        +28 light1 u8×4
///     +32 light2 u8×4         +36 userData1 u8×4 (skirts only, stride 40)
///
/// The first 36 bytes of a skirt vertex are therefore identical to a terrain
/// vertex, which is what lets the renderer flatten both into one buffer.
struct LVL0Document {
    static let magicValue = FormatUtil.asciiUInt32("LVL0")
    static let acceptedVersions: Set<UInt32> = [51, 52]
    static let vertexStride = 36
    static let skirtStride = 40
    static let occluderStride = 16
    /// Bytes before the first section: magic + version + u8 count + 3 padding.
    static let directoryStart = 12
    /// The editor additionally requires every section to start past this.
    static let sectionFloor = 132

    struct Section: Equatable {
        var tag: String
        var offset: Int
        var length: Int
    }

    enum Kind: String {
        case terrain, cloud, skirt, occluder
    }

    struct Patch: Equatable {
        var count: UInt32
        var raw: UInt32
    }

    struct Terrain {
        var linkedId: UInt32
        var flags: UInt8
        var boundsMin: SIMD3<Float>
        var boundsMax: SIMD3<Float>
        var indexCount: Int
        var collisionBytes: Int
        var gridMin: SIMD3<Float>
        var gridMax: SIMD3<Float>
        var cellSize: Float
        var dimensions: SIMD3<UInt32>
        var patches: [Patch]
        var edgeCount: Int
        var edgePairCount: Int
        var edgeReferenceCount: Int
        /// True when the indices were rebuilt through the edge table instead of
        /// stored literally. No shipped map uses that path, so it is mirrored
        /// from the editor and flagged rather than trusted.
        var rebuiltFromEdgeTable: Bool
        var recordOffset: Int
    }

    struct Mesh {
        var kind: Kind
        var ordinal: Int
        /// Byte offset of this record inside the decompressed `LOD0`.
        var recordOffset: Int
        var vertexCount: Int
        var stride: Int
        /// Byte offset of the vertex stream inside the decompressed `LOD0`.
        var vertexOffset: Int
        var indices: [UInt32]
        /// Present only for `.terrain`.
        var terrain: Terrain?

        var triangleCount: Int { indices.count / 3 }
        var vertexByteCount: Int { vertexCount * stride }
        var id: String { "\(kind.rawValue)\(ordinal)" }
    }

    struct BakeSubmesh {
        var vertexCount: Int
        var indexBytes: Int
        var lightOffset: Int
        var indexOffset: Int
    }

    struct Bake {
        var name: String
        var guid: UInt32
        var isUniform: Bool
        var submeshes: [BakeSubmesh]
    }

    let version: UInt32
    let sections: [Section]
    /// The decompressed `LOD0` payload every `vertexOffset` refers to.
    let lod: Data
    let meshes: [Mesh]
    let bakes: [Bake]
    let warnings: [String]

    // MARK: - Parsing

    init(data: Data) throws {
        var reader = ByteReader(data)
        guard try reader.u32() == Self.magicValue else {
            throw ByteReadError.badMagic(expected: "LVL0",
                                         got: reader.hex(at: 0, length: 4), offset: 0)
        }
        let version = try reader.u32()
        guard Self.acceptedVersions.contains(version) else {
            throw ByteReadError.invalid("LVL0 version \(version); this build reads 51 and 52")
        }
        self.version = version

        let count = Int(try reader.u8())
        try reader.skip(3)
        guard count > 0, count <= 10 else {
            throw ByteReadError.invalid("section count \(count) is outside the editor's 1…10")
        }
        guard data.count >= Self.directoryStart + count * 12 else {
            throw ByteReadError.invalid("section directory truncated")
        }

        var warnings: [String] = []
        var sections: [Section] = []
        var seen = Set<String>()
        for _ in 0..<count {
            let tag = FormatUtil.fourCC(try reader.u32())
            let offset = Int(try reader.u32())
            let length = Int(try reader.u32())
            guard offset >= Self.directoryStart + count * 12,
                  length >= 0, offset + length <= data.count else {
                throw ByteReadError.invalid("section '\(tag)' claims \(offset)+\(length) in a \(data.count)-byte file")
            }
            guard seen.insert(tag).inserted else {
                throw ByteReadError.invalid("section '\(tag)' appears twice")
            }
            if offset < Self.sectionFloor {
                warnings.append("段 \(tag) 起始于 \(offset)，编辑器要求 ≥ \(Self.sectionFloor)")
            }
            sections.append(Section(tag: tag, offset: offset, length: length))
        }
        self.sections = sections

        guard let lod = sections.first(where: { $0.tag == "LOD0" }) else {
            throw ByteReadError.invalid("no LOD0 section; found \(sections.map(\.tag).joined(separator: ", "))")
        }
        let compressed = data.subdata(in: lod.offset..<(lod.offset + lod.length))
        let payload = try LZ4.decompress(compressed, limit: 1 << 28)
        self.lod = payload

        let parsed = try Self.parseLOD(payload)
        self.meshes = parsed.meshes
        self.bakes = parsed.bakes
        self.warnings = warnings + parsed.warnings
    }

    private struct LODContent {
        var meshes: [Mesh]
        var bakes: [Bake]
        var warnings: [String]
    }

    private static func parseLOD(_ lod: Data) throws -> LODContent {
        var r = ByteReader(lod)
        var warnings: [String] = []
        var meshes: [Mesh] = []
        var bakes: [Bake] = []

        // 1 — baked meshes (props): read for byte accounting and UI, not drawn.
        let bakeCount = try count(&r, limit: 100_000, name: "bake")
        for _ in 0..<bakeCount {
            let name = try r.lengthPrefixedString()
            let guid = try r.u32()
            let submeshCount = try count(&r, limit: 10_000, name: "bake submesh")
            let uniform = try r.u8()
            guard uniform <= 1 else {
                throw ByteReadError.invalid("bake '\(name)' has uniform flag \(uniform)")
            }
            var submeshes: [BakeSubmesh] = []
            submeshes.reserveCapacity(submeshCount)
            for _ in 0..<submeshCount {
                let vertexCount = try count(&r, limit: 2_000_000, name: "bake vertex")
                let indexBytes = try count(&r, limit: 20_000_000, name: "bake index byte")
                let lightLength = uniform == 1 ? 12 : vertexCount * 12
                let lightOffset = r.pos
                try r.skip(lightLength)
                let indexOffset = r.pos
                try r.skip(indexBytes)
                submeshes.append(BakeSubmesh(vertexCount: vertexCount, indexBytes: indexBytes,
                                             lightOffset: lightOffset, indexOffset: indexOffset))
            }
            bakes.append(Bake(name: name, guid: guid, isUniform: uniform == 1,
                              submeshes: submeshes))
        }

        // 2 — terrain surfaces.
        let terrainCount = try count(&r, limit: 100_000, name: "terrain")
        for ordinal in 0..<terrainCount {
            let recordOffset = r.pos
            let linkedId = try r.u32()
            let flags = try r.u8()
            let boundsMin = try vec3(&r)
            let boundsMax = try vec3(&r)
            let vertexCount = try count(&r, limit: 65_536, name: "terrain vertex")
            let indexCount = try count(&r, limit: 10_000_000, name: "terrain index")
            guard indexCount % 3 == 0 else {
                throw ByteReadError.invalid("terrain\(ordinal): \(indexCount) indices is not a triangle list")
            }
            let vertexOffset = r.pos
            try r.skip(vertexCount * Self.vertexStride)

            let collisionBytes = try count(&r, limit: 100_000_000, name: "terrain collision byte")
            try r.skip(collisionBytes)

            let gridMin = try vec3(&r)
            let gridMax = try vec3(&r)
            let cellSize = try r.f32()
            let dimensions = SIMD3(try r.u32(), try r.u32(), try r.u32())

            let patchCount = try count(&r, limit: 1_000_000, name: "terrain patch")
            var patches: [Patch] = []
            patches.reserveCapacity(patchCount)
            for _ in 0..<patchCount {
                patches.append(Patch(count: try r.u32(), raw: try r.u32()))
            }

            let edgeCount = try count(&r, limit: 1_000_000, name: "terrain edge slot")
            let edgePairCount = try count(&r, limit: 5_000_000, name: "terrain edge pair")
            let edgeReferenceCount = try count(&r, limit: 10_000_000, name: "terrain edge reference")

            var pairs: [(UInt16, UInt16)] = []
            pairs.reserveCapacity(edgePairCount)
            for _ in 0..<edgePairCount {
                pairs.append((try r.u16(), try r.u16()))
            }
            var edgeList: [UInt16] = []
            edgeList.reserveCapacity(edgeReferenceCount)
            for _ in 0..<edgeReferenceCount {
                edgeList.append(try r.u16())
            }
            var slotCounts: [UInt32] = []
            slotCounts.reserveCapacity(edgeCount)
            for _ in 0..<edgeCount {
                slotCounts.append(try r.u32())
            }

            var indices: [UInt32]
            let rebuilt = edgePairCount != 0
            if rebuilt {
                // The editor rebuilds the index stream from the edge table: each
                // entry names a slot-relative pair and which end of it to take.
                // No shipped map exercises this, so it is mirrored exactly and
                // reported as unverified.
                let patchSum = patches.reduce(0) { $0 + Int($1.count) }
                guard edgeReferenceCount == indexCount,
                      edgeCount == patchCount,
                      patchSum == edgeReferenceCount else {
                    throw ByteReadError.invalid("terrain\(ordinal): edge table counts disagree (patches \(patchSum), refs \(edgeReferenceCount), indices \(indexCount), slots \(edgeCount)/\(patchCount))")
                }
                var built = [UInt32](repeating: 0, count: indexCount)
                var slotBase = 0
                var slotIndex = 0
                var cursor = 0
                for patch in patches {
                    for _ in 0..<Int(patch.count) {
                        let code = edgeList[cursor]
                        let pairIndex = slotBase + Int(code >> 1)
                        guard pairIndex < pairs.count else {
                            throw ByteReadError.invalid("terrain\(ordinal): edge reference \(pairIndex) outside the \(pairs.count)-pair table")
                        }
                        let pair = pairs[pairIndex]
                        let value = (code & 1) == 0 ? pair.0 : pair.1
                        guard Int(value) < vertexCount else {
                            throw ByteReadError.invalid("terrain\(ordinal): edge points at vertex \(value) of \(vertexCount)")
                        }
                        built[cursor] = UInt32(value)
                        cursor += 1
                    }
                    if slotIndex < slotCounts.count {
                        slotBase += Int(slotCounts[slotIndex])
                        slotIndex += 1
                    }
                }
                indices = built
                warnings.append("地形\(ordinal) 通过边表重建索引（\(edgePairCount) 对 / \(edgeReferenceCount) 引用），出货样本中没有此路径")
            } else {
                indices = []
                indices.reserveCapacity(indexCount)
                for _ in 0..<indexCount {
                    let value = try r.u16()
                    guard Int(value) < vertexCount else {
                        throw ByteReadError.invalid("terrain\(ordinal): index \(value) outside \(vertexCount) vertices")
                    }
                    indices.append(UInt32(value))
                }
            }

            meshes.append(Mesh(
                kind: .terrain, ordinal: ordinal, recordOffset: recordOffset,
                vertexCount: vertexCount, stride: Self.vertexStride,
                vertexOffset: vertexOffset, indices: indices,
                terrain: Terrain(linkedId: linkedId, flags: flags,
                                 boundsMin: boundsMin, boundsMax: boundsMax,
                                 indexCount: indexCount, collisionBytes: collisionBytes,
                                 gridMin: gridMin, gridMax: gridMax, cellSize: cellSize,
                                 dimensions: dimensions, patches: patches,
                                 edgeCount: edgeCount, edgePairCount: edgePairCount,
                                 edgeReferenceCount: edgeReferenceCount,
                                 rebuiltFromEdgeTable: rebuilt,
                                 recordOffset: recordOffset)))
        }

        // 3 — cloud volume, present or not as a single flag.
        let cloudFlag = try r.u32()
        if cloudFlag != 0 {
            _ = try r.i32(); _ = try r.i32(); _ = try r.i32() // origin
            let dims = (Int(try r.i32()), Int(try r.i32()), Int(try r.i32()))
            guard dims.0 >= 0, dims.1 >= 0, dims.2 >= 0,
                  dims.0 <= 4096, dims.1 <= 4096, dims.2 <= 4096 else {
                throw ByteReadError.invalid("cloud dimensions \(dims) are implausible")
            }
            try r.skip(dims.0 * dims.1 * dims.2)             // sparse block
            let active = try count(&r, limit: 10_000_000, name: "cloud active block")
            try r.skip(active * 6)                            // active block coordinates
            for label in ["距离", "环境0", "环境1"] {
                let size = try count(&r, limit: 100_000_000, name: "cloud \(label) table byte")
                try r.skip(size)
            }
            _ = try r.f32()                                   // sun occlusion scale
            _ = try r.u32(); _ = try r.u32()                  // two resolutions
            let recordOffset = r.pos
            let vertexCount = try count(&r, limit: 65_536, name: "cloud vertex")
            let indexCount = try count(&r, limit: 10_000_000, name: "cloud index")
            let vertexOffset = r.pos
            try r.skip(vertexCount * Self.occluderStride)
            var indices: [UInt32] = []
            indices.reserveCapacity(indexCount)
            for _ in 0..<indexCount {
                let value = try r.u16()
                guard Int(value) < vertexCount else {
                    throw ByteReadError.invalid("cloud: index \(value) outside \(vertexCount) vertices")
                }
                indices.append(UInt32(value))
            }
            meshes.append(Mesh(kind: .cloud, ordinal: 0, recordOffset: recordOffset,
                               vertexCount: vertexCount, stride: Self.occluderStride,
                               vertexOffset: vertexOffset, indices: indices, terrain: nil))
        }

        // 4 — skirts. Stride 40: the same 36 bytes plus userData1 at +36.
        let skirtCount = try count(&r, limit: 100_000, name: "skirt")
        for ordinal in 0..<skirtCount {
            let recordOffset = r.pos
            let vertexCount = try count(&r, limit: 65_536, name: "skirt vertex")
            let vertexOffset = r.pos
            try r.skip(vertexCount * Self.skirtStride)
            let indexCount = try count(&r, limit: 10_000_000, name: "skirt index")
            guard indexCount % 3 == 0 else {
                throw ByteReadError.invalid("skirt\(ordinal): \(indexCount) indices is not a triangle list")
            }
            var indices: [UInt32] = []
            indices.reserveCapacity(indexCount)
            for _ in 0..<indexCount {
                let value = try r.u16()
                guard Int(value) < vertexCount else {
                    throw ByteReadError.invalid("skirt\(ordinal): index \(value) outside \(vertexCount) vertices")
                }
                indices.append(UInt32(value))
            }
            meshes.append(Mesh(kind: .skirt, ordinal: ordinal, recordOffset: recordOffset,
                               vertexCount: vertexCount, stride: Self.skirtStride,
                               vertexOffset: vertexOffset, indices: indices, terrain: nil))
        }

        // 5 — occluders (16-byte vertices; used for culling, not drawn).
        let occluderCount = try count(&r, limit: 100_000, name: "occluder")
        for ordinal in 0..<occluderCount {
            let recordOffset = r.pos
            let vertexCount = try count(&r, limit: 65_536, name: "occluder vertex")
            let indexCount = try count(&r, limit: 10_000_000, name: "occluder index")
            let vertexOffset = r.pos
            try r.skip(vertexCount * Self.occluderStride)
            var indices: [UInt32] = []
            indices.reserveCapacity(indexCount)
            for _ in 0..<indexCount {
                let value = try r.u16()
                guard Int(value) < vertexCount else {
                    throw ByteReadError.invalid("occluder\(ordinal): index \(value) outside \(vertexCount) vertices")
                }
                indices.append(UInt32(value))
            }
            meshes.append(Mesh(kind: .occluder, ordinal: ordinal, recordOffset: recordOffset,
                               vertexCount: vertexCount, stride: Self.occluderStride,
                               vertexOffset: vertexOffset, indices: indices, terrain: nil))
        }

        guard r.pos == lod.count else {
            throw ByteReadError.invalid("LOD0 has \(lod.count - r.pos) unread byte(s) after the last record; the record codec does not match")
        }
        return LODContent(meshes: meshes, bakes: bakes, warnings: warnings)
    }

    // MARK: - Access

    func meshes(of kind: Kind) -> [Mesh] {
        meshes.filter { $0.kind == kind }
    }

    func firstMesh(of kind: Kind) -> Mesh? {
        meshes.first { $0.kind == kind }
    }

    /// Vertex bytes of one mesh, sliced out of the decompressed `LOD0`.
    func vertexData(of mesh: Mesh) -> Data {
        let start = mesh.vertexOffset
        let end = start + mesh.vertexByteCount
        guard start >= 0, end <= lod.count else { return Data() }
        return lod.subdata(in: start..<end)
    }

    // MARK: - Helpers

    private static func count(_ r: inout ByteReader, limit: Int, name: String) throws -> Int {
        let start = r.pos
        let value = Int(try r.u32())
        guard value <= limit else {
            throw ByteReadError.invalid("\(name) count \(value) exceeds \(limit) at \(start)")
        }
        return value
    }

    private static func vec3(_ r: inout ByteReader) throws -> SIMD3<Float> {
        SIMD3(try r.f32(), try r.f32(), try r.f32())
    }

    var summary: String {
        var parts: [String] = []
        parts.append("LVL0 v\(version) — \(sections.count) 段 (\(sections.map(\.tag).joined(separator: "/"))), "
                     + "\(meshes.count) 几何, \(bakes.count) 烘焙")
        for mesh in meshes where mesh.kind != .occluder {
            parts.append("  \(mesh.id): \(mesh.vertexCount) 顶点 / \(mesh.triangleCount) 三角形, stride \(mesh.stride)")
        }
        let occluders = meshes(of: .occluder)
        if !occluders.isEmpty {
            parts.append("  occluder ×\(occluders.count): "
                         + "\(occluders.reduce(0) { $0 + $1.vertexCount }) 顶点")
        }
        return parts.joined(separator: "\n")
    }
}
