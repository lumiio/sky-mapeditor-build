"""Census of a Sky `Data` folder: every map's TGCL/LVL0 records, in one table.

This is the script that produced the baseline table in
`SkyMapEditor/Core/FormatSelfTest.swift`. Run it against any `Data` folder to
see what the Swift parsers are expected to report:

    python3 tools/reverse/survey.py /path/to/Data
    python3 tools/reverse/survey.py /path/to/Data --swift     # emit the baseline
    python3 tools/reverse/survey.py /path/to/Data --json out.json

A map that fails to parse is listed under FAIL and makes the exit code 1, so
this doubles as a regression gate for `skyformats.py`.
"""

from __future__ import annotations

import json
import sys
from pathlib import Path

sys.path.insert(0, str(Path(__file__).resolve().parent))

from skyformats import LVL0, TGCL, FormatError  # noqa: E402


def survey_map(directory: Path) -> dict:
    level = directory / "Objects.level.bin"
    meshes = directory / "BstBaked.meshes"
    row: dict = {"name": directory.name}
    if level.exists():
        tgcl = TGCL.parse(level.read_bytes(), str(level))
        row["nodes"] = len(tgcl.nodes)
        row["classes"] = len(tgcl.classes)
        row["fields"] = len(tgcl.fields)
    else:
        row["nodes"] = row["classes"] = row["fields"] = 0
    if not meshes.exists():
        raise FormatError(f"{meshes}: missing")
    lvl0 = LVL0.parse(meshes.read_bytes(), str(meshes))
    row["version"] = lvl0.version
    row["sections"] = [s.tag for s in lvl0.sections]
    row["bakes"] = len(lvl0.bakes)
    row["lod_bytes"] = len(lvl0.lod)

    counts = {kind: [0, 0, 0] for kind in ("terrain", "skirt", "occluder", "cloud")}
    for geometry in lvl0.geometries:
        entry = counts.setdefault(geometry.kind, [0, 0, 0])
        entry[0] += 1
        entry[1] += geometry.vertex_count
        entry[2] += geometry.index_count
    for kind in ("terrain", "skirt", "occluder", "cloud"):
        records, vertices, indices = counts.get(kind, [0, 0, 0])
        row[f"{kind}_records"] = records
        row[f"{kind}_vertices"] = vertices
        row[f"{kind}_indices"] = indices
    row["edge_tables"] = sum(
        1 for g in lvl0.geometries
        if g.kind == "terrain" and g.metadata.get("edgeCount", 0))
    return row


def swift_baseline(rows: list[dict]) -> str:
    lines = []
    for r in rows:
        lines.append(
            f'        "{r["name"]}": Expectation(version: {r["version"]}, '
            f'nodes: {r["nodes"]}, classes: {r["classes"]}, '
            f'terrains: {r["terrain_records"]}, vertices: {r["terrain_vertices"]}, '
            f'indices: {r["terrain_indices"]}, skirts: {r["skirt_records"]}, '
            f'skirtVertices: {r["skirt_vertices"]}, '
            f'occluders: {r["occluder_records"]}, bakes: {r["bakes"]}),')
    return "\n".join(lines)


def main(argv: list[str]) -> int:
    if len(argv) < 2:
        print(__doc__, file=sys.stderr)
        return 2
    root = Path(argv[1])
    levels = root / "Levels"
    if not levels.is_dir():
        print(f"{levels} 不是 Data/Levels 目录", file=sys.stderr)
        return 2
    rows: list[dict] = []
    failures: list[tuple[str, str]] = []
    for directory in sorted(p for p in levels.iterdir() if p.is_dir()):
        try:
            rows.append(survey_map(directory))
        except (FormatError, OSError) as error:
            failures.append((directory.name, str(error)))

    header = (f'{"map":24}{"ver":>4}{"bake":>6}{"terr":>5}{"verts":>9}{"idx":>10}'
              f'{"skirt":>6}{"sv":>8}{"occ":>4}{"ov":>7}{"cloud":>6}{"LOD0":>10}')
    print(header)
    for r in rows:
        print(f'{r["name"][:24]:24}{r["version"]:>4}{r["bakes"]:>6}'
              f'{r["terrain_records"]:>5}{r["terrain_vertices"]:>9}{r["terrain_indices"]:>10}'
              f'{r["skirt_records"]:>6}{r["skirt_vertices"]:>8}'
              f'{r["occluder_records"]:>4}{r["occluder_vertices"]:>7}'
              f'{r["cloud_records"]:>6}{r["lod_bytes"]:>10}')

    total = lambda key: sum(r[key] for r in rows)  # noqa: E731
    print()
    print(f"maps {len(rows)} · failed {len(failures)}"
          f" · terrain {total('terrain_vertices')} v / {total('terrain_indices')} i"
          f" · skirt {total('skirt_vertices')} v / {total('skirt_indices')} i"
          f" · bakes {total('bakes')}")
    print(f"maps with terrain {sum(1 for r in rows if r['terrain_records'])}"
          f" · with skirt {sum(1 for r in rows if r['skirt_records'])}"
          f" · with cloud {sum(1 for r in rows if r['cloud_records'])}"
          f" · non-empty edge tables {sum(r['edge_tables'] for r in rows)}")
    for name, error in failures:
        print(f"FAIL {name}: {error}")

    if "--json" in argv:
        out = Path(argv[argv.index("--json") + 1])
        out.write_text(json.dumps(rows, ensure_ascii=False, indent=1))
        print(f"wrote {out}")
    if "--swift" in argv:
        print()
        print(swift_baseline(rows))
    return 1 if failures else 0


if __name__ == "__main__":
    raise SystemExit(main(sys.argv))
