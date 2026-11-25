#!/usr/bin/env python3
"""Readable dump of minified JavaScript found inside an APK.

The editor's front-end ships as bundled/minified JS (three.js viewer, TGCL
parser, material table, RPC client). Without a JS beautifier installed, this
walks the source with a small state machine and breaks lines at statement and
block boundaries while leaving string literals and comments untouched.

It prints:
  * the formatted file (to `--out` or stdout)
  * the quoted string literals, longest first (asset names, protocol keys)
  * identifier frequency (functions/variables worth following)

Usage:
    python3 tools/reverse/js_scan.py assets/www/app.js --out /tmp/app.pretty.js
"""

from __future__ import annotations

import argparse
import re
from collections import Counter
from pathlib import Path


def pretty(source: str) -> str:
    out: list[str] = []
    indent = 0
    i = 0
    n = len(source)
    in_string: str | None = None
    in_comment: str | None = None
    line_start = True

    def emit(text: str) -> None:
        nonlocal line_start
        if line_start and text.strip():
            out.append("    " * indent)
            line_start = False
        out.append(text)

    def newline() -> None:
        nonlocal line_start
        out.append("\n")
        line_start = True

    while i < n:
        c = source[i]
        if in_comment:
            if in_comment == "//" and c == "\n":
                in_comment = None
                newline()
            elif in_comment == "/*" and c == "*" and i + 1 < n and source[i + 1] == "/":
                emit("*/")
                i += 1
                in_comment = None
                newline()
            else:
                emit(c)
            i += 1
            continue
        if in_string:
            emit(c)
            if c == "\\" and i + 1 < n:
                emit(source[i + 1])
                i += 2
                continue
            if c == in_string:
                in_string = None
            i += 1
            continue
        if c in "\"'`":
            in_string = c
            emit(c)
        elif c == "/" and i + 1 < n and source[i + 1] == "/":
            in_comment = "//"
            emit("//")
            i += 1
        elif c == "/" and i + 1 < n and source[i + 1] == "*":
            in_comment = "/*"
            emit("/*")
            i += 1
        elif c == "{":
            emit("{")
            newline()
            indent += 1
        elif c == "}":
            if indent:
                indent -= 1
            newline()
            emit("}")
            newline()
        elif c == ";":
            emit(";")
            newline()
        elif c == ",":
            emit(c)
            if len("".join(out)) - len("".join(out).rstrip()) >= 0:
                pass
        else:
            emit(c)
        i += 1
    return "".join(out)


def literals(source: str) -> list[str]:
    return sorted(set(re.findall(r'"([^"\\]{4,120})"', source)
                      + re.findall(r"'([^'\\]{4,120})'", source)), key=len, reverse=True)


def identifiers(source: str) -> Counter:
    return Counter(re.findall(r"[A-Za-z_$][A-Za-z0-9_$]{2,}", source))


def main(argv: list[str] | None = None) -> int:
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("js", type=Path)
    parser.add_argument("--out", type=Path)
    parser.add_argument("--top", type=int, default=40)
    args = parser.parse_args(argv)

    source = args.js.read_text(encoding="utf-8", errors="replace")
    formatted = pretty(source)
    if args.out:
        args.out.write_text(formatted)
        print(f"wrote {args.out} ({len(formatted)} chars, {formatted.count(chr(10))} lines)")
    else:
        print(formatted[:8000])

    print("\n--- string literals (longest first) ---")
    for s in literals(source)[:args.top]:
        print(" ", s)
    print("\n--- identifiers ---")
    for name, count in identifiers(source).most_common(args.top):
        print(f"  {count:>5} {name}")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
