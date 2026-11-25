#!/usr/bin/env python3
"""Decode Android binary XML (`AndroidManifest.xml` inside an APK).

AXML is a chunked format: an XML chunk wrapping a string pool, a resource map
and start/end element chunks. There is no `aapt`/`apktool` in this container,
so this reads the chunks directly and prints pseudo-XML with resolved strings
and typed attribute values.

Usage:
    python3 tools/reverse/android_binary_xml.py AndroidManifest.xml
"""

from __future__ import annotations

import argparse
import struct
from pathlib import Path

RES_STRING_POOL = 0x0001
RES_XML = 0x0003
RES_XML_START = 0x0102
RES_XML_END = 0x0103
RES_XML_RESOURCE_MAP = 0x0180

TYPE_REFERENCE = 0x01
TYPE_STRING = 0x03
TYPE_FLOAT = 0x04
TYPE_INT_DEC = 0x10
TYPE_INT_HEX = 0x11
TYPE_INT_BOOLEAN = 0x12


class AXML:
    def __init__(self, data: bytes):
        self.data = data
        self.strings: list[str] = []
        self.attrs: list[tuple[str, str]] = []
        self._parse()

    def _u16(self, off: int) -> int:
        return struct.unpack_from("<H", self.data, off)[0]

    def _u32(self, off: int) -> int:
        return struct.unpack_from("<I", self.data, off)[0]

    def _read_strings(self, off: int) -> int:
        """Reads a string pool chunk, returns its end offset."""
        chunk_type = self._u16(off)
        assert chunk_type == RES_STRING_POOL, chunk_type
        header_size = self._u16(off + 2)
        size = self._u32(off + 4)
        count = self._u32(off + 8)
        flags = self._u32(off + 16)
        strings_start = self._u32(off + 20)
        utf8 = bool(flags & (1 << 8))
        offsets = [self._u32(off + header_size + i * 4) for i in range(count)]
        base = off + strings_start
        for rel in offsets:
            pos = base + rel
            if utf8:
                # utf16 length, then byte length, both u8 (or u16 if >= 0x80)
                u16len = self.data[pos]; pos += 1
                if u16len & 0x80:
                    u16len = ((u16len & 0x7F) << 8) | self.data[pos]; pos += 1
                u8len = self.data[pos]; pos += 1
                if u8len & 0x80:
                    u8len = ((u8len & 0x7F) << 8) | self.data[pos]; pos += 1
                raw = self.data[pos:pos + u8len]
                self.strings.append(raw.decode("utf-8", "replace"))
            else:
                length = self._u16(pos); pos += 2
                if length & 0x8000:
                    length = ((length & 0x7FFF) << 16) | self._u16(pos); pos += 2
                raw = self.data[pos:pos + length * 2]
                self.strings.append(raw.decode("utf-16-le", "replace"))
        return off + size

    def _string(self, index: int) -> str:
        return self.strings[index] if 0 <= index < len(self.strings) else f"@{index}"

    def _parse(self) -> None:
        off = 0
        depth = 0
        lines: list[str] = []
        while off + 8 <= len(self.data):
            chunk_type = self._u16(off)
            header_size = self._u16(off + 2)
            size = self._u32(off + 4)
            if size == 0:
                break
            if chunk_type == RES_STRING_POOL:
                off = self._read_strings(off)
                continue
            if chunk_type == RES_XML:
                off += header_size
                continue
            if chunk_type == RES_XML_RESOURCE_MAP:
                off += size
                continue
            if chunk_type == RES_XML_START:
                line = self._u32(off + 8)
                name = self._string(self._u32(off + 20))
                attr_start = self._u16(off + 24)
                attr_size = self._u16(off + 26)
                attr_count = self._u16(off + 28)
                parts = []
                for i in range(attr_count):
                    a = off + 16 + attr_start + i * attr_size
                    attr_name = self._string(self._u32(a + 4))
                    raw = self._u32(a + 8)
                    value_type = self.data[a + 15]
                    value = self._u32(a + 16)
                    if raw != 0xFFFFFFFF and raw < len(self.strings):
                        text = self._string(raw)
                    elif value_type == TYPE_STRING:
                        text = '"' + self._string(value) + '"'
                    elif value_type == TYPE_REFERENCE:
                        text = f"@0x{value:08x}"
                    elif value_type == TYPE_INT_BOOLEAN:
                        text = "true" if value else "false"
                    elif value_type == TYPE_INT_HEX:
                        text = f"0x{value:x}"
                    elif value_type == TYPE_FLOAT:
                        text = str(struct.unpack("<f", struct.pack("<I", value))[0])
                    else:
                        text = str(value)
                    parts.append(f'{attr_name}="{text}"')
                indent = "  " * depth
                lines.append(f"{indent}<{name}{' ' if parts else ''}{' '.join(parts)}>")
                depth += 1
            elif chunk_type == RES_XML_END:
                depth = max(0, depth - 1)
                name = self._string(self._u32(off + 20))
                lines.append(f"{'  ' * depth}</{name}>")
            off += size
        self.text = "\n".join(lines)


def main(argv: list[str] | None = None) -> int:
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("manifest", type=Path)
    args = parser.parse_args(argv)
    axml = AXML(args.manifest.read_bytes())
    print(axml.text)
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
