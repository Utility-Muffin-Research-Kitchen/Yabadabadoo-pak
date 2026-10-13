#!/usr/bin/env python3
"""Write the pak ZIP or the corresponding-source tarball byte for byte the same
on every machine.

    make-archive.py zip  --epoch N --out FILE.zip    --root DIR NAME
    make-archive.py tar  --epoch N --out FILE.tar.gz --member DEST=SRC [...]

Both formats carry whatever the filesystem happened to say: mtimes from the
last copy, the builder's owner, umask-dependent modes and readdir order. None
of that is part of the pak, so it is normalised here:

- entries in sorted path order, directories before their contents;
- every mtime is the lock's SOURCE_DATE_EPOCH;
- owner and group are 0 with no names;
- modes are 0755 for directories and executables, 0644 for everything else;
- no ZIP extra fields; the gzip header has no file name and a zero mtime
  (what `gzip -n` writes).

The compressed bytes also depend on the zlib doing the compressing, so the
Makefile runs this inside the digest-pinned toolchain image, whose Python and
zlib are fixed. Run on another zlib it still produces a valid, normalised
archive; it just may not hash the same.

A `SRC` that is a git work tree contributes only what git would ship: tracked
files plus untracked files git does not ignore (a patch adds new sources), and
never `.git` itself. Anything else is walked, skipping `.git` and
`__pycache__`.
"""
from __future__ import annotations

import argparse
import gzip
import io
import os
import stat
import subprocess
import sys
import tarfile
import time
import zipfile
from pathlib import Path

SKIP_DIRS = {".git", "__pycache__"}


def mode_of(path: Path) -> int:
    st = path.lstat()
    if stat.S_ISDIR(st.st_mode):
        return 0o755
    return 0o755 if st.st_mode & 0o111 else 0o644


def git_files(root: Path) -> list[str] | None:
    """Files git would ship from `root`, or None when it is not a work tree."""
    if not (root / ".git").exists():
        return None
    try:
        out = subprocess.run(
            ["git", "-C", str(root), "ls-files", "-z", "--cached", "--others",
             "--exclude-standard"],
            check=True, stdout=subprocess.PIPE, stderr=subprocess.DEVNULL,
        ).stdout
    except (OSError, subprocess.CalledProcessError):
        return None
    names = sorted({n for n in out.decode("utf-8").split("\0") if n})
    # A deleted-but-tracked file is listed by --cached; it is not in the tree.
    return [n for n in names if (root / n).is_file() or (root / n).is_symlink()]


def walk_files(root: Path) -> list[str]:
    found: list[str] = []
    for dirpath, dirnames, filenames in os.walk(root):
        dirnames[:] = sorted(d for d in dirnames if d not in SKIP_DIRS)
        for name in filenames:
            if name == ".DS_Store":
                continue
            found.append(os.path.relpath(os.path.join(dirpath, name), root))
    return sorted(p.replace(os.sep, "/") for p in found)


def collect(dest: str, src: Path) -> list[tuple[str, Path]]:
    """(archive path, filesystem path) for every file under one member."""
    if src.is_file():
        return [(dest, src)]
    if not src.is_dir():
        raise SystemExit(f"make-archive: missing input: {src}")
    names = git_files(src)
    if names is None:
        names = walk_files(src)
    return [(f"{dest}/{name}", src / name) for name in names]


def with_dirs(files: list[tuple[str, Path]]) -> list[tuple[str, Path | None]]:
    """Add every parent directory once, then sort the whole set by path."""
    entries: dict[str, Path | None] = {}
    for arc, path in files:
        if arc in entries:
            raise SystemExit(f"make-archive: duplicate archive path: {arc}")
        entries[arc] = path
        parent = arc.rsplit("/", 1)[0] if "/" in arc else ""
        while parent and parent + "/" not in entries:
            entries[parent + "/"] = None
            parent = parent.rsplit("/", 1)[0] if "/" in parent else ""
    return sorted(entries.items(), key=lambda item: item[0])


def refuse_links(files: list[tuple[str, Path]]) -> None:
    # A pak installs onto FAT32, which has no symlinks. (A source tarball keeps
    # upstream's links as links: RetroArch's tree has a few under pkg/apple.)
    for arc, path in files:
        if path.is_symlink():
            raise SystemExit(f"make-archive: refusing a symlink: {arc}")


def write_zip(out: Path, epoch: int, root: Path, name: str) -> None:
    files = collect(name, root / name)
    refuse_links(files)
    date_time = time.gmtime(epoch)[:6]
    with zipfile.ZipFile(out, "w") as archive:
        for arc, path in with_dirs(files):
            info = zipfile.ZipInfo(arc, date_time=date_time)
            info.create_system = 3  # Unix, so external_attr carries the mode
            if path is None:
                info.external_attr = (stat.S_IFDIR | 0o755) << 16 | 0x10
                info.compress_type = zipfile.ZIP_STORED
                archive.writestr(info, b"")
                continue
            info.external_attr = (stat.S_IFREG | mode_of(path)) << 16
            info.compress_type = zipfile.ZIP_DEFLATED
            archive.writestr(info, path.read_bytes(), compresslevel=9)


def write_tar(out: Path, epoch: int, members: list[tuple[str, Path]]) -> None:
    files: list[tuple[str, Path]] = []
    for dest, src in members:
        files.extend(collect(dest, src))
    buffer = io.BytesIO()
    with tarfile.open(fileobj=buffer, mode="w", format=tarfile.GNU_FORMAT) as archive:
        for arc, path in with_dirs(files):
            info = tarfile.TarInfo(arc.rstrip("/"))
            info.mtime = epoch
            info.uid = info.gid = 0
            info.uname = info.gname = ""
            if path is None:
                info.type = tarfile.DIRTYPE
                info.mode = 0o755
                archive.addfile(info)
                continue
            if path.is_symlink():
                info.type = tarfile.SYMTYPE
                info.mode = 0o777
                info.linkname = os.readlink(path)
                archive.addfile(info)
                continue
            data = path.read_bytes()
            info.type = tarfile.REGTYPE
            info.mode = mode_of(path)
            info.size = len(data)
            archive.addfile(info, io.BytesIO(data))
    with open(out, "wb") as raw:
        # filename="" and mtime=0: the header names nothing and dates nothing.
        with gzip.GzipFile(filename="", mode="wb", fileobj=raw, compresslevel=9,
                           mtime=0) as compressed:
            compressed.write(buffer.getvalue())


def main() -> int:
    parser = argparse.ArgumentParser()
    parser.add_argument("format", choices=("zip", "tar"))
    parser.add_argument("--epoch", required=True, type=int)
    parser.add_argument("--out", required=True, type=Path)
    parser.add_argument("--root", type=Path, help="zip: the directory holding NAME")
    parser.add_argument("--member", action="append", default=[],
                        help="tar: DEST=SRC, a file or a directory")
    parser.add_argument("name", nargs="?", help="zip: the directory to archive")
    args = parser.parse_intermixed_args()

    tmp = args.out.with_name(args.out.name + ".tmp")
    tmp.unlink(missing_ok=True)
    if args.format == "zip":
        if args.root is None or not args.name:
            parser.error("zip needs --root and NAME")
        write_zip(tmp, args.epoch, args.root, args.name)
    else:
        if not args.member:
            parser.error("tar needs at least one --member")
        members = []
        for spec in args.member:
            dest, sep, src = spec.partition("=")
            if not sep or not dest or not src:
                parser.error(f"bad --member {spec!r}; expected DEST=SRC")
            members.append((dest.strip("/"), Path(src)))
        write_tar(tmp, args.epoch, members)
    os.replace(tmp, args.out)
    return 0


if __name__ == "__main__":
    sys.exit(main())
