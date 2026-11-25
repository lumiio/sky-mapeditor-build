"""Push a directory of files into a GitHub repository in one commit, over the API.

This device cannot use the git wire protocol against github.com (only
`api.github.com` answers), so `git push` is not an option. This script does the
same thing the hard way: blobs → tree → commit → update ref.

It is idempotent in the useful sense: a blob whose content already exists in the
repository is deduplicated by GitHub, and re-running with the same files on top
of an already-updated branch simply produces a new commit with no changes, so
check the output before trusting it.

Usage
-----
    python3 tools/github/push_tree.py --repo owner/name --message "..." \
        --root staging/ [--branch main] [--dry-run]

`--root` is a directory whose contents mirror the repository tree, for example

    staging/ios/Sources/GameAssets.swift
    staging/reverse/FINDINGS.md

The token is read from `GITHUB_TOKEN`, or from the environment variable named by
`--token-env` (default `DSH_SECRET_GITHUB_TOKEN`, which is how the saved secret
reaches the shell here). It needs **Contents: Read and write** on the repository;
the script probes that first and fails with a clear message instead of a bare 403.
"""

from __future__ import annotations

import json
import os
import sys
import urllib.error
import urllib.request
import base64
from pathlib import Path

API = "https://api.github.com"
TEXT_SUFFIXES = {".swift", ".py", ".md", ".json", ".patch", ".txt", ".yml", ".yaml", ".mjs", ".metal"}


class GitHubError(Exception):
    pass


class Client:
    def __init__(self, token: str):
        self.token = token

    def call(self, method: str, path: str, body: dict | None = None,
             raw: bool = False) -> bytes:
        url = path if path.startswith("http") else API + path
        data = None
        headers = {
            "Authorization": f"Bearer {self.token}",
            "Accept": "application/vnd.github.raw" if raw else "application/vnd.github+json",
            "User-Agent": "sky-mapeditor-reverse",
            "X-GitHub-Api-Version": "2022-11-28",
        }
        if body is not None:
            data = json.dumps(body).encode()
            headers["Content-Type"] = "application/json"
        request = urllib.request.Request(url, data=data, method=method, headers=headers)
        try:
            with urllib.request.urlopen(request) as response:
                return response.read()
        except urllib.error.HTTPError as error:
            payload = error.read().decode("utf-8", "replace")
            raise GitHubError(f"{method} {url} -> HTTP {error.code}: {payload[:400]}") from None

    def json(self, method: str, path: str, body: dict | None = None) -> dict:
        return json.loads(self.call(method, path, body))


def collect(root: Path) -> list[tuple[str, Path]]:
    entries: list[tuple[str, Path]] = []
    for path in sorted(root.rglob("*")):
        if not path.is_file():
            continue
        relative = path.relative_to(root).as_posix()
        if any(part.startswith(".") for part in relative.split("/")):
            continue
        if path.suffix not in TEXT_SUFFIXES:
            print(f"跳过（非文本/未列出的后缀）: {relative}", file=sys.stderr)
            continue
        entries.append((relative, path))
    return entries


def main(argv: list[str]) -> int:
    args = {"branch": "main", "dry_run": False, "token_env": "DSH_SECRET_GITHUB_TOKEN"}
    positional: list[str] = []
    index = 1
    while index < len(argv):
        arg = argv[index]
        if arg == "--repo":
            args["repo"] = argv[index + 1]; index += 2
        elif arg == "--message":
            args["message"] = argv[index + 1]; index += 2
        elif arg == "--root":
            args["root"] = argv[index + 1]; index += 2
        elif arg == "--branch":
            args["branch"] = argv[index + 1]; index += 2
        elif arg == "--token-env":
            args["token_env"] = argv[index + 1]; index += 2
        elif arg == "--dry-run":
            args["dry_run"] = True; index += 1
        elif arg.startswith("-"):
            print(f"未知参数 {arg}", file=sys.stderr); return 2
        else:
            positional.append(arg); index += 1

    for required in ("repo", "message", "root"):
        if required not in args:
            print(f"缺少 --{required}\n\n{__doc__}", file=sys.stderr)
            return 2

    repository = args["repo"]
    branch = args["branch"]
    root = Path(args["root"]).resolve()
    if not root.is_dir():
        print(f"{root} 不是目录", file=sys.stderr)
        return 2

    entries = collect(root)
    if not entries:
        print("没有可推送的文件", file=sys.stderr)
        return 2
    total = sum(path.stat().st_size for _, path in entries)
    print(f"待推送 {len(entries)} 个文件 / {total / 1024:.0f} KB → {repository}@{branch}")
    if args["dry_run"]:
        for remote, local in entries:
            print(f"  + {remote}  ({local.stat().st_size} B)")
        print("dry run：没有写入")
        return 0

    token = os.environ.get(args["token_env"]) or os.environ.get("GITHUB_TOKEN") or ""
    if not token:
        print(f"没有 token：请设置 ${args['token_env']}", file=sys.stderr)
        return 2
    client = Client(token)

    try:
        # 先探一下写权限，否则后面每个请求都只回一句 403
        client.json("POST", f"/repos/{repository}/git/blobs",
                    {"content": "probe", "encoding": "utf-8"})
    except GitHubError as error:
        print("这个 token 没有 Contents: Read and write 权限，推送中止。", file=sys.stderr)
        print(f"  {error}", file=sys.stderr)
        print("  修法：GitHub → Settings → Developer settings → Fine-grained tokens →"
              f" 选中该 token → Repository permissions → Contents = Read and write，"
              f"并确认 Repository access 里包含 {repository}。", file=sys.stderr)
        return 3

    try:
        ref = client.json("GET", f"/repos/{repository}/git/ref/heads/{branch}")
        head_sha = ref["object"]["sha"]
        head = client.json("GET", f"/repos/{repository}/git/commits/{head_sha}")
        base_tree = head["tree"]["sha"]
        print(f"当前 {branch} = {head_sha[:12]}")

        tree_entries = []
        for remote, local in entries:
            data = local.read_bytes()
            blob = client.json("POST", f"/repos/{repository}/git/blobs",
                               {"content": base64.b64encode(data).decode(), "encoding": "base64"})
            tree_entries.append({"path": remote, "mode": "100644", "type": "blob",
                                 "sha": blob["sha"]})
            print(f"  blob {remote} → {blob['sha'][:12]}")

        tree = client.json("POST", f"/repos/{repository}/git/trees",
                           {"base_tree": base_tree, "tree": tree_entries})
        commit = client.json("POST", f"/repos/{repository}/git/commits",
                             {"message": args["message"], "tree": tree["sha"],
                              "parents": [head_sha]})
        client.json("PATCH", f"/repos/{repository}/git/refs/heads/{branch}",
                    {"sha": commit["sha"], "force": False})
    except GitHubError as error:
        print(f"推送失败：{error}", file=sys.stderr)
        return 1

    print(f"完成：{repository}@{branch} = {commit['sha'][:12]}")
    print(f"  https://github.com/{repository}/commit/{commit['sha']}")
    return 0


if __name__ == "__main__":
    raise SystemExit(main(sys.argv))
