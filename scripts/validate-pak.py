#!/usr/bin/env python3
"""Validate this pak against the content-pak contract.

The rules are not reimplemented here: the contract's own reference validator
(`content_model.py`) and schemas are loaded from a checkout of the public
leaf-contracts repository, which `make validate` fetches at a pinned commit.

    python3 scripts/validate-pak.py --contract <leaf-contracts> --pak pak/
    python3 scripts/validate-pak.py --contract <leaf-contracts> --pak build/package/Yabadabadoo.pak --packaged
"""
from __future__ import annotations

import argparse
import json
import sys
from pathlib import Path

# What a built package must carry besides pak.json and the wrapper: the 32-bit
# loader, RetroArch, the core, and the licence texts for what it redistributes.
PACKAGED_EXECUTABLES = (
    "scripts/run.sh",
    "bin/retroarch",
    "cores/yabadabadoo_libretro.so",
    "runtime/lib/ld-linux-armhf.so.3",
)
PACKAGED_FILES = (
    "defaults/retroarch.cfg",
    "defaults/pulse-client.conf",
    "defaults/autoconfig/Loong Gamepad.cfg",
    "runtime/lib/libmali.so.1",
    "runtime/lib/libEGL.so.1",
    "runtime/lib/libGLESv2.so.2",
    "licenses/RetroArch-COPYING.txt",
    "licenses/Yabadabadoo-COPYING.txt",
    "licenses/Yabadabadoo-THIRD-PARTY-NOTICES.txt",
    "licenses/mali/libmali-rockchip-debian-copyright",
    "licenses/runtime-manifest.json",
    "BUILD-INFO.json",
)


def load_contract(contract_root: Path):
    scripts = contract_root / "contracts" / "leaf-content" / "scripts"
    schema = contract_root / "contracts" / "leaf-content" / "content-paks-v1.schema.json"
    scrape_schema = (
        contract_root / "contracts" / "leaf-content" / "content-scrape-v1.schema.json"
    )
    if not scripts.is_dir() or not schema.is_file() or not scrape_schema.is_file():
        raise SystemExit(
            f"not a leaf-contracts checkout: {contract_root}\n"
            "expected CONTENT-1 and CONTENT-SCRAPE-1 under contracts/leaf-content/"
        )
    sys.path.insert(0, str(scripts))
    # minischema lives with the SVC-1 contract and is shared, not copied.
    sys.path.insert(0, str(contract_root / "contracts" / "leaf-services" / "scripts"))
    import content_model  # noqa: E402
    import minischema  # noqa: E402
    import scrape_model  # noqa: E402

    return (
        content_model,
        scrape_model,
        minischema,
        json.loads(schema.read_text()),
        json.loads(scrape_schema.read_text()),
    )


def check_package(pak_dir: Path) -> list[str]:
    problems = []
    for rel in PACKAGED_EXECUTABLES:
        path = pak_dir / rel
        if not path.is_file() or not path.stat().st_mode & 0o111:
            problems.append(f"package: missing or non-executable {rel}")
    for rel in PACKAGED_FILES:
        if not (pak_dir / rel).is_file():
            problems.append(f"package: missing {rel}")
    manifest = pak_dir / "licenses" / "runtime-manifest.json"
    if manifest.is_file():
        runtime = json.loads(manifest.read_text())
        listed = {entry["name"] for entry in runtime.get("files", [])}
        shipped = {p.name for p in (pak_dir / "runtime" / "lib").iterdir()}
        if listed != shipped:
            problems.append(
                "package: runtime/lib and licenses/runtime-manifest.json disagree: "
                f"unlisted {sorted(shipped - listed)}, missing {sorted(listed - shipped)}"
            )
        for package in runtime.get("packages", []):
            license_file = package.get("license_file")
            if not license_file or not (pak_dir / license_file).is_file():
                problems.append(f"package: no licence file for {package.get('package')}")
    for path in pak_dir.rglob("*"):
        if path.is_symlink():
            problems.append(f"package: symlink {path.relative_to(pak_dir)} (FAT32 has none)")
    return problems


def main() -> int:
    parser = argparse.ArgumentParser()
    parser.add_argument("--contract", required=True, type=Path)
    parser.add_argument("--pak", required=True, type=Path)
    parser.add_argument(
        "--packaged",
        action="store_true",
        help="the directory is a built package, so the binaries, runtime and "
             "licences must all be present",
    )
    args = parser.parse_args()

    content_model, scrape_model, minischema, schema, scrape_schema = load_contract(
        args.contract.resolve()
    )

    pak_dir = args.pak.resolve()
    manifest_path = pak_dir / "pak.json"
    if not manifest_path.is_file():
        raise SystemExit(f"no pak.json in {pak_dir}")
    manifest = json.loads(manifest_path.read_text())

    ok, err = minischema.is_valid(manifest, schema)
    if not ok:
        print(f"FAIL schema: {err}")
        return 1
    print("ok   schema: content-paks-v1")

    scrape_ok, scrape_err = minischema.is_valid(manifest, scrape_schema)
    if not scrape_ok:
        print(f"FAIL content scrape schema: {scrape_err}")
        return 1
    scrape_violations = scrape_model.validate(manifest)
    if scrape_violations:
        for reason in sorted(scrape_violations):
            print(f"FAIL {reason}")
        return 1
    print("ok   schema: content-scrape-v1")

    violations = content_model.validate_manifest(
        manifest, str(pak_dir),
        {"install_lane": "platform", "source_id": "primary"},
    )
    if violations:
        for reason in sorted(violations):
            print(f"FAIL {reason}")
        return 1
    print("ok   content model: path core target present and executable")

    if args.packaged:
        problems = check_package(pak_dir)
        if problems:
            for problem in problems:
                print(f"FAIL {problem}")
            return 1
        print("ok   package: loader, RetroArch, core, runtime and licences")

    for warning in sorted(content_model.manifest_warnings(manifest)):
        print(f"warn {warning}")

    provides = manifest["provides"]
    extensions = [e["system_id"] for e in provides.get("system_extensions", [])]
    cores = [c["id"] for c in provides.get("cores", [])]
    print(f"ok   provides: extensions={extensions} cores={cores}")

    # A pure content pak. A launch.sh would make it a hybrid that also shows
    # in Apps, which is not what this pak is.
    if (pak_dir / "launch.sh").exists():
        print("FAIL launch.sh present: this is meant to be a pure content pak")
        return 1
    print("ok   no launch.sh: pure content pak, not listed in Apps")

    print("PASS validate-pak")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
