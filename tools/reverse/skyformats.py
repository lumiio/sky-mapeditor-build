"""Reference parsers for the Sky map editor formats — version 2, verified
against the editor's own implementation.

Provenance: the Android APK (com.sky.editor 0.3.1-android-preview) ships its
formats in `assets/runtime/server.cjs`, in two minified classes:

  * TGCL container  → `Objects.level.bin`  (class table, field table, name
    pool, node records; four field kinds 0..3)
  * LVL0 container  → `BstBaked.meshes`    (u8 section count + directory,
    `LOD0` section LZ4-compressed, bake/terrain/cloud/skirt/occluder records)

Everything below mirrors those parsers byte-for-byte, including their limits
and rejection rules, so the output can be trusted as "what the editor sees".
Where the two previously inferred layouts disagreed with the implementation,
the implementation wins and the old assumption is noted.

Layout summary
-------------
TGCL header (44 bytes = magic + 10 × u32):

    0  magic "TGCL"
    4  version            == 1
    8  classCount
    12 fieldCount
    16 nodeCount
    20 (unused by the parser)
    24 classTableOffset
    28 fieldTableOffset
    32 namePoolOffset
    36 nodeAreaOffset
    40 fileLength         == len(file)

  class table (classCount × 12): nameOffset, firstField, fieldCount
  field table (fieldCount × 16): type, nameOffset, size, classIndex
  name pool: NUL-terminated strings; `nameOffset` is a **byte offset** inside
             the pool (not an index), which is measured from namePoolOffset
  nodes: classIndex u32, name cstr, then the class's fields in order

Field kinds (type): 0 raw(size), 1 string, 2 reference(u32), 3 array
  - array: u32 count, then `count` entries
  - entry is a u32 when classIndex == 0xFFFFFFFF (object references)
  - otherwise an entry is a nested struct of class `classIndex`

Raw sizes map to values exactly as the editor presents them: 1→u8, 2→u16,
4→bits32 (uint/int/float), 8→bits64 (hex), 12/16→vector (3/4 floats),
64→matrix4, anything else→raw hex.
"""

from __future__ import annotations

import json
import struct
import sys
from dataclasses import dataclass, field
from pathlib import Path

TGCL_MAGIC = 0x4C434754  # b"TGCL" little-endian
LVL0_MAGIC = 0x304C564C  # b"LVL0" little-endian
ARRAY_REF_MARKER = 0xFFFFFFFF

VERTEX_STRIDE = 36
SKIRT_STRIDE = 40


class FormatError(Exception):
    pass


class Reader:
    def __init__(self, data: bytes, pos: int = 0, label: str = "binary"):
        self.data = data
        self.pos = pos
        self.label = label

    @property
    def remaining(self) -> int:
        return len(self.data) - self.pos

    def need(self, n: int) -> None:
        if n < 0 or self.pos + n > len(self.data):
            raise FormatError(f"{self.label}: out of bounds @0x{self.pos:x}, need {n}")

    def u8(self) -> int:
        self.need(1)
        v = self.data[self.pos]
        self.pos += 1
        return v

    def u16(self) -> int:
        self.need(2)
        v = struct.unpack_from("<H", self.data, self.pos)[0]
        self.pos += 2
        return v

    def u32(self) -> int:
        self.need(4)
        v = struct.unpack_from("<I", self.data, self.pos)[0]
        self.pos += 4
        return v

    def i32(self) -> int:
        self.need(4)
        v = struct.unpack_from("<i", self.data, self.pos)[0]
        self.pos += 4
        return v

    def f32(self) -> float:
        self.need(4)
        v = struct.unpack_from("<f", self.data, self.pos)[0]
        self.pos += 4
        return v

    def vec3(self) -> tuple[float, float, float]:
        return (self.f32(), self.f32(), self.f32())

    def take(self, n: int) -> bytes:
        self.need(n)
        v = self.data[self.pos:self.pos + n]
        self.pos += n
        return v

    def cstr(self) -> str:
        end = self.data.find(b"\x00", self.pos)
        if end < 0:
            raise FormatError(f"{self.label}: unterminated string @0x{self.pos:x}")
        raw = self.take(end - self.pos)
        self.take(1)
        return raw.decode("utf-8", "replace")

    def string(self) -> str:
        return self.take(self.count(1 << 20)).decode("utf-8", "replace")

    def count(self, limit: int = 2_000_000) -> int:
        v = self.u32()
        if v > limit:
            raise FormatError(f"{self.label}: implausible count {v} @0x{self.pos - 4:x}")
        return v


# ---------------------------------------------------------------------------
# TGCL — Objects.level.bin
# ---------------------------------------------------------------------------

@dataclass
class FieldDef:
    index: int
    name: str
    type: int
    size: int
    class_index: int


@dataclass
class Field:
    id: str
    name: str
    kind: str          # u8/u16/bits32/bits64/vector/matrix4/raw/string/reference/array
    offset: int
    length: int
    value: object = None
    raw: bytes = b""
    children: list["Field"] = field(default_factory=list)


@dataclass
class Node:
    id: int
    name: str
    class_name: str
    class_index: int
    offset: int
    length: int
    fields: list[Field] = field(default_factory=list)


@dataclass
class TGCL:
    path: str
    version: int
    classes: list[tuple[str, int, int]]
    fields: list[FieldDef]
    nodes: list[Node]
    warnings: list[str]

    @staticmethod
    def parse(data: bytes, path: str = "<memory>") -> "TGCL":
        r = Reader(data, label="Objects.level.bin")
        if r.take(4) != b"TGCL":
            raise FormatError("Objects 不是 TGCL 格式")
        header = [r.u32() for _ in range(10)]
        version, class_count, field_count, node_count, _unused, \
            class_off, field_off, names_off, nodes_off, file_len = header
        if version != 1 or file_len != len(data):
            raise FormatError("TGCL 头部校验失败（版本或文件长度）")
        if class_count > 10_000 or field_count > 100_000 or node_count > 1_000_000:
            raise FormatError("TGCL 数量超限")
        if not (class_off >= 44 and class_off + class_count * 12 <= field_off
                and field_off + field_count * 16 <= names_off
                and names_off <= nodes_off <= file_len):
            raise FormatError("TGCL 段偏移非法")

        pool = data[names_off:nodes_off]

        def name_at(off: int) -> str:
            if off >= len(pool):
                raise FormatError(f"名称池偏移无效 0x{off:x}")
            end = pool.find(b"\x00", off)
            if end < 0:
                raise FormatError("名称池字符串截断")
            return pool[off:end].decode("utf-8", "replace")

        fields: list[FieldDef] = []
        r.pos = field_off
        for i in range(field_count):
            ftype = r.u32()
            name = name_at(r.u32())
            size = r.u32()
            class_index = r.u32()
            if ftype > 3:
                raise FormatError(f"未确认的 TGCL 字段类型 {ftype}")
            fields.append(FieldDef(i, name, ftype, size, class_index))

        classes: list[tuple[str, int, int]] = []
        r.pos = class_off
        for _ in range(class_count):
            name = name_at(r.u32())
            first = r.u32()
            count = r.u32()
            if first + count > len(fields):
                raise FormatError("类字段范围无效")
            classes.append((name, first, count))

        nodes: list[Node] = []
        r.pos = nodes_off
        for i in range(node_count):
            start = r.pos
            class_index = r.u32()
            if class_index >= len(classes):
                raise FormatError(f"无效类索引 {class_index}")
            node_name = r.cstr()
            node = Node(i, node_name, classes[class_index][0], class_index,
                        start, 0, TGCL._read_fields(r, classes, fields, class_index, f"n{i}", 0))
            node.length = r.pos - start
            nodes.append(node)

        if r.pos != file_len:
            raise FormatError(f"TGCL 剩余 {file_len - r.pos} 字节，拒绝不完整解析")
        return TGCL(path, version, classes, fields, nodes, [])

    @staticmethod
    def _read_fields(r: Reader, classes, fields: list[FieldDef], class_index: int,
                     prefix: str, depth: int) -> list[Field]:
        if depth > 64:
            raise FormatError("递归类结构无效")
        _name, first, count = classes[class_index]
        out: list[Field] = []
        for k in range(count):
            f = fields[first + k]
            start = r.pos
            kind, value, children = "raw", None, []
            if f.type == 0:
                size = f.size
                raw = r.take(size)
                if size == 1:
                    kind, value = "u8", raw[0]
                elif size == 2:
                    kind, value = "u16", struct.unpack_from("<H", raw, 0)[0]
                elif size == 4:
                    kind = "bits32"
                    value = {"uint": struct.unpack_from("<I", raw, 0)[0],
                             "int": struct.unpack_from("<i", raw, 0)[0],
                             "float": struct.unpack_from("<f", raw, 0)[0]}
                elif size == 8:
                    kind, value = "bits64", raw.hex()
                elif size in (12, 16, 64):
                    floats = list(struct.unpack_from(f"<{size // 4}f", raw, 0))
                    if all(_finite(v) for v in floats):
                        kind = "matrix4" if size == 64 else "vector"
                        value = floats
                    else:
                        kind = "raw"
                else:
                    kind = "raw"
            elif f.type == 1:
                kind, value = "string", r.cstr()
            elif f.type == 2:
                kind, value = "reference", r.u32()
            else:
                kind = "array"
                n = r.count()
                items = []
                for j in range(n):
                    if f.class_index == ARRAY_REF_MARKER:
                        off = r.pos
                        ref = r.u32()
                        items.append(Field(f"{prefix}/p{k}/a{j}", f"[{j}]", "reference",
                                           off, 4, ref, r.data[off:r.pos]))
                    else:
                        off = r.pos
                        kids = TGCL._read_fields(r, classes, fields, f.class_index,
                                                 f"{prefix}/p{k}/a{j}", depth + 1)
                        items.append(Field(f"{prefix}/p{k}/a{j}", f"[{j}]", "struct",
                                           off, r.pos - off, None, b"", kids))
                value = items
            out.append(Field(f"{prefix}/p{k}", f.name, kind, start, r.pos - start,
                             value, r.data[start:r.pos], children))
        return out

    # -- helpers ----------------------------------------------------------

    def find(self, class_name: str) -> list[Node]:
        return [n for n in self.nodes if n.class_name == class_name]

    def field_of(self, node: Node, name: str) -> Field | None:
        for f in node.fields:
            if f.name == name:
                return f
        return None

    def summary(self, limit: int = 40) -> str:
        lines = [f"TGCL v{self.version} — {len(self.nodes)} nodes, "
                 f"{len(self.classes)} classes, {len(self.fields)} fields"]
        for node in self.nodes[:limit]:
            parts = []
            for f in node.fields:
                if f.kind == "array":
                    parts.append(f"{f.name}:array[{len(f.value)}]")
                elif f.kind in ("u8", "u16", "bits32", "vector", "matrix4"):
                    parts.append(f"{f.name}:{f.kind}")
                else:
                    parts.append(f"{f.name}:{f.kind}")
            lines.append(f"  {node.class_name} {node.name!r} @0x{node.offset:x}: {', '.join(parts)}")
        if len(self.nodes) > limit:
            lines.append("  …")
        return "\n".join(lines)


def _finite(v: float) -> bool:
    return v == v and v not in (float("inf"), float("-inf"))


# ---------------------------------------------------------------------------
# LVL0 — BstBaked.meshes
# ---------------------------------------------------------------------------

@dataclass
class Section:
    tag: str
    offset: int
    length: int


@dataclass
class Geometry:
    id: str
    kind: str          # terrain / cloud / skirt / occluder
    name: str
    vertex_count: int
    index_count: int
    stride: int
    vertex_offset: int
    indices: list[int]
    metadata: dict = field(default_factory=dict)


@dataclass
class LVL0:
    path: str
    version: int
    sections: list[Section]
    lod: bytes
    geometries: list[Geometry]
    bakes: list[dict]

    @staticmethod
    def parse(data: bytes, path: str = "<memory>") -> "LVL0":
        r = Reader(data, label="BstBaked.meshes")
        if r.take(4) != b"LVL0":
            raise FormatError("Meshes 不是 LVL0 格式")
        version = r.u32()
        if version not in (51, 52):
            raise FormatError(f"meshes 版本需为 51/52，实际 {version}")
        count = r.u8()
        r.take(3)
        if count > 10:
            raise FormatError("LVL0 目录数量无效")
        if len(data) < 132:
            raise FormatError("LVL0 目录头截断")
        sections: list[Section] = []
        for _ in range(count):
            tag = r.take(4).decode("ascii", "replace")
            offset = r.u32()
            length = r.u32()
            if offset < 132 or offset + length > len(data):
                raise FormatError(f"LVL0 段 {tag} 越界")
            sections.append(Section(tag, offset, length))
        tags = [s.tag for s in sections]
        if len(set(tags)) != len(tags):
            raise FormatError("LVL0 段重复")
        lod_section = next((s for s in sections if s.tag == "LOD0"), None)
        if not lod_section:
            raise FormatError("找不到 LOD0")
        lod = lz4_decompress(data[lod_section.offset:lod_section.offset + lod_section.length])

        geometries, bakes = LVL0._parse_lod(lod)
        return LVL0(path, version, sections, lod, geometries, bakes)

    @staticmethod
    def _parse_lod(lod: bytes) -> tuple[list[Geometry], list[dict]]:
        r = Reader(lod, label="LOD0")
        geometries: list[Geometry] = []
        bakes: list[dict] = []

        bake_count = r.count(100_000)
        for i in range(bake_count):
            name = r.string()
            guid = r.u32()
            submesh_count = r.count(10_000)
            uniform = r.u8()
            if uniform > 1:
                raise FormatError("烘焙标记无效")
            subs = []
            for _ in range(submesh_count):
                vertex_count = r.count()
                index_bytes = r.count(20_000_000)
                light_len = 12 if uniform else vertex_count * 12
                light_off = r.pos
                r.take(light_len)
                index_off = r.pos
                r.take(index_bytes)
                subs.append({"vertexCount": vertex_count, "indexBytes": index_bytes,
                             "lightOffset": light_off, "indexOffset": index_off})
            bakes.append({"name": name, "guid": guid, "uniform": bool(uniform), "submeshes": subs})

        terrain_count = r.count(100_000)
        for i in range(terrain_count):
            record_off = r.pos
            linked = r.u32()
            flags = r.u8()
            bounds = (*r.vec3(), *r.vec3())
            vertex_count = r.count(65_536)
            index_count = r.count(10_000_000)
            if index_count % 3:
                raise FormatError(f"terrain{i}: 索引数 {index_count} 不是 3 的倍数")
            vertex_off = r.pos
            r.take(vertex_count * 36)
            collision_bytes = r.count(100_000_000)
            r.take(collision_bytes)
            grid_min = r.vec3()
            grid_max = r.vec3()
            cell_size = r.f32()
            dimensions = (r.u32(), r.u32(), r.u32())
            patch_count = r.count(1_000_000)
            patches = []
            for _ in range(patch_count):
                patches.append({"count": r.u32(), "raw": r.u32()})
            edge_count = r.count(1_000_000)
            edge_table = r.count(5_000_000)
            edge_refs = r.count(10_000_000)
            edge_pairs = [(r.u16(), r.u16()) for _ in range(edge_table)]
            edge_list = [r.u16() for _ in range(edge_refs)]
            slot_counts = [r.u32() for _ in range(edge_count)]
            indices: list[int]
            if edge_table:
                if edge_refs != index_count or edge_count != patch_count \
                        or sum(p["count"] for p in patches) != edge_refs:
                    raise FormatError(f"terrain{i}: 地形边表计数不一致")
                indices = [0] * index_count
                k = z = 0
                for patch in patches:
                    for _ in range(patch["count"]):
                        code = edge_list[z]
                        pair = edge_pairs[k + (code >> 1)] if k + (code >> 1) < len(edge_pairs) else None
                        if pair is None or pair[code & 1] >= vertex_count:
                            raise FormatError(f"terrain{i}: 地形边引用无效")
                        indices[z] = pair[code & 1]
                        z += 1
                    k += slot_counts[0] if slot_counts else 0
                    if slot_counts:
                        slot_counts = slot_counts[1:]
            else:
                indices = []
                for _ in range(index_count):
                    idx = r.u16()
                    if idx >= vertex_count:
                        raise FormatError(f"terrain{i}: 索引越界 {idx}")
                    indices.append(idx)
            geometries.append(Geometry(
                id=f"terrain{i}", kind="terrain", name=f"terrain{i}",
                vertex_count=vertex_count, index_count=index_count, stride=36,
                vertex_offset=vertex_off, indices=indices,
                metadata={"linkedId": linked, "flags": flags, "bounds": bounds,
                          "collisionBytes": collision_bytes,
                          "gridBounds": (*grid_min, *grid_max),
                          "cellSize": cell_size, "dimensions": dimensions,
                          "patchCount": patch_count, "patches": patches,
                          "edgeCount": edge_count, "recordOffset": record_off}))

        cloud_flag = r.u32()
        if cloud_flag:
            r.i32(), r.i32(), r.i32()          # origin
            dims = (r.i32(), r.i32(), r.i32())
            sparse = r.take(_prod(dims))
            active = r.count(10_000_000)
            r.take(active * 6)
            chunks = [r.count(100_000_000) for _ in range(3)]
            for size in chunks:
                r.take(size)
            r.f32()                             # sun occlusion scale
            r.u32(), r.u32()                    # resolutions
            vcount = r.count(65_536)
            icount = r.count(10_000_000)
            r.take(vcount * 16)
            for _ in range(icount):
                r.u16()

        skirt_count = r.count(100_000)
        for i in range(skirt_count):
            record_off = r.pos
            vertex_count = r.count(65_536)
            vertex_off = r.pos
            r.take(vertex_count * 40)
            index_count = r.count(10_000_000)
            if index_count % 3:
                raise FormatError(f"skirt{i}: 三角形数量无效")
            indices = []
            for _ in range(index_count):
                idx = r.u16()
                if idx >= vertex_count:
                    raise FormatError(f"skirt{i}: 索引越界")
                indices.append(idx)
            geometries.append(Geometry(
                id=f"skirt{i}", kind="skirt", name=f"skirt{i}",
                vertex_count=vertex_count, index_count=index_count, stride=40,
                vertex_offset=vertex_off, indices=indices,
                metadata={"recordOffset": record_off}))

        occluder_count = r.count(100_000)
        for i in range(occluder_count):
            record_off = r.pos
            vertex_count = r.count(65_536)
            index_count = r.count(10_000_000)
            vertex_off = r.pos
            r.take(vertex_count * 16)
            indices = []
            for _ in range(index_count):
                idx = r.u16()
                if idx >= vertex_count:
                    raise FormatError(f"occluder{i}: 索引越界")
                indices.append(idx)
            geometries.append(Geometry(
                id=f"occluder{i}", kind="occluder", name=f"occluder{i}",
                vertex_count=vertex_count, index_count=index_count, stride=16,
                vertex_offset=vertex_off, indices=indices,
                metadata={"recordOffset": record_off}))

        if r.pos != len(lod):
            raise FormatError(f"LOD0 未解析数据 {len(lod) - r.pos} 字节")
        return geometries, bakes

    def first(self, kind: str) -> Geometry | None:
        return next((g for g in self.geometries if g.kind == kind), None)


def _prod(values) -> int:
    out = 1
    for v in values:
        out *= v
    return out


def lz4_decompress(data: bytes, max_size: int = 256 * 1024 * 1024) -> bytes:
    """LZ4 block decoder matching the editor's `fr()` (no size prefix)."""
    out = bytearray()
    i = 0
    n = len(data)
    while i < n:
        token = data[i]
        i += 1
        literal = token >> 4
        if literal == 15:
            while True:
                if i >= n:
                    raise FormatError("LZ4 长度截断")
                b = data[i]
                i += 1
                literal += b
                if b != 255:
                    break
        if i + literal > n:
            raise FormatError("LZ4 字面量截断")
        out += data[i:i + literal]
        i += literal
        if i == n:
            break
        if i + 2 > n:
            raise FormatError("LZ4 偏移截断")
        offset = data[i] | (data[i + 1] << 8)
        i += 2
        if not 0 < offset <= len(out):
            raise FormatError(f"LZ4 匹配偏移无效 {offset}")
        match = token & 0x0F
        if match == 15:
            while True:
                if i >= n:
                    raise FormatError("LZ4 匹配长度截断")
                b = data[i]
                i += 1
                match += b
                if b != 255:
                    break
        match += 4
        src = len(out) - offset
        for _ in range(match):
            out.append(out[src])
            src += 1
        if len(out) > max_size:
            raise FormatError("LZ4 解压超限")
    if len(out) >= max_size:
        raise FormatError("LZ4 解压超限")
    return bytes(out)


# ---------------------------------------------------------------------------
# Map directory helper + CLI
# ---------------------------------------------------------------------------

def load_map_dir(directory: Path) -> tuple[TGCL | None, LVL0 | None, list[str]]:
    warnings: list[str] = []
    level = directory / "Objects.level.bin"
    meshes = directory / "BstBaked.meshes"
    tgcl = TGCL.parse(level.read_bytes(), str(level)) if level.exists() else None
    if tgcl is None:
        warnings.append(f"missing {level}")
    lvl0 = LVL0.parse(meshes.read_bytes(), str(meshes)) if meshes.exists() else None
    if lvl0 is None:
        warnings.append(f"missing {meshes}")
    return tgcl, lvl0, warnings


def main(argv: list[str]) -> int:
    if len(argv) < 2:
        print("usage: skyformat.py <map-dir|Objects.level.bin>", file=sys.stderr)
        return 2
    target = Path(argv[1])
    if target.is_dir():
        tgcl, lvl0, warnings = load_map_dir(target)
        if tgcl:
            print(tgcl.summary())
        if lvl0:
            print(f"LVL0 v{lvl0.version}: {len(lvl0.sections)} sections "
                  f"({', '.join(s.tag for s in lvl0.sections)}), "
                  f"{len(lvl0.geometries)} geometries, {len(lvl0.bakes)} bakes")
            terrain = lvl0.first("terrain")
            if terrain:
                print(f"terrain: {terrain.vertex_count} verts, {terrain.index_count} idx, "
                      f"dims {terrain.metadata['dimensions']}")
        for w in warnings:
            print(f"! {w}")
        return 0
    data = target.read_bytes()
    if data[:4] == b"TGCL":
        print(TGCL.parse(data, str(target)).summary())
        return 0
    if data[:4] == b"LVL0":
        lvl0 = LVL0.parse(data, str(target))
        print(json.dumps({"version": lvl0.version,
                          "sections": [s.__dict__ for s in lvl0.sections],
                          "geometries": [{"id": g.id, "kind": g.kind,
                                          "verts": g.vertex_count,
                                          "idx": g.index_count} for g in lvl0.geometries]},
                         indent=2, ensure_ascii=False))
        return 0
    print("unknown file magic", file=sys.stderr)
    return 1


if __name__ == "__main__":
    raise SystemExit(main(sys.argv))
