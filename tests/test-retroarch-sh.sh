#!/bin/sh
# Host test for pak/scripts/retroarch.sh, the LEAF-RA-1 frontend wrapper. The
# 32-bit loader is replaced by a stub that records its arguments and
# environment, so the wrapper's command line, 32-bit environment and one-time
# settings move are checked without a device.
set -eu

REPO_ROOT="$(CDPATH= cd -- "$(dirname -- "$0")/.." && pwd)"
TMP="$(mktemp -d)"
trap 'rm -rf "$TMP"' EXIT

fail() {
    echo "FAIL $*" >&2
    exit 1
}

PAK="$TMP/Yabadabadoo.pak"
cp -R "$REPO_ROOT/pak" "$PAK"
mkdir -p "$PAK/runtime/lib" "$PAK/bin" "$PAK/cores"
cat >"$PAK/runtime/lib/ld-linux-armhf.so.3" <<'EOF'
#!/bin/sh
printf '%s\n' "$#" "$@" >"$STUB_OUT/args"
env >"$STUB_OUT/env"
pwd >"$STUB_OUT/cwd"
EOF
chmod +x "$PAK/runtime/lib/ld-linux-armhf.so.3"
: >"$PAK/bin/retroarch"
: >"$PAK/cores/yabadabadoo_libretro.so"

CARD="$TMP/card"
INTERNAL="$CARD/.umrk/mlp1"
RA_HOME="$INTERNAL/retroarch"
USERDATA="$CARD/.userdata/mlp1"
mkdir -p "$CARD/Roms/SATURN" "$TMP/stub"
ROM="$CARD/Roms/SATURN/Game (USA) [Disc 1] *.chd"
: >"$ROM"
CORE="$PAK/cores/yabadabadoo_libretro.so"
CFG="$RA_HOME/retroarch-current-1234.cfg"

ARGS="$TMP/stub/args"
ENVF="$TMP/stub/env"
ERR="$TMP/stderr"

# Leaf's environment for a RetroArch session, plus the 64-bit variables the
# wrapper has to drop. Extra "NAME=value" arguments override or add to it.
run() {
    rm -f "$ARGS" "$ENVF"
    env -i PATH="$PATH" STUB_OUT="$TMP/stub" \
        PLATFORM=mlp1 SDCARD_PATH="$CARD" USERDATA_PATH="$USERDATA" \
        UMRK_INTERNAL_DATA_PATH="$INTERNAL" HOME="$RA_HOME" \
        UMRK_PLATFORM_PATH="$CARD/.system/leaf/platforms/mlp1" \
        WAYLAND_DISPLAY=wayland-1 SDL_JOYSTICK_DEVICE=/dev/input/event6 \
        SDL_JOYSTICK_DISABLE_UDEV=1 UMRK_LANGUAGE=en \
        LD_LIBRARY_PATH=/lib64-only LD_PRELOAD=/lib64-only/shim.so \
        "$@" 2>"$ERR.raw"
    rc=$?
    # glibc's loader warns once for every program started with the deliberately
    # unloadable preload above, before the wrapper drops it. Those lines are the
    # loader's, not the wrapper's (macOS ignores LD_PRELOAD and prints none).
    grep -v "^ERROR: ld.so: object '/lib64-only/shim.so' from LD_PRELOAD cannot be preloaded" \
        "$ERR.raw" >"$ERR" || :
    return "$rc"
}
launch() { run "$@" sh "$PAK/scripts/retroarch.sh" -L "$CORE" --config "$CFG" "$ROM"; }

# --- the command line is Leaf's, untouched -----------------------------------
launch || fail "launch failed"
expected="10
--library-path
$PAK/runtime/lib
--argv0
retroarch
$PAK/bin/retroarch
-L
$CORE
--config
$CFG
$ROM"
[ "$(cat "$ARGS")" = "$expected" ] || { cat "$ARGS" >&2; fail "loader arguments"; }

# A saved-state entry slot, and arguments the wrapper must not interpret.
run sh "$PAK/scripts/retroarch.sh" -L "$CORE" --config "$CFG" -e 3 "$ROM" || fail "launch with -e failed"
expected="12
--library-path
$PAK/runtime/lib
--argv0
retroarch
$PAK/bin/retroarch
-L
$CORE
--config
$CFG
-e
3
$ROM"
[ "$(cat "$ARGS")" = "$expected" ] || { cat "$ARGS" >&2; fail "-e slot not passed through verbatim"; }

run sh "$PAK/scripts/retroarch.sh" --verbose --menu -L "$CORE" "two words" '--' "$ROM" ||
    fail "launch with extra flags failed"
[ "$(sed -n '1p' "$ARGS")" = "12" ] || fail "extra flags: argument count"
[ "$(sed -n '7,13p' "$ARGS")" = "--verbose
--menu
-L
$CORE
two words
--
$ROM" ] || { cat "$ARGS" >&2; fail "extra flags not passed through"; }

# --- the 32-bit environment --------------------------------------------------
launch || fail "launch failed"
! grep -q '^LD_LIBRARY_PATH=' "$ENVF" || fail "64-bit LD_LIBRARY_PATH leaked"
! grep -q '^LD_PRELOAD=' "$ENVF" || fail "64-bit LD_PRELOAD leaked"
grep -qx 'SDL_VIDEODRIVER=wayland' "$ENVF" || fail "SDL video driver"
grep -qx 'XDG_RUNTIME_DIR=/run' "$ENVF" || fail "XDG_RUNTIME_DIR default"
grep -qx 'SDL_VIDEO_EGL_DRIVER=libEGL.so.1' "$ENVF" || fail "EGL driver name"
grep -qx 'SDL_VIDEO_GL_DRIVER=libGLESv2.so.2' "$ENVF" || fail "GL driver name"
grep -qx 'PULSE_SERVER=unix:/tmp/pulse-socket' "$ENVF" || fail "PULSE_SERVER default"
grep -qx "PULSE_CLIENTCONFIG=$PAK/defaults/pulse-client.conf" "$ENVF" || fail "Pulse client config"
[ -f "$PAK/defaults/pulse-client.conf" ] || fail "pulse-client.conf is not shipped"

# Everything else Leaf set survives, HOME included.
grep -qx "HOME=$RA_HOME" "$ENVF" || fail "HOME"
grep -qx 'WAYLAND_DISPLAY=wayland-1' "$ENVF" || fail "WAYLAND_DISPLAY"
grep -qx 'SDL_JOYSTICK_DEVICE=/dev/input/event6' "$ENVF" || fail "SDL_JOYSTICK_DEVICE"
grep -qx 'SDL_JOYSTICK_DISABLE_UDEV=1' "$ENVF" || fail "SDL_JOYSTICK_DISABLE_UDEV"
grep -qx 'UMRK_LANGUAGE=en' "$ENVF" || fail "UMRK_LANGUAGE"
grep -qx "SDCARD_PATH=$CARD" "$ENVF" || fail "SDCARD_PATH"

# Values Leaf (or the session) already chose are not replaced.
launch XDG_RUNTIME_DIR=/run/user/0 PULSE_SERVER=unix:/other.sock || fail "launch failed"
grep -qx 'XDG_RUNTIME_DIR=/run/user/0' "$ENVF" || fail "XDG_RUNTIME_DIR overridden"
grep -qx 'PULSE_SERVER=unix:/other.sock' "$ENVF" || fail "PULSE_SERVER overridden"

# --- no config of its own ----------------------------------------------------
[ ! -e "$USERDATA/Yabadabadoo" ] || fail "wrapper wrote a 0.2-style state directory"
[ ! -e "$INTERNAL" ] || fail "wrapper wrote into Leaf's state with nothing to move"
[ ! -s "$ERR" ] || { cat "$ERR" >&2; fail "unexpected output with nothing to move"; }
[ ! -e "$PAK/defaults/retroarch.cfg" ] && [ ! -e "$PAK/defaults/autoconfig" ] ||
    fail "the 0.2 config and controller profile still ship"
[ ! -e "$PAK/scripts/run.sh" ] || fail "run.sh still ships"

# --- a broken install says so ------------------------------------------------
mv "$PAK/runtime/lib/ld-linux-armhf.so.3" "$TMP/loader.away"
set +e
launch >/dev/null 2>&1
[ $? -eq 127 ] || fail "a missing loader should exit 127"
set -e
mv "$TMP/loader.away" "$PAK/runtime/lib/ld-linux-armhf.so.3"

# --- the one-time move of 0.2 settings ---------------------------------------
OLD="$USERDATA/Yabadabadoo"
NEW="$RA_HOME/config/Yabadabadoo"
mkdir -p "$OLD/config/Yabadabadoo/sub" "$OLD/home"
printf 'opt0.2\n' >"$OLD/config/Yabadabadoo/Yabadabadoo.opt"
printf 'cfg0.2\n' >"$OLD/config/Yabadabadoo/Yabadabadoo.cfg"
printf 'rmp0.2\n' >"$OLD/config/Yabadabadoo/Yabadabadoo.rmp"
printf 'game0.2\n' >"$OLD/config/Yabadabadoo/sub/Game.opt"
# 0.2's own retroarch.cfg and managed.cfg are not core settings and stay put.
printf 'video_smooth = "true"\n' >"$OLD/retroarch.cfg"

launch || fail "launch with 0.2 settings failed"
[ -s "$ARGS" ] || fail "loader not reached with 0.2 settings"
for f in Yabadabadoo.opt Yabadabadoo.cfg Yabadabadoo.rmp sub/Game.opt; do
    cmp -s "$OLD/config/Yabadabadoo/$f" "$NEW/$f" || fail "$f was not copied"
done
find "$RA_HOME" -name '*.moving' | grep -q . && fail "temporary copy left behind"
[ ! -e "$RA_HOME/retroarch.cfg" ] || fail "0.2's retroarch.cfg reached Leaf's shared config"
[ "$(cat "$OLD/retroarch.cfg")" = 'video_smooth = "true"' ] || fail "original retroarch.cfg changed"
[ "$(cat "$OLD/config/Yabadabadoo/Yabadabadoo.opt")" = "opt0.2" ] || fail "original option file changed"
grep -q 'moved 4 core option' "$ERR" || { cat "$ERR" >&2; fail "no note of the move"; }

# Second launch: nothing is copied again. A file edited in Leaf's folder is
# kept, and one deleted there stays deleted.
printf 'opt-edited-in-leaf\n' >"$NEW/Yabadabadoo.opt"
rm -f "$NEW/Yabadabadoo.rmp"
launch || fail "second launch failed"
[ "$(cat "$NEW/Yabadabadoo.opt")" = "opt-edited-in-leaf" ] || fail "an edited file was overwritten"
[ ! -e "$NEW/Yabadabadoo.rmp" ] || fail "a deleted file came back"
[ ! -s "$ERR" ] || { cat "$ERR" >&2; fail "second launch moved files again"; }

# A file already in Leaf's folder is never replaced, even on the first move.
rm -rf "$RA_HOME/config" "$OLD/.config-moved-to-leaf"
mkdir -p "$NEW"
printf 'already-there\n' >"$NEW/Yabadabadoo.cfg"
launch || fail "launch over an existing file failed"
[ "$(cat "$NEW/Yabadabadoo.cfg")" = "already-there" ] || fail "an existing file was overwritten"
cmp -s "$OLD/config/Yabadabadoo/Yabadabadoo.opt" "$NEW/Yabadabadoo.opt" || fail "missing file not copied around an existing one"
grep -q 'moved 3 core option' "$ERR" || { cat "$ERR" >&2; fail "move count with an existing file"; }

# Without UMRK_INTERNAL_DATA_PATH or USERDATA_PATH, the card layout is used.
rm -rf "$RA_HOME/config" "$OLD/.config-moved-to-leaf"
launch UMRK_INTERNAL_DATA_PATH= USERDATA_PATH= || fail "launch without data paths failed"
cmp -s "$OLD/config/Yabadabadoo/Yabadabadoo.rmp" "$NEW/Yabadabadoo.rmp" || fail "card-layout fallback did not copy"

# A move that cannot finish never stops the launch, and is retried next time.
rm -rf "$INTERNAL" "$OLD/.config-moved-to-leaf"
mkdir -p "$INTERNAL"
: >"$RA_HOME"   # a file where Leaf's state directory should be
launch || fail "a blocked move stopped the launch"
[ -s "$ARGS" ] || fail "loader not reached after a blocked move"
[ ! -e "$OLD/.config-moved-to-leaf" ] || fail "a failed move was marked done"
rm -f "$RA_HOME"
mkdir -p "$RA_HOME"
launch || fail "retry launch failed"
cmp -s "$OLD/config/Yabadabadoo/Yabadabadoo.opt" "$NEW/Yabadabadoo.opt" || fail "the move was not retried"

echo "PASS test-retroarch-sh"
