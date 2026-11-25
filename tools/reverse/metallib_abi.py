#!/usr/bin/env python3
"""Reverse the original iOS `metallib` shader binaries shipped with the game.

Apple's `metallib` is a `MTLB` container: a table of length-prefixed tags
(`NAME`, `TYPE`, `HASH`, `VERS`, `UUID`, `VATT`, `VATY`, ...) followed by an
LLVM bitcode blob (magic `BC C0 DE`). The bitcode's module metadata and
`air.*` function attributes name every argument, uniform and structure member,
which is exactly the information needed to bind the shaders from a Metal app.

This tool extracts, per shader:

  * function name (vsmain / fsmain), hash, Metal version, module UUID
  * vertex attributes with their locations (`VATT`), and the raw type codes
    (`VATY`, mapping not documented by Apple — kept verbatim)
  * the LLVM bitcode blob offset/size
  * every `air.arg_name` / type pair, every `user(locnN)` varying, every
    uniform member (`u_*`), texture / sampler names and uniform structure names

Output is deterministic JSON so a CI job can diff shader ABI between builds.

Usage:
    python3 tools/reverse/metallib_abi.py --metallib DIR --out reverse/shader-abi.json
"""

from __future__ import annotations

import argparse
import hashlib
import json
import re
import struct
from pathlib import Path

TAG_RE = re.compile(rb"[A-Z]{4}")


class MTLB:
    def __init__(self, data: bytes, name: str):
        self.data = data
        self.name = name
        self.tags = self._walk_tags()

    def _walk_tags(self) -> list[tuple[int, str, bytes]]:
        """Walks the tag table at the head of the file.

        Entries are 4-byte ASCII tags, a little-endian u16 payload length and
        the payload; the table is 4-byte aligned. The walk stops at the first
        non-tag bytes (the bitcode blob).
        """
        out = []
        pos = 0
        end = self.data.find(b"BC\xc0\xde")
        if end < 0:
            end = len(self.data)
        while pos + 6 <= end:
            tag = self.data[pos:pos + 4]
            if not TAG_RE.fullmatch(tag):
                pos += 1
                continue
            length = struct.unpack_from("<H", self.data, pos + 4)[0]
            if length > 4096 or pos + 6 + length > end:
                pos += 1
                continue
            out.append((pos, tag.decode("ascii"), self.data[pos + 6:pos + 6 + length]))
            pos += 6 + length
            if pos % 4:
                pos += 4 - (pos % 4)
        return out

    def tag(self, name: str) -> bytes | None:
        needle = name.encode("ascii")
        start = 0
        while True:
            pos = self.data.find(needle, start)
            if pos < 0:
                return None
            start = pos + 1
            if pos + 6 > len(self.data):
                continue
            length = struct.unpack_from("<H", self.data, pos + 4)[0]
            if length > 4096 or pos + 6 + length > len(self.data):
                continue
            return self.data[pos + 6:pos + 6 + length]

    @property
    def function(self) -> str | None:
        payload = self.tag("NAME")
        return payload.rstrip(b"\x00").decode() if payload else None

    @property
    def hash(self) -> str | None:
        payload = self.tag("HASH")
        return payload.hex() if payload else None

    @property
    def version(self) -> str | None:
        payload = self.tag("VERS")
        if not payload:
            return None
        return ".".join(str(v) for v in struct.unpack("<" + "H" * (len(payload) // 2), payload))

    @property
    def uuid(self) -> str | None:
        payload = self.tag("UUID")
        return payload.hex() if payload else None

    @property
    def bitcode_offset(self) -> int | None:
        idx = self.data.find(b"BC\xc0\xde")
        return idx if idx >= 0 else None

    @property
    def attributes(self) -> list[dict]:
        payload = self.tag("VATT")
        if not payload:
            return []
        count = struct.unpack_from("<H", payload, 0)[0]
        pos = 2
        attrs = []
        for _ in range(count):
            end = payload.find(b"\x00", pos)
            if end < 0:
                break
            name = payload[pos:end].decode("ascii", "replace")
            location = payload[end + 1] if end + 1 < len(payload) else 0
            attrs.append({"name": name, "location": location})
            pos = end + 2
            if pos < len(payload) and payload[pos] == 0x80:
                pos += 1
        return attrs

    @property
    def attribute_types(self) -> list[int]:
        payload = self.tag("VATY")
        if not payload:
            return []
        count = struct.unpack_from("<H", payload, 0)[0]
        return list(payload[2:2 + count])

    @property
    def metadata(self) -> dict:
        """Extracts the argument/AA information from the AIR metadata run."""
        blob = self.data[self.bitcode_offset:] if self.bitcode_offset else self.data
        runs = [m.group(0).decode("latin-1") for m in re.finditer(rb"[ -~]{200,}", blob)]
        text = max(runs, key=len) if runs else ""

        varyings = re.findall(r"user\(locn(\d+)\)", text)
        arg_names = re.findall(r"air\.arg_name([A-Za-z_][A-Za-z0-9_]*)", text)
        structs = re.findall(r"([A-Z][A-Za-z0-9_]*_\d+)", text)
        uniforms = _uniform_members(text)
        textures = re.findall(r"air\.texture", text)
        samplers = re.findall(r"air\.sampler", text)

        return {
            "metadata_chars": len(text),
            "varying_locations": [int(v) for v in varyings],
            "arg_names": arg_names,
            "uniform_structs": _dedupe(structs),
            "uniform_members": _dedupe(uniforms),
            "texture_slots": len(textures),
            "sampler_slots": len(samplers),
            "missing_type_names": re.findall(r"_m(\d+)_pad", text),
        }

    def to_json(self) -> dict:
        meta = self.metadata
        return {
            "file": self.name,
            "function": self.function,
            "hash": self.hash,
            "metal_version": self.version,
            "uuid": self.uuid,
            "bitcode_offset": self.bitcode_offset,
            "bitcode_bytes": (len(self.data) - self.bitcode_offset) if self.bitcode_offset else 0,
            "attributes": self.attributes,
            "attribute_type_codes": self.attribute_types,
            "varyings": meta["varying_locations"],
            "uniform_structs": meta["uniform_structs"],
            "uniform_members": meta["uniform_members"],
            "texture_slots": meta["texture_slots"],
            "sampler_slots": meta["sampler_slots"],
            "arg_names": meta["arg_names"],
        }


_TYPES = (r"texture[0-9a-z]*<[^>]*>|vec<[^>]*>|float4x4|packed_float3|packed_float2|"
          r"char_m\d+_pad|uint4|uint|float[234]?|sampler")
_STRUCT = r"(?:PerObject|PerPass|PerFrame)Uniforms_\d+"


def _uniform_members(text: str) -> list[str]:
    """Splits the concatenated AIR metadata into uniform member names.

    The metadata run has no delimiters, so boundaries are inserted before
    known type tokens, structure names and `air.*` keys, then each piece is
    split again on the `u_` prefix that starts every member name.
    """
    for pattern in (_TYPES, _STRUCT, r"air\.", r"user\(locn\d+\)", r"gl_[A-Za-z]+"):
        text = re.sub(rf"(?={pattern})", "|", text)
    members = []
    for piece in text.split("|"):
        for chunk in piece.split("u_"):
            chunk = chunk.strip()
            if not chunk or not chunk[0].isalpha():
                continue
            name = re.split(r"[^A-Za-z0-9_]", chunk)[0]
            # Real members are lowerCamelCase after `u_`; everything else is
            # type/struct/air noise glued on by the delimiter-free metadata.
            if not re.fullmatch(r"[a-z][A-Za-z0-9_]{1,63}", name):
                continue
            if name.startswith(("float", "packed_", "char_m", "uint", "texture", "sampler",
                                "air", "user", "gl_", "SDK", "PerObject", "PerPass",
                                "PerFrame", "samplersApple", "vec")):
                continue
            members.append("u_" + name)
    return _dedupe(members)


def _dedupe(items: list[str]) -> list[str]:
    seen = set()
    out = []
    for item in items:
        if item not in seen:
            seen.add(item)
            out.append(item)
    return out


def main(argv: list[str] | None = None) -> int:
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--metallib", required=True, type=Path,
                        help="directory containing *.ios.vs.metallib / *.ios.fs.metallib")
    parser.add_argument("--out", required=True, type=Path)
    args = parser.parse_args(argv)

    files = sorted(args.metallib.glob("*.metallib"))
    if not files:
        print(f"no .metallib under {args.metallib}")
        return 1

    catalog = []
    for path in files:
        data = path.read_bytes()
        if not data.startswith(b"MTLB"):
            print(f"skip {path.name}: not an MTLB container")
            continue
        info = MTLB(data, path.name).to_json()
        info["sha256"] = hashlib.sha256(data).hexdigest()
        catalog.append(info)
        print(f"{path.name:<48} {info['function']:<8} attrs={len(info['attributes'])} "
              f"uniforms={len(info['uniform_members'])} bitcode@{info['bitcode_offset']}")

    args.out.parent.mkdir(parents=True, exist_ok=True)
    args.out.write_text(json.dumps(catalog, indent=2, ensure_ascii=False))
    print(f"wrote {len(catalog)} shader(s) → {args.out}")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
