#!/usr/bin/env python3
"""Decode and verify the app's packed terrain stream (the `GEO0` 36-byte form).

On-disk layout produced by `native/export-scene.mjs`'s successor tooling:

    u32 vertexCount
    u32 indexCount
    vertexCount × 36-byte vertices
    indexCount × u32 indices

The 36-byte vertex matches the editor's `TerrainBlob` stream and is verified
against real CandleSpace data by this script:

    +0   pos        f32 × 3
    +12  normal     snorm8 × 4      (|n| ≈ 127 for every vertex)
    +16  material    u8 × 4         (blend palette: primary id first)
    +20  weights     u8 × 4         (255 = full weight for that slot)
    +24  light0      u8 × 4         (baked ambient; xyz ≈ 254/255, w = divisor)
    +28  light1      u8 × 4         (sky mix + sun visibility in .y)
    +32  light2      u8 × 4         (baked sun direction in xyz, intensity in .w)

The script prints the statistics that justify each claim, so a different build
(the original APK's Terrain.bin uses u16 indices and a longer header) can be
checked the same way.
"""

from __future__ import annotations

import argparse
import json
import struct
from collections import Counter
from pathlib import Path

STRIDE = 36


def decode(data: bytes) -> dict:
    if len(data) < 8:
        raise SystemExit("file too small")
    vcount, icount = struct.unpack_from("<II", data, 0)
    vertex_end = 8 + vcount * STRIDE
    if vertex_end > len(data):
        raise SystemExit(f"vertex stream ({vcount}×36) exceeds file")
    tail = len(data) - vertex_end
    if tail == icount * 4:
        index_fmt, index_bytes = "<I", 4
    elif tail == icount * 2:
        index_fmt, index_bytes = "<H", 2
    else:
        raise SystemExit(f"index stream size {tail} matches neither u16 nor u32 for {icount} indices")

    indices = list(struct.unpack_from(f"<{icount}{index_fmt[1]}", data, vertex_end))
    if indices and max(indices) >= vcount:
        raise SystemExit(f"index {max(indices)} outside {vcount} vertices")

    normals_ok = 0
    materials = Counter()
    weights_sum = Counter()
    light0 = []
    light1 = []
    light2 = []
    positions_min = [float("inf")] * 3
    positions_max = [float("-inf")] * 3
    step = max(1, vcount // 4096)  # sampling keeps large maps fast

    for i in range(0, vcount, step):
        o = 8 + i * STRIDE
        x, y, z = struct.unpack_from("<3f", data, o)
        for k, v in enumerate((x, y, z)):
            positions_min[k] = min(positions_min[k], v)
            positions_max[k] = max(positions_max[k], v)
        n = struct.unpack_from("<4b", data, o + 12)
        length = (n[0] ** 2 + n[1] ** 2 + n[2] ** 2) ** 0.5
        if 110 <= length <= 130:
            normals_ok += 1
        mats = struct.unpack_from("<4B", data, o + 16)
        weights = struct.unpack_from("<4B", data, o + 20)
        materials[mats[0]] += 1
        weights_sum[weights[0]] += 1
        light0.append(struct.unpack_from("<4B", data, o + 24))
        light1.append(struct.unpack_from("<4B", data, o + 28))
        light2.append(struct.unpack_from("<4B", data, o + 32))

    return {
        "vertex_count": vcount,
        "index_count": icount,
        "index_type": "u32" if index_bytes == 4 else "u16",
        "triangles": icount // 3,
        "bounds_min": [round(v, 2) for v in positions_min],
        "bounds_max": [round(v, 2) for v in positions_max],
        "normal_snorm4_fraction": round(normals_ok / max(1, len(light0)), 3),
        "material_id_histogram": dict(materials.most_common(8)),
        "weight_histogram": dict(weights_sum.most_common(4)),
        "light0_mean": [round(sum(c[k] for c in light0) / max(1, len(light0)), 1) for k in range(4)],
        "light1_mean": [round(sum(c[k] for c in light1) / max(1, len(light1)), 1) for k in range(4)],
        "light2_mean": [round(sum(c[k] for c in light2) / max(1, len(light2)), 1) for k in range(4)],
    }


def main(argv: list[str] | None = None) -> int:
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("terrain", type=Path)
    parser.add_argument("--json", type=Path)
    args = parser.parse_args(argv)

    report = decode(args.terrain.read_bytes())
    for key, value in report.items():
        print(f"{key:>26}: {value}")
    if args.json:
        args.json.write_text(json.dumps(report, indent=2, ensure_ascii=False))
        print(f"wrote {args.json}")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
