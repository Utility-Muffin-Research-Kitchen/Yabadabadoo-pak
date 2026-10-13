#!/usr/bin/env bash
# Build the pak inside the digest-pinned Debian bookworm image (see the
# Makefile's `package` target). Inputs are read-only: this repository at
# /repo and the patched sources from scripts/fetch-sources.sh at /src. The
# finished package and its build record are written under /out.
#
# Everything is built for armhf: the Yabadabadoo core keeps its ARMv7 SH-2
# recompiler, which has no AArch64 backend, so the core, the RetroArch that
# hosts it and the whole userland they load are 32-bit. The MLP1 kernel runs
# 32-bit ARM programs; its rootfs has no 32-bit libraries, so they ship here.
#
# The RetroArch in /src already carries Leaf's MLP1 patch set (see
# scripts/fetch-sources.sh), which is what lets Leaf drive it like its own:
# the command-port extensions behind its in-game menu, boot resume and
# Switcher. Recording needs FFmpeg, which this build leaves out, but those
# patches still compile and stay in so the source matches Leaf's.
set -euo pipefail

REPO=/repo
SRC=/src
OUT=/out
WORK=/tmp/build
PAK_NAME=Yabadabadoo.pak
PACKAGE="$OUT/package/$PAK_NAME"
JOBS="${JOBS:-$(nproc)}"

lock_get() {
    python3 -I -c 'import json,sys
v = json.load(open(sys.argv[1]))
for k in sys.argv[2:]:
    v = v[k]
print(v)' "$REPO/upstream.lock.json" "$@"
}

echo "=== Installing the armhf cross toolchain and libraries"
export DEBIAN_FRONTEND=noninteractive
dpkg --add-architecture armhf
apt-get update -qq
apt-get install -y -qq --no-install-recommends \
    ca-certificates curl git make python3 pkg-config crossbuild-essential-armhf \
    libsdl2-dev:armhf libpulse-dev:armhf libasound2-dev:armhf \
    libfreetype-dev:armhf zlib1g-dev:armhf libegl-dev:armhf libgles-dev:armhf \
    >/dev/null

rm -rf "$WORK" "$PACKAGE"
mkdir -p "$WORK" "$PACKAGE"
# Build in copies so /src stays exactly what the source archive ships.
cp -a "$SRC/yabadabadoo" "$WORK/yabadabadoo"
cp -a "$SRC/retroarch" "$WORK/retroarch"

# Both upstream Makefiles embed `git rev-parse --short HEAD` in the binary.
# Left to git, that depends on the build host: as root in here, git refuses a
# checkout the host user owns (a Linux runner's bind mount, unlike Docker
# Desktop's) and the version comes out blank, and the abbreviation grows with
# the clone's object count. The pinned commits stand in for it instead.
YABADABADOO_GIT="$(lock_get yabadabadoo commit | cut -c1-7)"
RETROARCH_GIT="$(lock_get retroarch commit | cut -c1-7)"
embeds() { # embeds FILE STRING
    LC_ALL=C grep -aqF "$2" "$1" || { echo "$1 does not embed '$2'" >&2; exit 1; }
}

echo "=== Building the Yabadabadoo core (armhf, ARMv7 SH-2 recompiler)"
# Upstream's own value carries the quotes and the leading space.
make -C "$WORK/yabadabadoo/yabause/src/libretro" -j"$JOBS" platform=miyoomini \
    GIT_VERSION="\" $YABADABADOO_GIT\"" \
    >"$WORK/core-build.log" 2>&1 || { tail -40 "$WORK/core-build.log"; exit 1; }
CORE="$WORK/yabadabadoo/yabause/src/libretro/yabadabadoo_libretro.so"
arm-linux-gnueabihf-strip --strip-unneeded "$CORE"
embeds "$CORE" " $YABADABADOO_GIT"

echo "=== Building RetroArch (armhf, SDL2 + EGL/GLES on Wayland, PulseAudio)"
(
    cd "$WORK/retroarch"
    export CFLAGS="-O2 -march=armv7-a -mfpu=neon-vfpv4 -mfloat-abi=hard -D_GNU_SOURCE"
    export CXXFLAGS="$CFLAGS"
    export PKG_CONF_PATH=arm-linux-gnueabihf-pkg-config
    CC=arm-linux-gnueabihf-gcc CXX=arm-linux-gnueabihf-g++ ./configure \
        --host=arm-linux-gnueabihf \
        --disable-qt --disable-discord --disable-x11 --disable-wayland \
        --enable-pulse --disable-jack --disable-oss \
        --disable-vulkan --disable-vulkan_display --disable-opengl1 --disable-opengl_core \
        --disable-kms --disable-mali_fbdev --enable-ssl --enable-networking --enable-command \
        --enable-sdl2 --enable-alsa --disable-udev --enable-freetype --enable-zlib \
        --enable-opengles --enable-opengles3 --enable-egl --disable-ffmpeg \
        >"$WORK/retroarch-configure.log" 2>&1 || { tail -40 "$WORK/retroarch-configure.log"; exit 1; }
    make -j"$JOBS" GIT_VERSION="$RETROARCH_GIT" \
        >"$WORK/retroarch-build.log" 2>&1 || { tail -40 "$WORK/retroarch-build.log"; exit 1; }
)
RETROARCH="$WORK/retroarch/retroarch"
arm-linux-gnueabihf-strip "$RETROARCH"
embeds "$RETROARCH" "$RETROARCH_GIT"

echo "=== Fetching the pinned Rockchip Mali armhf userspace"
MALI_WORK="$WORK/mali"
MALI_DEB="$MALI_WORK/mali.deb"
mkdir -p "$MALI_WORK/root" "$MALI_WORK/lib"
curl -fsSL "$(lock_get mali deb_url)" -o "$MALI_DEB"
check() { # check WHAT FILE SHA256
    local got
    got="$(sha256sum "$2" | cut -d' ' -f1)"
    if [ "$got" != "$3" ]; then
        echo "$1 sha256 mismatch: $got != $3" >&2
        exit 1
    fi
}
check "Mali deb" "$MALI_DEB" "$(lock_get mali deb_sha256)"
[ "$(wc -c <"$MALI_DEB")" -eq "$(lock_get mali deb_size)" ] || { echo "Mali deb size mismatch" >&2; exit 1; }
dpkg-deb -x "$MALI_DEB" "$MALI_WORK/root"
MALI_LIB="$MALI_WORK/root/usr/lib/arm-linux-gnueabihf"
MALI_COPYRIGHT="$MALI_WORK/root/usr/share/doc/$(lock_get mali package)/copyright"
check "Mali blob" "$MALI_LIB/libmali.so.1.9.0" "$(lock_get mali blob_sha256)"
check "Mali hook" "$MALI_LIB/libmali-hook.so.1.9.0" "$(lock_get mali hook_sha256)"
check "Mali copyright" "$MALI_COPYRIGHT" "$(lock_get mali copyright_sha256)"
# The vendor EGL/GLES/GBM/wayland-egl libraries load libmali.so.1; the deb
# ships them as symlinks, which FAT32 cannot hold, so they become copies.
cp "$MALI_LIB/libmali.so.1.9.0" "$MALI_WORK/lib/libmali.so.1"
cp "$MALI_LIB/libmali-hook.so.1.9.0" "$MALI_WORK/lib/libmali-hook.so.1"
for lib in libEGL.so.1 libGLESv1_CM.so.1 libGLESv2.so.2 libgbm.so.1 libwayland-egl.so.1; do
    cp -L "$MALI_LIB/mali/$lib" "$MALI_WORK/lib/$lib"
done

echo "=== Assembling $PAK_NAME"
cp -a "$REPO/pak/." "$PACKAGE/"
mkdir -p "$PACKAGE/bin" "$PACKAGE/cores" "$PACKAGE/info" "$PACKAGE/runtime/lib" "$PACKAGE/licenses/mali"
install -m 0755 "$RETROARCH" "$PACKAGE/bin/retroarch"
install -m 0755 "$CORE" "$PACKAGE/cores/yabadabadoo_libretro.so"
# RetroArch and Leaf read the core's metadata from this file. Upstream ships
# it for Onion OS; its corename is the core's library_name, which RetroArch
# sorts saves and states by and which pak.json's config_folder must equal.
install -m 0644 "$WORK/yabadabadoo/packaging/onion/RetroArch/.retroarch/cores/yabadabadoo_libretro.info" \
    "$PACKAGE/info/yabadabadoo_libretro.info"

python3 -I "$REPO/scripts/collect-runtime.py" \
    --mali-dir "$MALI_WORK/lib" \
    --mali-package "$(lock_get mali package):armhf" \
    --mali-version "$(lock_get mali release_tag) ($(lock_get mali driver_release))" \
    --out-lib "$PACKAGE/runtime/lib" \
    --out-licenses "$PACKAGE/licenses" \
    --manifest "$PACKAGE/licenses/runtime-manifest.json" \
    "$PACKAGE/bin/retroarch" "$PACKAGE/cores/yabadabadoo_libretro.so"

cp "$MALI_COPYRIGHT" "$PACKAGE/licenses/mali/libmali-rockchip-debian-copyright"
cp "$WORK/retroarch/COPYING" "$PACKAGE/licenses/RetroArch-COPYING.txt"
cp "$WORK/yabadabadoo/yabause/COPYING" "$PACKAGE/licenses/Yabadabadoo-COPYING.txt"
cp "$WORK/yabadabadoo/packaging/THIRD-PARTY-NOTICES.txt" "$PACKAGE/licenses/Yabadabadoo-THIRD-PARTY-NOTICES.txt"

python3 -I - "$PACKAGE" "$REPO" <<'PY'
import hashlib, json, sys
from pathlib import Path
pak, repo = Path(sys.argv[1]), Path(sys.argv[2])
lock = json.load(open(repo / "upstream.lock.json"))
def digest(path):
    return hashlib.sha256(Path(path).read_bytes()).hexdigest()
leaf = json.load(open(repo / "patches/retroarch/leaf/SOURCE.json"))
def local_patches(subdir):
    return [{"file": p.name, "sha256": digest(p)}
            for p in sorted((repo / "patches" / subdir).glob("*.patch"))]
record = {
    "schema": 2,
    "pak_version": json.load(open(pak / "pak.json"))["pak_version"],
    "yabadabadoo": {k: lock["yabadabadoo"][k] for k in ("repo", "tag", "commit")},
    "retroarch": {k: lock["retroarch"][k] for k in ("repo", "tag", "commit")},
    "patches": {
        "yabadabadoo": local_patches("yabadabadoo"),
        # In apply order: Leaf's set from retroarch-builds, then the pak's own.
        "retroarch_leaf_set": {
            "repo": leaf["repo"],
            "commit": leaf["commit"],
            "patch_set": leaf["patch_set"],
            "patches": [{k: p[k] for k in ("order", "name", "source_path", "sha256")}
                        for p in leaf["patches"]],
            "dropped": leaf["dropped"],
        },
        "retroarch_pak": local_patches("retroarch/pak"),
    },
    "image": lock["image"],
    "binaries": {rel: digest(pak / rel) for rel in (
        "bin/retroarch", "cores/yabadabadoo_libretro.so", "info/yabadabadoo_libretro.info")},
}
(pak / "BUILD-INFO.json").write_text(json.dumps(record, indent=2) + "\n")
PY

if [ -n "${HOST_UID:-}" ]; then
    chown -R "$HOST_UID:${HOST_GID:-$HOST_UID}" "$OUT"
fi
du -sh "$PACKAGE"
echo "Package ready: $PACKAGE"
