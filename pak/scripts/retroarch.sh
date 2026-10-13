#!/bin/sh
# Yabadabadoo's RetroArch frontend for Leaf on MLP1.
#
# This is the `frontend.path` of the `yabadabadoo` core in pak.json. Leaf's
# daemon starts the pak's RetroArch exactly like its own, so this is a wrapper
# and nothing more:
#
#     retroarch.sh -L <core> --config <cfg> [-e <slot>] <rom>
#
# The config file, the arguments and the environment are all Leaf's, and every
# argument is handed to RetroArch untouched. RetroArch's output goes where Leaf
# sends it.
#
# Yabadabadoo's SH-2 recompiler only exists for 32-bit ARM, so the core runs in
# a 32-bit RetroArch. The MLP1 rootfs has no 32-bit userland: the dynamic
# loader and every library RetroArch and the core load ship in runtime/lib, and
# nothing from the 64-bit system is mixed in. This wrapper only has to start
# that loader with the 32-bit side of the environment.
set -u

PAK="$(CDPATH= cd -- "$(dirname -- "$0")/.." && pwd)"
LOADER="$PAK/runtime/lib/ld-linux-armhf.so.3"
RETROARCH="$PAK/bin/retroarch"

# --- one-time move of 0.2 settings -------------------------------------------
# 0.2 ran its own RetroArch with its own state under
# $USERDATA_PATH/Yabadabadoo/. Leaf keeps core options, core overrides and
# remaps for every core under its RetroArch state directory, so the ones 0.2
# wrote are copied there once: files that are already there are never
# replaced, the originals stay where they are, and a marker beside them stops
# the copy from running again (a deleted override must stay deleted).
# Saves and states need no move; they were already in Saves/Yabadabadoo and
# States/Yabadabadoo. A failure here never stops a launch.
migrate_core_config() {
    platform="${PLATFORM:-mlp1}"
    userdata="${USERDATA_PATH:-}"
    internal="${UMRK_INTERNAL_DATA_PATH:-}"
    if [ -n "${SDCARD_PATH:-}" ]; then
        [ -n "$userdata" ] || userdata="$SDCARD_PATH/.userdata/$platform"
        [ -n "$internal" ] || internal="$SDCARD_PATH/.umrk/$platform"
    fi
    [ -n "$userdata" ] && [ -n "$internal" ] || return 0

    old_state="$userdata/Yabadabadoo"
    old="$old_state/config/Yabadabadoo"
    new="$internal/retroarch/config/Yabadabadoo"
    marker="$old_state/.config-moved-to-leaf"
    [ -d "$old" ] && [ ! -e "$marker" ] || return 0

    copied=0
    failed=0
    files="$(find "$old" -type f 2>/dev/null)"
    while IFS= read -r src; do
        [ -n "$src" ] || continue
        dest="$new/${src#"$old"/}"
        [ -e "$dest" ] && continue
        if mkdir -p "$(dirname -- "$dest")" &&
           cp "$src" "$dest.moving" && mv "$dest.moving" "$dest"; then
            copied=$((copied + 1))
        else
            rm -f "$dest.moving"
            failed=1
        fi
    done <<EOF
$files
EOF
    if [ "$failed" -eq 0 ]; then
        : >"$marker" 2>/dev/null
    fi
    if [ "$copied" -gt 0 ]; then
        echo "yabadabadoo: moved $copied core option, override and remap file(s) from 0.2 to $new" >&2
    fi
    return 0
}
migrate_core_config

# --- the 32-bit side of the environment --------------------------------------
# Leaf's library path and preloads are 64-bit and cannot be loaded here; the
# bundled loader gets its own --library-path below.
unset LD_LIBRARY_PATH LD_PRELOAD
# Weston owns the panel transform on MLP1, so RetroArch is a plain fullscreen
# Wayland client of the vendor EGL/GLES libraries shipped in runtime/lib.
export SDL_VIDEODRIVER=wayland
export XDG_RUNTIME_DIR="${XDG_RUNTIME_DIR:-/run}"
export SDL_VIDEO_EGL_DRIVER=libEGL.so.1
export SDL_VIDEO_GL_DRIVER=libGLESv2.so.2
# Jawaka's controller roster contract: SDL reads the frozen device list. Leaf
# sets this itself; the default only matters for a launch outside Leaf.
export SDL_JOYSTICK_DISABLE_UDEV="${SDL_JOYSTICK_DISABLE_UDEV:-1}"
# The 32-bit libpulse talks to Leaf's PulseAudio server and never starts one.
export PULSE_SERVER="${PULSE_SERVER:-unix:/tmp/pulse-socket}"
export PULSE_CLIENTCONFIG="$PAK/defaults/pulse-client.conf"

if [ ! -x "$LOADER" ] || [ ! -f "$RETROARCH" ]; then
    echo "yabadabadoo: the 32-bit loader or RetroArch is missing from $PAK; reinstall the pak" >&2
    exit 127
fi

exec "$LOADER" --library-path "$PAK/runtime/lib" --argv0 retroarch "$RETROARCH" "$@"
