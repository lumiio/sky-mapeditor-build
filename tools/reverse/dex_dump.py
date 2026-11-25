#!/usr/bin/env python3
"""Minimal Android `classes*.dex` reader — class / method / field inventory.

No Java toolchain is available in this container (no `java`, no `javap`, no
baksmali/jadx), so this walks the DEX structures directly:

    header → string_ids → type_ids → proto_ids → field_ids → method_ids → class_defs
           → class_data (uleb128 encoded field/method lists)

It prints the class hierarchy with every declared field and method signature,
which is enough to map the editor's architecture (MainActivity, JNI bridge, RPC
client, shader/material tables) without a decompiler. `--strings` dumps the
string pool, useful for finding embedded JSON keys, file names and log tags.

Usage:
    python3 tools/reverse/dex_dump.py classes.dex
    python3 tools/reverse/dex_dump.py classes.dex --strings --filter binary
"""

from __future__ import annotations

import argparse
import struct
import sys
from pathlib import Path


class DEX:
    def __init__(self, data: bytes):
        self.data = data
        if data[:4] != b"dex\n":
            raise SystemExit(f"not a DEX file (magic {data[:4]!r})")
        self.version = data[4:7].decode()
        (self.file_size, self.header_size, self.endian_tag,
         self.link_size, self.link_off, self.map_off,
         self.string_ids_size, self.string_ids_off,
         self.type_ids_size, self.type_ids_off,
         self.proto_ids_size, self.proto_ids_off,
         self.field_ids_size, self.field_ids_off,
         self.method_ids_size, self.method_ids_off,
         self.class_defs_size, self.class_defs_off,
         self.data_size, self.data_off) = struct.unpack_from("<20I", data, 32)

        self.strings = [self._string_at(self._u32(self.string_ids_off + i * 4))
                        for i in range(self.string_ids_size)]
        self.types = [self.strings[self._u32(self.type_ids_off + i * 4)]
                      for i in range(self.type_ids_size)]
        self.protos = []
        for i in range(self.proto_ids_size):
            shorty, ret, params_off = struct.unpack_from("<3I", data, self.proto_ids_off + i * 12)
            params = self._type_list(params_off) if params_off else []
            self.protos.append((self.strings[shorty], self.types[ret], params))
        self.fields = []
        for i in range(self.field_ids_size):
            cls, typ, name = struct.unpack_from("<HHI", data, self.field_ids_off + i * 8)
            self.fields.append((self.types[cls], self.types[typ], self.strings[name]))
        self.methods = []
        for i in range(self.method_ids_size):
            cls, proto, name = struct.unpack_from("<HHI", data, self.method_ids_off + i * 8)
            self.methods.append((self.types[cls], proto, self.strings[name]))
        self.classes = []
        for i in range(self.class_defs_size):
            values = struct.unpack_from("<8I", data, self.class_defs_off + i * 32)
            self.classes.append(values)

    # -- primitives -------------------------------------------------------
    def _u32(self, off: int) -> int:
        return struct.unpack_from("<I", self.data, off)[0]

    def _uleb(self, off: int) -> tuple[int, int]:
        result = 0
        shift = 0
        while True:
            byte = self.data[off]
            off += 1
            result |= (byte & 0x7F) << shift
            if not byte & 0x80:
                return result, off
            shift += 7

    def _string_at(self, off: int) -> str:
        _, off = self._uleb(off)  # utf16 length
        end = self.data.find(b"\x00", off)
        raw = self.data[off:end]
        return raw.decode("utf-8", "replace").replace("\u0001", "\u0001")

    def _type_list(self, off: int) -> list[str]:
        size = self._u32(off)
        return [self.types[self._u16(off + 4 + i * 2)] for i in range(size)]

    def _u16(self, off: int) -> int:
        return struct.unpack_from("<H", self.data, off)[0]

    # -- class data -------------------------------------------------------
    def dump(self, filter_text: str | None = None) -> None:
        for class_def in self.classes:
            class_idx, access, super_idx, interfaces_off, source_idx, \
                annotations_off, class_data_off, static_values_off = class_def
            if class_idx >= len(self.types):
                continue
            name = self.types[class_idx]
            if filter_text and filter_text.lower() not in name.lower():
                continue
            superclass = self.types[super_idx] if super_idx < len(self.types) else "-"
            interfaces = self._type_list(interfaces_off) if interfaces_off else []
            print(f"\nclass {name}  access=0x{access:04x}  extends {superclass}"
                  + (f"  implements {', '.join(interfaces)}" if interfaces else ""))
            if not class_data_off:
                print("  (no class data)")
                continue
            off = class_data_off
            static_fields, off = self._uleb(off)
            instance_fields, off = self._uleb(off)
            direct_methods, off = self._uleb(off)
            virtual_methods, off = self._uleb(off)

            def read_fields(count: int, off: int) -> tuple[list[int], int]:
                idx = 0
                out = []
                for _ in range(count):
                    diff, off = self._uleb(off)
                    _access, off = self._uleb(off)
                    idx += diff
                    out.append(idx)
                return out, off

            def read_methods(count: int, off: int) -> tuple[list[int], int]:
                idx = 0
                out = []
                for _ in range(count):
                    diff, off = self._uleb(off)
                    _access, off = self._uleb(off)
                    _code, off = self._uleb(off)
                    idx += diff
                    out.append(idx)
                return out, off

            s_fields, off = read_fields(static_fields, off)
            i_fields, off = read_fields(instance_fields, off)
            d_methods, off = read_methods(direct_methods, off)
            v_methods, off = read_methods(virtual_methods, off)

            for kind, ids in (("static", s_fields), ("instance", i_fields)):
                for fid in ids:
                    if fid < len(self.fields):
                        _cls, typ, fname = self.fields[fid]
                        print(f"  field[{kind}] {fname}: {typ}")
            for kind, ids in (("direct", d_methods), ("virtual", v_methods)):
                for mid in ids:
                    if mid < len(self.methods):
                        _cls, proto_idx, mname = self.methods[mid]
                        shorty, ret, params = self.protos[proto_idx]
                        sig = ", ".join(params)
                        print(f"  method[{kind}] {mname}({sig}) -> {ret}")

    def dump_strings(self, needle: str | None = None) -> None:
        for s in self.strings:
            if needle and needle.lower() not in s.lower():
                continue
            print(s)


def main(argv: list[str] | None = None) -> int:
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("dex", type=Path)
    parser.add_argument("--filter", help="only classes whose name contains this text")
    parser.add_argument("--strings", action="store_true", help="dump the string pool")
    args = parser.parse_args(argv)

    dex = DEX(args.dex.read_bytes())
    print(f"{args.dex.name}: DEX {dex.version}, {dex.classes.__len__()} classes, "
          f"{dex.methods.__len__()} methods, {dex.fields.__len__()} fields, "
          f"{len(dex.strings)} strings, {dex.file_size} bytes")
    if args.strings:
        dex.dump_strings(args.filter)
    else:
        dex.dump(args.filter)
    return 0


if __name__ == "__main__":
    raise SystemExit(main(sys.argv[1:]))
