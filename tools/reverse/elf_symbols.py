#!/usr/bin/env python3
"""Symbol / import / section inventory for Android arm64 ELF shared objects.

`objdump` and `readelf` are not installed here, so this walks ELF64 structures
directly: program headers, section headers, `.dynsym` / `.symtab`, `.dynamic`
(NEEDED / SONAME / RPATH), and notes whether the file is stripped.

That is the symbol-level view needed to understand `libsky_vulkan.so` (renderer
entry points) and `libnode.so` (N-API surface) without a disassembler.

Usage:
    python3 tools/reverse/elf_symbols.py lib/arm64-v8a/libsky_vulkan.so
    python3 tools/reverse/elf_symbols.py libnode.so --filter Sky
"""

from __future__ import annotations

import argparse
import struct
from pathlib import Path

SHT_SYMTAB = 2
SHT_STRTAB = 3
SHT_DYNAMIC = 6
SHT_DYNSYM = 11
DT_NEEDED = 1
DT_SONAME = 14
DT_RPATH = 15
DT_RUNPATH = 29


class ELF:
    def __init__(self, data: bytes):
        self.data = data
        if data[:4] != b"\x7fELF":
            raise SystemExit("not an ELF file")
        self.bits = data[4]
        if self.bits != 2:
            raise SystemExit(f"only ELF64 supported (class {self.bits})")
        self.endian = "<" if data[5] == 1 else ">"
        e = self.endian
        (self.e_type, self.e_machine, self.e_version, self.e_entry, self.e_phoff,
         self.e_shoff, self.e_flags, self.e_ehsize, self.e_phentsize, self.e_phnum,
         self.e_shentsize, self.e_shnum, self.e_shstrndx) = struct.unpack_from(f"{e}HHIQQQIHHHHHH", data, 16)

        self.sections = []
        for i in range(self.e_shnum):
            off = self.e_shoff + i * self.e_shentsize
            name, typ, flags, addr, offset, size, link, info, align, entsize = \
                struct.unpack_from(f"{e}IIQQQQIIQQ", data, off)
            self.sections.append({"name_off": name, "type": typ, "flags": flags,
                                  "addr": addr, "offset": offset, "size": size,
                                  "link": link, "info": info, "entsize": entsize})
        shstr = self.sections[self.e_shstrndx]
        self.shstr = data[shstr["offset"]:shstr["offset"] + shstr["size"]]
        for s in self.sections:
            s["name"] = self._cstr(self.shstr, s["name_off"])

        self.dynamic = []
        self.symbols = {}  # name -> list of dicts

    def _cstr(self, blob: bytes, off: int) -> str:
        end = blob.find(b"\x00", off)
        return blob[off:end].decode("utf-8", "replace") if end >= 0 else ""

    def read_symbols(self) -> None:
        for s in self.sections:
            if s["type"] not in (SHT_SYMTAB, SHT_DYNSYM):
                continue
            strtab = self.sections[s["link"]]
            strings = self.data[strtab["offset"]:strtab["offset"] + strtab["size"]]
            entsize = s["entsize"] or 24
            for i in range(s["size"] // entsize):
                off = s["offset"] + i * entsize
                st_name, st_info, st_other, st_shndx, st_value, st_size = \
                    struct.unpack_from(f"{self.endian}IBBHQQ", self.data, off)
                name = self._cstr(strings, st_name)
                if not name:
                    continue
                bind = st_info >> 4
                typ = st_info & 0xF
                self.symbols.setdefault(name, []).append({
                    "bind": bind, "type": typ, "shndx": st_shndx,
                    "value": st_value, "size": st_size, "table": s["name"],
                })

    def read_dynamic(self) -> None:
        for s in self.sections:
            if s["type"] != SHT_DYNAMIC:
                continue
            strtab = self.sections[s["link"]]
            strings = self.data[strtab["offset"]:strtab["offset"] + strtab["size"]]
            entsize = s["entsize"] or 16
            for i in range(s["size"] // entsize):
                off = s["offset"] + i * entsize
                tag, val = struct.unpack_from(f"{self.endian}qQ", self.data, off)
                if tag in (DT_NEEDED, DT_SONAME, DT_RPATH, DT_RUNPATH):
                    kind = {DT_NEEDED: "NEEDED", DT_SONAME: "SONAME",
                            DT_RPATH: "RPATH", DT_RUNPATH: "RUNPATH"}[tag]
                    self.dynamic.append((kind, self._cstr(strings, val)))
                if tag == 0:
                    break

    def describe(self) -> str:
        machine = {0xB7: "aarch64", 0x28: "arm", 0x3E: "x86-64"}.get(self.e_machine, hex(self.e_machine))
        stripped = "yes" if not any(s["type"] == SHT_SYMTAB for s in self.sections) else "no"
        text = [f"ELF64 {machine}, type={self.e_type}, entry=0x{self.e_entry:x}, "
                f"sections={len(self.sections)}, stripped={stripped}"]
        if self.dynamic:
            text.append("dynamic: " + ", ".join(f"{k}={v}" for k, v in self.dynamic))
        return "\n".join(text)

    def print_symbols(self, needle: str | None, only_defined: bool, limit: int | None) -> None:
        items = []
        for name, entries in self.symbols.items():
            if needle and needle.lower() not in name.lower():
                continue
            for e in entries:
                defined = e["shndx"] != 0
                if only_defined and not defined:
                    continue
                typ = {1: "object", 2: "func", 3: "section", 4: "file"}.get(e["type"], str(e["type"]))
                bind = {0: "local", 1: "global", 2: "weak"}.get(e["bind"], str(e["bind"]))
                items.append((name, e, typ, bind, defined))
        items.sort(key=lambda t: t[0])
        if limit:
            items = items[:limit]
        for name, e, typ, bind, defined in items:
            mark = "T" if defined and e["type"] == 2 else ("U" if not defined else "D")
            print(f"{mark} {bind:<6} {typ:<8} 0x{e['value']:08x} {e['size']:>8} {name}")


def main(argv: list[str] | None = None) -> int:
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("elf", type=Path)
    parser.add_argument("--filter", help="only symbols whose name contains this text")
    parser.add_argument("--defined", action="store_true", help="only defined symbols")
    parser.add_argument("--limit", type=int, default=400)
    args = parser.parse_args(argv)

    elf = ELF(args.elf.read_bytes())
    elf.read_symbols()
    elf.read_dynamic()
    print(elf.describe())
    print(f"symbols: {sum(len(v) for v in elf.symbols.values())} entries, {len(elf.symbols)} names")
    elf.print_symbols(args.filter, args.defined, args.limit)
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
