#!/usr/bin/env python3
"""Copy the armhf shared-library closure of the pak's programs into one flat
directory, and record where every file came from.

Runs inside the build container, where the armhf Debian packages are
installed. The MLP1 rootfs has no 32-bit userland at all, so everything the
32-bit RetroArch and core load, down to the dynamic loader, ships in the pak:

    collect-runtime.py --mali-dir DIR --out-lib DIR --out-licenses DIR \
        --manifest FILE ELF [ELF ...]

- Dependencies are followed through DT_NEEDED (and DT_RUNPATH/DT_RPATH)
  with the cross readelf, searching the Mali directory first so the Rockchip
  Mali EGL/GLES/GBM libraries win over Debian's GLVND dispatchers.
- Each library is copied once, under the name it is NEEDED by, as a regular
  file: a pak installs onto FAT32, which has no symlinks.
- Every file is mapped to its Debian package with dpkg; the package's
  copyright file is copied beside it and its version and source package are
  written to the manifest, so the shipped bytes can be traced to the source.
"""
from __future__ import annotations

import argparse
import hashlib
import json
import os
import re
import shutil
import subprocess
from pathlib import Path

READELF = "arm-linux-gnueabihf-readelf"
DEBIAN_DIRS = [
    "/usr/lib/arm-linux-gnueabihf",
    "/lib/arm-linux-gnueabihf",
]
LOADER = "ld-linux-armhf.so.3"
# Loaded by the Mali vendor libraries at run time rather than through
# DT_NEEDED; harmless if it is NEEDED as well.
EXTRA_LIBS = ["libmali-hook.so.1"]

NEEDED_RE = re.compile(r"\(NEEDED\)\s+Shared library: \[(.+)\]")
RUNPATH_RE = re.compile(r"\((?:RUNPATH|RPATH)\)\s+Library (?:runpath|rpath): \[(.+)\]")


def dynamic_section(path: Path) -> tuple[list[str], list[str]]:
    out = subprocess.run([READELF, "-dW", str(path)], check=True,
                         stdout=subprocess.PIPE, text=True).stdout
    needed = NEEDED_RE.findall(out)
    runpaths: list[str] = []
    for value in RUNPATH_RE.findall(out):
        for entry in value.split(":"):
            runpaths.append(entry.replace("$ORIGIN", str(path.resolve().parent)))
    return needed, runpaths


def resolve(name: str, dirs: list[str]) -> Path | None:
    for directory in dirs:
        candidate = Path(directory) / name
        if candidate.exists():
            return candidate
    return None


def sha256(path: Path) -> str:
    return hashlib.sha256(path.read_bytes()).hexdigest()


def dpkg_owner(path: Path) -> str | None:
    """The armhf package that installed `path` (merged-/usr aware)."""
    real = str(path.resolve())
    candidates = {real, str(path)}
    for alias_from, alias_to in (("/usr/lib/", "/lib/"), ("/lib/", "/usr/lib/")):
        for item in list(candidates):
            if item.startswith(alias_from):
                candidates.add(alias_to + item[len(alias_from):])
    for item in sorted(candidates):
        result = subprocess.run(["dpkg", "-S", item], stdout=subprocess.PIPE,
                                stderr=subprocess.DEVNULL, text=True)
        if result.returncode == 0 and result.stdout:
            # "libc6:armhf: /usr/lib/...", or "pkg1, pkg2: /path" when diverted
            return result.stdout.split(": ", 1)[0].split(",")[0].strip()
    return None


def package_info(package: str) -> dict:
    fields = "${Package}\t${Architecture}\t${Version}\t${source:Package}\t${source:Version}"
    out = subprocess.run(["dpkg-query", "-W", "-f", fields, package], check=True,
                         stdout=subprocess.PIPE, text=True).stdout
    name, arch, version, source, source_version = out.split("\t")
    return {
        "package": f"{name}:{arch}",
        "version": version,
        "source_package": source,
        "source_version": source_version,
        "source_url": f"https://snapshot.debian.org/package/{source}/{source_version}/",
    }


def copy_copyright(package: str, out_licenses: Path) -> str:
    name = package.split(":", 1)[0]
    src = Path("/usr/share/doc") / name / "copyright"
    if not src.exists():
        raise SystemExit(f"collect-runtime: no copyright file for {package}")
    dest = out_licenses / "debian" / f"{name}.copyright"
    dest.parent.mkdir(parents=True, exist_ok=True)
    shutil.copyfile(src.resolve(), dest)
    return f"licenses/debian/{dest.name}"


def main() -> int:
    parser = argparse.ArgumentParser()
    parser.add_argument("--mali-dir", required=True, type=Path)
    parser.add_argument("--mali-package", required=True)
    parser.add_argument("--mali-version", required=True)
    parser.add_argument("--out-lib", required=True, type=Path)
    parser.add_argument("--out-licenses", required=True, type=Path)
    parser.add_argument("--manifest", required=True, type=Path)
    parser.add_argument("elf", nargs="+", type=Path)
    args = parser.parse_args()

    mali_dir = str(args.mali_dir.resolve())
    search = [mali_dir] + DEBIAN_DIRS
    args.out_lib.mkdir(parents=True, exist_ok=True)

    resolved: dict[str, Path] = {}
    queue: list[tuple[str, Path]] = []
    for elf in args.elf:
        needed, runpaths = dynamic_section(elf)
        search.extend(p for p in runpaths if p not in search)
        queue.extend((name, elf) for name in needed)
    for name in EXTRA_LIBS:
        queue.append((name, Path("<extra>")))

    while queue:
        name, wanted_by = queue.pop(0)
        if name in resolved:
            continue
        path = resolve(name, search)
        if path is None:
            raise SystemExit(f"collect-runtime: {name} (needed by {wanted_by}) not found")
        resolved[name] = path
        needed, runpaths = dynamic_section(path)
        search.extend(p for p in runpaths if p not in search)
        queue.extend((dep, path) for dep in needed)

    loader = resolve(LOADER, DEBIAN_DIRS)
    if loader is None:
        raise SystemExit("collect-runtime: no armhf dynamic loader")
    resolved[LOADER] = loader

    files = []
    packages: dict[str, dict] = {}
    for name in sorted(resolved):
        src = resolved[name]
        dest = args.out_lib / name
        shutil.copyfile(src.resolve(), dest)
        os.chmod(dest, 0o755)
        if str(src.resolve()).startswith(mali_dir) or str(src).startswith(mali_dir):
            package = args.mali_package
            if package not in packages:
                packages[package] = {
                    "package": package,
                    "version": args.mali_version,
                    "license_file": "licenses/mali/libmali-rockchip-debian-copyright",
                }
        else:
            owner = dpkg_owner(src)
            if owner is None:
                raise SystemExit(f"collect-runtime: no Debian package owns {src}")
            package = owner
            if package not in packages:
                info = package_info(package)
                info["license_file"] = copy_copyright(package, args.out_licenses)
                packages[package] = info
        files.append({
            "name": name,
            "size": dest.stat().st_size,
            "sha256": sha256(dest),
            "package": packages[package]["package"],
        })

    manifest = {
        "schema": 1,
        "loader": LOADER,
        "files": files,
        "packages": sorted(packages.values(), key=lambda p: p["package"]),
    }
    args.manifest.parent.mkdir(parents=True, exist_ok=True)
    args.manifest.write_text(json.dumps(manifest, indent=2) + "\n")
    total = sum(f["size"] for f in files)
    print(f"runtime: {len(files)} files from {len(packages)} packages, {total} bytes")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
