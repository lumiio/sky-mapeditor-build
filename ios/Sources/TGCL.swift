import Foundation

/// Reader / editor for `Objects.level.bin` (magic "TGCL").
///
/// Nothing here is inferred any more. The editor ships its own TGCL reader in
/// `assets/runtime/server.cjs` (package `com.sky.editor`, 0.3.1-android-preview),
/// and this file mirrors it byte for byte. It was checked against all 33 real
/// `Objects.level.bin` files in that build: every one parses and lands exactly
/// on the declared file length.
///
/// Header — 44 bytes, magic + 10 × u32:
///
///     0  magic "TGCL"
///     4  version            == 1
///     8  classCount
///     12 fieldCount
///     16 nodeCount
///     20 reserved (the editor ignores it)
///     24 classTableOffset  (>= 44)
///     28 fieldTableOffset  (the class table comes first)
///     32 namePoolOffset
///     36 nodeAreaOffset
///     40 fileLength        == size of the file
///
/// Tables:
///
///     classes : classCount × 12 → { nameOffset, firstField, fieldCount }
///     fields  : fieldCount × 16 → { type, nameOffset, size, classIndex }
///     names   : NUL-terminated strings; `nameOffset` is a BYTE offset into the
///               pool, not an index into a string list. (An earlier revision of
///               this file treated it as an index and read the wrong names.)
///     nodes   : { classIndex u32, name cstr, then the class's fields in order }
///
/// Field types are only 0…3:
///
///     0 raw(size)   1 string   2 reference(u32)   3 array
///
/// An array is a u32 count followed by `count` entries. When the field's
/// `classIndex` is `0xFFFFFFFF` an entry is a u32 reference; otherwise an entry
/// is a nested struct of class `classIndex`, read with that class's field list.
///
/// Editing never re-serialises the file: a patch replaces the bytes of one
/// field in place and rewrites the length word at +40, so classes and fields
/// this code does not understand survive untouched. A patch must keep the same
/// byte length, because every internal offset in the file is absolute.
struct TGCLDocument {
    static let magicValue = FormatUtil.asciiUInt32("TGCL")
    /// `classIndex` that marks an array of object references.
    static let arrayReferenceMarker: UInt32 = 0xFFFF_FFFF
    static let headerSize = 44
    /// Offset of the total-length word, needed by every patch.
    static let lengthWordOffset = 40
    /// Guards against a self-referential class graph.
    static let maxClassDepth = 64

    enum FieldType: UInt32 {
        case raw = 0
        case string = 1
        case reference = 2
        case array = 3
    }

    struct Header: Equatable {
        var version: UInt32
        var classCount: UInt32
        var fieldCount: UInt32
        var nodeCount: UInt32
        var reserved: UInt32
        var classTableOffset: UInt32
        var fieldTableOffset: UInt32
        var namePoolOffset: UInt32
        var nodeAreaOffset: UInt32
        var fileLength: UInt32
    }

    struct ClassDef: Equatable {
        var name: String
        var firstField: UInt32
        var fieldCount: UInt32
    }

    struct FieldDef: Equatable {
        var index: Int
        var name: String
        var type: FieldType
        var size: UInt32
        var classIndex: UInt32
    }

    /// A decoded field value. `raw` widths map to exactly the shapes the editor
    /// presents: 1→u8, 2→u16, 4→bits32, 8→bits64 (shown as hex), 12/16→a 3/4
    /// float vector, 64→matrix4, anything else→opaque bytes.
    enum Value {
        case u8(UInt8)
        case u16(UInt16)
        case bits32(UInt32)
        case bits64(UInt64)
        case vector([Float])
        case matrix([Float])
        case bytes(Data)
        case string(String)
        case reference(UInt32)
        case array([Field])
        case structure([Field])

        var floats: [Float] {
            switch self {
            case let .vector(v), let .matrix(v): return v
            case let .bits32(b): return [Float(bitPattern: b)]
            case let .u8(b): return [Float(b)]
            case let .u16(b): return [Float(b)]
            case .bits64, .bytes, .string, .reference, .array, .structure: return []
            }
        }

        var isNumeric: Bool {
            switch self {
            case .u8, .u16, .bits32, .vector, .matrix: return true
            case .bits64, .bytes, .string, .reference, .array, .structure: return false
            }
        }

        var stringValue: String? {
            if case let .string(s) = self { return s }
            return nil
        }

        var referenceValue: UInt32? {
            if case let .reference(r) = self { return r }
            return nil
        }

        var arrayElements: [Field]? {
            if case let .array(items) = self { return items }
            return nil
        }

        var structureMembers: [Field]? {
            if case let .structure(members) = self { return members }
            return nil
        }
    }

    struct Field {
        var name: String
        /// Byte range inside the file; a patch replaces exactly this.
        var offset: Int
        var length: Int
        var value: Value
        var raw: Data

        var floats: [Float] { value.floats }
        var isNumeric: Bool { value.isNumeric }
        var arrayCount: Int? { value.arrayElements?.count }
        var reference: UInt32? { value.referenceValue }
        var string: String? { value.stringValue }

        /// This field and everything below it, depth first. Array elements and
        /// nested struct members are included, so a caller can look a name up
        /// without knowing where in the class graph it sits.
        func flattened(depth: Int = 0) -> [Field] {
            guard depth < TGCLDocument.maxClassDepth else { return [self] }
            var out: [Field] = [self]
            let kids = value.arrayElements ?? value.structureMembers ?? []
            for kid in kids {
                out.append(contentsOf: kid.flattened(depth: depth + 1))
            }
            return out
        }
    }

    struct Node {
        var className: String
        var name: String
        var classIndex: UInt32
        var recordOffset: Int
        var length: Int
        var fields: [Field]

        /// Flattened field list, nested structures included.
        func allFields() -> [Field] {
            fields.flatMap { $0.flattened() }
        }
    }

    private(set) var raw: Data
    let header: Header
    let classes: [ClassDef]
    let fields: [FieldDef]
    let nodes: [Node]

    // MARK: - Parsing

    init(data: Data) throws {
        raw = data
        var reader = ByteReader(data)

        guard try reader.u32() == Self.magicValue else {
            throw ByteReadError.badMagic(expected: "TGCL",
                                         got: reader.hex(at: 0, length: 4),
                                         offset: 0)
        }

        let version = try reader.u32()
        let classCount = try reader.u32()
        let fieldCount = try reader.u32()
        let nodeCount = try reader.u32()
        let reserved = try reader.u32()
        let classTableOffset = try reader.u32()
        let fieldTableOffset = try reader.u32()
        let namePoolOffset = try reader.u32()
        let nodeAreaOffset = try reader.u32()
        let fileLength = try reader.u32()

        let header = Header(version: version, classCount: classCount,
                            fieldCount: fieldCount, nodeCount: nodeCount,
                            reserved: reserved,
                            classTableOffset: classTableOffset,
                            fieldTableOffset: fieldTableOffset,
                            namePoolOffset: namePoolOffset,
                            nodeAreaOffset: nodeAreaOffset,
                            fileLength: fileLength)
        try Self.validate(header, fileLength: data.count)
        self.header = header

        let pool = data.subdata(in: Int(header.namePoolOffset)..<Int(header.nodeAreaOffset))

        // Field table first: the class table is validated against its length.
        var fieldDefs: [FieldDef] = []
        fieldDefs.reserveCapacity(Int(header.fieldCount))
        try reader.seek(to: Int(header.fieldTableOffset))
        for index in 0..<Int(header.fieldCount) {
            let typeRaw = try reader.u32()
            guard let type = FieldType(rawValue: typeRaw) else {
                throw ByteReadError.invalid("field \(index) uses type \(typeRaw); the format only defines 0…3")
            }
            let nameOffset = try reader.u32()
            let size = try reader.u32()
            let classIndex = try reader.u32()
            fieldDefs.append(FieldDef(index: index,
                                      name: try Self.name(at: nameOffset, pool: pool),
                                      type: type, size: size, classIndex: classIndex))
        }
        self.fields = fieldDefs

        var classDefs: [ClassDef] = []
        classDefs.reserveCapacity(Int(header.classCount))
        try reader.seek(to: Int(header.classTableOffset))
        for _ in 0..<Int(header.classCount) {
            let nameOffset = try reader.u32()
            let firstField = try reader.u32()
            let count = try reader.u32()
            guard Int(firstField) + Int(count) <= fieldDefs.count else {
                throw ByteReadError.invalid("class field range \(firstField)+\(count) runs past the \(fieldDefs.count)-entry field table")
            }
            classDefs.append(ClassDef(name: try Self.name(at: nameOffset, pool: pool),
                                      firstField: firstField, fieldCount: count))
        }
        self.classes = classDefs

        var nodeList: [Node] = []
        nodeList.reserveCapacity(Int(header.nodeCount))
        try reader.seek(to: Int(header.nodeAreaOffset))
        for _ in 0..<Int(header.nodeCount) {
            let start = reader.pos
            let classIndex = try reader.u32()
            guard Int(classIndex) < classDefs.count else {
                throw ByteReadError.invalid("node at \(start) names class \(classIndex), but only \(classDefs.count) classes exist")
            }
            let name = try reader.cString()
            let members = try Self.readFields(&reader, classes: classDefs, fields: fieldDefs,
                                              classIndex: classIndex, depth: 0)
            nodeList.append(Node(className: classDefs[Int(classIndex)].name,
                                 name: name, classIndex: classIndex,
                                 recordOffset: start, length: reader.pos - start,
                                 fields: members))
        }
        self.nodes = nodeList

        // The editor rejects a file that does not end exactly on its declared
        // length, so a mismatch here means the field codec is wrong. Fail loudly
        // instead of showing half a map.
        guard reader.pos == Int(header.fileLength) else {
            throw ByteReadError.invalid("node area ended at \(reader.pos) but the header declares \(header.fileLength) bytes")
        }
    }

    private static func validate(_ h: Header, fileLength: Int) throws {
        guard h.version == 1 else {
            throw ByteReadError.invalid("TGCL version \(h.version); only version 1 exists")
        }
        guard Int(h.fileLength) == fileLength else {
            throw ByteReadError.invalid("header file length \(h.fileLength) does not match the \(fileLength)-byte file")
        }
        guard h.classCount <= 10_000 else {
            throw ByteReadError.invalid("\(h.classCount) classes is beyond the editor's limit of 10000")
        }
        guard h.fieldCount <= 100_000 else {
            throw ByteReadError.invalid("\(h.fieldCount) fields is beyond the editor's limit of 100000")
        }
        guard h.nodeCount <= 1_000_000 else {
            throw ByteReadError.invalid("\(h.nodeCount) nodes is beyond the editor's limit of 1000000")
        }
        let classStart = Int(h.classTableOffset)
        let fieldStart = Int(h.fieldTableOffset)
        let namesStart = Int(h.namePoolOffset)
        let nodesStart = Int(h.nodeAreaOffset)
        guard classStart >= headerSize,
              classStart + Int(h.classCount) * 12 <= fieldStart,
              fieldStart + Int(h.fieldCount) * 16 <= namesStart,
              namesStart <= nodesStart,
              nodesStart <= fileLength else {
            throw ByteReadError.invalid("table offsets are inconsistent (class \(classStart), field \(fieldStart), names \(namesStart), nodes \(nodesStart), length \(fileLength))")
        }
    }

    private static func name(at offset: UInt32, pool: Data) throws -> String {
        let start = Int(offset)
        guard start < pool.count else {
            throw ByteReadError.invalid("name offset \(offset) is outside the \(pool.count)-byte name pool")
        }
        var end = start
        while end < pool.count, pool[pool.startIndex + end] != 0 { end += 1 }
        guard end < pool.count else {
            throw ByteReadError.invalid("name at pool offset \(offset) is not NUL-terminated")
        }
        return String(decoding: pool[(pool.startIndex + start)..<(pool.startIndex + end)], as: UTF8.self)
    }

    /// Reads one class's fields, recursing into nested structs and array entries.
    private static func readFields(_ reader: inout ByteReader,
                                   classes: [ClassDef],
                                   fields: [FieldDef],
                                   classIndex: UInt32,
                                   depth: Int) throws -> [Field] {
        guard depth <= maxClassDepth else {
            throw ByteReadError.invalid("class nesting deeper than \(maxClassDepth) at \(reader.pos)")
        }
        guard Int(classIndex) < classes.count else {
            throw ByteReadError.invalid("reference to class \(classIndex), which does not exist")
        }
        let cls = classes[Int(classIndex)]
        let first = Int(cls.firstField)
        guard first <= fields.count, first + Int(cls.fieldCount) <= fields.count else {
            throw ByteReadError.invalid("class \(cls.name) declares fields \(first)…\(first + Int(cls.fieldCount)) of \(fields.count)")
        }

        var out: [Field] = []
        out.reserveCapacity(Int(cls.fieldCount))
        for k in 0..<Int(cls.fieldCount) {
            let def = fields[first + k]
            let start = reader.pos
            let value: Value
            switch def.type {
            case .raw:
                let size = Int(def.size)
                value = Self.classify(try reader.bytes(size))
            case .string:
                value = .string(try reader.cString())
            case .reference:
                value = .reference(try reader.u32())
            case .array:
                let count = Int(try reader.u32())
                guard count <= 2_000_000 else {
                    throw ByteReadError.invalid("array \(def.name) claims \(count) entries at \(start)")
                }
                var items: [Field] = []
                items.reserveCapacity(min(count, 4096))
                for j in 0..<count {
                    let elementStart = reader.pos
                    if def.classIndex == arrayReferenceMarker {
                        // An entry is a u32 object reference.
                        let reference = try reader.u32()
                        items.append(Field(name: "[\(j)]", offset: elementStart,
                                           length: reader.pos - elementStart,
                                           value: .reference(reference), raw: Data()))
                    } else {
                        // An entry is a nested struct of class `def.classIndex`.
                        let members = try Self.readFields(&reader, classes: classes, fields: fields,
                                                          classIndex: def.classIndex, depth: depth + 1)
                        items.append(Field(name: "[\(j)]", offset: elementStart,
                                           length: reader.pos - elementStart,
                                           value: .structure(members), raw: Data()))
                    }
                }
                value = .array(items)
            }
            let end = reader.pos
            out.append(Field(name: def.name, offset: start, length: end - start,
                             value: value, raw: reader.data.subdata(in: start..<end)))
        }
        return out
    }

    /// Maps a raw byte string to the value shape the editor displays.
    private static func classify(_ bytes: Data) -> Value {
        switch bytes.count {
        case 1:
            return .u8(bytes[bytes.startIndex])
        case 2:
            return .u16(decodeUInt16(bytes))
        case 4:
            return .bits32(decodeUInt32(bytes))
        case 8:
            return .bits64(decodeUInt64(bytes))
        case 12, 16:
            let floats = decodeFloats(bytes)
            return floats.allSatisfy({ $0.isFinite }) ? .vector(floats) : .bytes(bytes)
        case 64:
            let floats = decodeFloats(bytes)
            return floats.allSatisfy({ $0.isFinite }) ? .matrix(floats) : .bytes(bytes)
        default:
            return .bytes(bytes)
        }
    }

    // MARK: - Little-endian decoding

    static func decodeUInt16(_ d: Data) -> UInt16 {
        guard d.count >= 2 else { return 0 }
        return UInt16(d[d.startIndex]) | (UInt16(d[d.startIndex + 1]) << 8)
    }

    static func decodeUInt32(_ d: Data) -> UInt32 {
        guard d.count >= 4 else { return 0 }
        let b = d.startIndex
        return UInt32(d[b]) | (UInt32(d[b + 1]) << 8)
            | (UInt32(d[b + 2]) << 16) | (UInt32(d[b + 3]) << 24)
    }

    static func decodeUInt64(_ d: Data) -> UInt64 {
        guard d.count >= 8 else { return 0 }
        let lo = UInt64(decodeUInt32(d))
        let hi = UInt64(decodeUInt32(d.dropFirst(4)))
        return lo | (hi << 32)
    }

    static func decodeFloats(_ d: Data) -> [Float] {
        var out: [Float] = []
        out.reserveCapacity(d.count / 4)
        var i = 0
        while i + 4 <= d.count {
            out.append(Float(bitPattern: decodeUInt32(d.dropFirst(i))))
            i += 4
        }
        return out
    }

    // MARK: - Lookups

    func nodes(ofClass className: String) -> [Node] {
        nodes.filter { $0.className == className }
    }

    func field(named name: String, in node: Node) -> Field? {
        node.allFields().first { $0.name == name }
    }

    // MARK: - Patching

    /// Returns a copy of the file with `replacement` written over the byte range
    /// of one field, then re-parses it to prove the result is still valid.
    ///
    /// The replacement must be the same length: every offset inside a TGCL file
    /// is absolute, so a resize would invalidate the class/field/node tables.
    func patched(offset: Int, length: Int, replacement: Data) throws -> TGCLDocument {
        guard offset >= 0, length >= 0, offset + length <= raw.count else {
            throw ByteReadError.outOfBounds(offset: offset, need: length, have: raw.count - offset)
        }
        guard replacement.count == length else {
            throw ByteReadError.invalid("a TGCL patch must keep its byte length (\(length)); got \(replacement.count). Resizing would break every absolute offset in the file.")
        }

        var out = Data()
        out.reserveCapacity(raw.count)
        out.append(raw.subdata(in: 0..<offset))
        out.append(replacement)
        out.append(raw.subdata(in: (offset + length)..<raw.count))

        // Only the length word could ever differ; keep it exact anyway.
        let newLength = UInt32(out.count)
        out[Self.lengthWordOffset + 0] = UInt8(newLength & 0xFF)
        out[Self.lengthWordOffset + 1] = UInt8((newLength >> 8) & 0xFF)
        out[Self.lengthWordOffset + 2] = UInt8((newLength >> 16) & 0xFF)
        out[Self.lengthWordOffset + 3] = UInt8((newLength >> 24) & 0xFF)

        return try TGCLDocument(data: out)
    }

    /// Writes one float inside a vector/matrix field.
    func settingFloat(of field: Field, at index: Int, to newValue: Float) throws -> TGCLDocument {
        guard field.isNumeric, index >= 0, index * 4 + 4 <= field.length else {
            throw ByteReadError.invalid("field \(field.name) is not a float vector of at least \(index + 1) components")
        }
        var replacement = field.raw
        let bits = newValue.bitPattern
        let at = replacement.startIndex + index * 4
        replacement[at + 0] = UInt8(bits & 0xFF)
        replacement[at + 1] = UInt8((bits >> 8) & 0xFF)
        replacement[at + 2] = UInt8((bits >> 16) & 0xFF)
        replacement[at + 3] = UInt8((bits >> 24) & 0xFF)
        return try patched(offset: field.offset, length: field.length, replacement: replacement)
    }

    // MARK: - Diagnostics

    func summary() -> String {
        var lines: [String] = []
        lines.append("TGCL v\(header.version) — \(nodes.count) 节点, \(classes.count) 类, \(fields.count) 字段")
        for node in nodes.prefix(64) {
            let described = node.fields.map { field -> String in
                switch field.value {
                case .array(let items): return "\(field.name):array[\(items.count)]"
                case .string: return "\(field.name):string"
                case .reference(let r): return "\(field.name):ref(\(r))"
                case .u8: return "\(field.name):u8"
                case .u16: return "\(field.name):u16"
                case .bits32: return "\(field.name):bits32"
                case .bits64: return "\(field.name):bits64"
                case .vector(let v): return "\(field.name):vec\(v.count)"
                case .matrix: return "\(field.name):matrix4"
                case .bytes(let b): return "\(field.name):raw\(b.count)"
                case .structure: return "\(field.name):struct"
                }
            }.joined(separator: ", ")
            lines.append("  \(node.className) '\(node.name)' @\(node.recordOffset): \(described)")
        }
        if nodes.count > 64 { lines.append("  …") }
        return lines.joined(separator: "\n")
    }
}
