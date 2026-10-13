#!/usr/bin/env python3
"""Check the vendored copy of Leaf's RetroArch patch set.

The pak builds from a clean clone, so Leaf's MLP1 RetroArch patches are copied
into patches/retroarch/leaf/ instead of being read from a sibling checkout.
patches/retroarch/leaf/SOURCE.json records where they came from. Two checks:

    check-patches.py list
        Offline. Verifies the vendored files against SOURCE.json (present, in
        order, sha256, nothing extra, agrees with upstream.lock.json) and prints
        their paths in the order they must be applied. scripts/fetch-sources.sh
        uses this, so a hand-edited patch never reaches a build.

    check-patches.py verify [--upstream DIR]
        Everything `list` checks, plus: fetches retroarch-builds at the recorded
        commit and fails if any vendored patch differs from the original, or if
        that commit's build-mlp1.sh maps a patch-set name to a different file.
        DIR may be any clone that contains the commit; without it the commit is
        fetched into a temporary directory.
"""
from __future__ import annotations

import argparse
import hashlib
import json
import re
import subprocess
import sys
import tempfile
from pathlib import Path

REPO_ROOT = Path(__file__).resolve().parent.parent
LEAF_DIR = REPO_ROOT / "patches" / "retroarch" / "leaf"
SOURCE = LEAF_DIR / "SOURCE.json"
LOCK = REPO_ROOT / "upstream.lock.json"
COMMIT_RE = re.compile(r"^[0-9a-f]{40}$")


def sha256(data: bytes) -> str:
    return hashlib.sha256(data).hexdigest()


def load_source() -> dict:
    try:
        source = json.loads(SOURCE.read_text())
    except (OSError, json.JSONDecodeError) as exc:
        raise SystemExit(f"FAIL cannot read {SOURCE}: {exc}")
    return source


def check_local(source: dict) -> list[str]:
    problems: list[str] = []
    if source.get("schema") != 1:
        problems.append("SOURCE.json: schema must be 1")
    for key in ("repo", "commit", "patch_set", "patches"):
        if key not in source:
            problems.append(f"SOURCE.json: missing {key}")
    if problems:
        return problems
    if not COMMIT_RE.match(source["commit"]):
        problems.append("SOURCE.json: commit must be a full 40-character SHA")

    patches = source["patches"]
    dropped = source.get("dropped", [])
    for entry in dropped:
        if not entry.get("name") or not entry.get("reason"):
            problems.append(f"SOURCE.json: dropped entry needs a name and a reason: {entry}")

    names = [p.get("name") for p in patches]
    wanted = [n for n in source["patch_set"].split(",") if n]
    shipped = names + [d.get("name") for d in dropped]
    if sorted(shipped) != sorted(wanted) or len(set(shipped)) != len(shipped):
        problems.append(
            f"SOURCE.json: patches + dropped {shipped} do not cover patch_set {wanted}"
        )
    if [n for n in wanted if n in names] != names:
        problems.append("SOURCE.json: patches are not in patch_set order")
    if [p.get("order") for p in patches] != list(range(1, len(patches) + 1)):
        problems.append("SOURCE.json: order must count 1..n with no gaps")

    for patch in patches:
        label = patch.get("file", "?")
        path = LEAF_DIR / label
        if not path.is_file():
            problems.append(f"missing vendored patch {label}")
            continue
        got = sha256(path.read_bytes())
        if got != patch.get("sha256"):
            problems.append(f"{label}: sha256 {got} != recorded {patch.get('sha256')}")
        if not str(patch.get("source_path", "")).startswith("patches/"):
            problems.append(f"{label}: source_path must be under patches/")

    listed = {p.get("file") for p in patches}
    for path in sorted(LEAF_DIR.glob("*.patch")):
        if path.name not in listed:
            problems.append(f"{path.name} is not listed in SOURCE.json")

    lock = json.loads(LOCK.read_text())
    pinned = lock.get("retroarch", {}).get("leaf_patches", {})
    for key in ("repo", "commit"):
        if pinned.get(key) != source.get(key):
            problems.append(
                f"upstream.lock.json retroarch.leaf_patches.{key} "
                f"{pinned.get(key)!r} != SOURCE.json {source.get(key)!r}"
            )
    if lock.get("retroarch", {}).get("commit") != source.get("applies_to", {}).get("commit"):
        problems.append("SOURCE.json applies_to.commit is not the RetroArch commit in upstream.lock.json")
    return problems


def git(directory: Path, *args: str) -> str:
    return subprocess.run(
        ["git", "-C", str(directory), *args],
        check=True, capture_output=True, text=True,
    ).stdout


def git_bytes(directory: Path, *args: str) -> bytes:
    return subprocess.run(
        ["git", "-C", str(directory), *args], check=True, capture_output=True
    ).stdout


def check_upstream(source: dict, directory: Path) -> list[str]:
    problems: list[str] = []
    commit = source["commit"]
    try:
        git(directory, "cat-file", "-e", f"{commit}^{{commit}}")
    except subprocess.CalledProcessError:
        return [f"{directory} does not contain retroarch-builds commit {commit}"]

    for patch in source["patches"]:
        try:
            original = git_bytes(directory, "show", f"{commit}:{patch['source_path']}")
        except subprocess.CalledProcessError:
            problems.append(f"{patch['source_path']} does not exist at {commit[:7]}")
            continue
        vendored = (LEAF_DIR / patch["file"]).read_bytes()
        if original != vendored:
            problems.append(
                f"{patch['file']} differs from retroarch-builds {commit[:7]}:"
                f"{patch['source_path']} (sha256 {sha256(original)})"
            )

    # build-mlp1.sh is where a patch-set name becomes a file, so the mapping is
    # checked at the same commit instead of trusted from SOURCE.json.
    script = git_bytes(directory, "show", f"{commit}:build-mlp1.sh").decode()
    mapping = dict(
        re.findall(
            r'^\s+([a-z0-9-]+)\)\s*\n\s+patch_path="\$REPO_ROOT/(patches/[^"]+)"',
            script,
            re.MULTILINE,
        )
    )
    if not mapping:
        problems.append(f"could not read the patch-name mapping from build-mlp1.sh at {commit[:7]}")
    for patch in source["patches"]:
        if mapping.get(patch["name"]) != patch["source_path"]:
            problems.append(
                f"build-mlp1.sh at {commit[:7]} maps {patch['name']} to "
                f"{mapping.get(patch['name'])!r}, SOURCE.json says {patch['source_path']!r}"
            )
    return problems


def main() -> int:
    parser = argparse.ArgumentParser(description=__doc__.split("\n\n")[0])
    sub = parser.add_subparsers(dest="command", required=True)
    sub.add_parser("list")
    verify = sub.add_parser("verify")
    verify.add_argument("--upstream", type=Path)
    args = parser.parse_args()

    source = load_source()
    problems = check_local(source)
    if problems:
        for problem in problems:
            print(f"FAIL {problem}", file=sys.stderr)
        return 1

    if args.command == "list":
        for patch in source["patches"]:
            print(LEAF_DIR / patch["file"])
        return 0

    with tempfile.TemporaryDirectory() as tmp:
        directory = args.upstream
        if directory is None:
            directory = Path(tmp)
            git(directory, "init", "-q")
            print(f"fetching retroarch-builds {source['commit'][:7]} from {source['repo']}")
            subprocess.run(
                ["git", "-C", str(directory), "fetch", "-q", "--depth", "1",
                 source["repo"], source["commit"]],
                check=True,
            )
        problems = check_upstream(source, directory.resolve())
    if problems:
        for problem in problems:
            print(f"FAIL {problem}", file=sys.stderr)
        return 1
    print(
        f"PASS check-patches: {len(source['patches'])} vendored patches match "
        f"retroarch-builds {source['commit'][:7]}"
    )
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
