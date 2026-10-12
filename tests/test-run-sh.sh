#!/bin/sh
# Host test for pak/scripts/run.sh. The 32-bit loader is replaced by a stub
# that records its arguments and environment, so the wrapper's command line,
# generated config and error paths are checked without a device.
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
printf '%s\n' "$@" >"$STUB_OUT/args"
env >"$STUB_OUT/env"
EOF
chmod +x "$PAK/runtime/lib/ld-linux-armhf.so.3"
: >"$PAK/bin/retroarch"
: >"$PAK/cores/yabadabadoo_libretro.so"

CARD="$TMP/card"
mkdir -p "$CARD/Roms/SATURN" "$TMP/stub"
: >"$CARD/Roms/SATURN/Game (USA).chd"
ROM="$CARD/Roms/SATURN/Game (USA).chd"

run() {
    env -i PATH="$PATH" STUB_OUT="$TMP/stub" \
        PLATFORM=mlp1 SDCARD_PATH="$CARD" USERDATA_PATH="$CARD/.userdata/mlp1" \
        LOGS_PATH="${LOGS:-$CARD/.userdata/mlp1/logs}" \
        SAVES_PATH="$CARD/Saves" STATES_PATH="$CARD/States" BIOS_PATH="$CARD/BIOS" \
        UMRK_PLATFORM_PATH="$CARD/.system/leaf/platforms/mlp1" \
        JAWAKA_RETROARCH_JOYPAD_INDEX=1 \
        LD_LIBRARY_PATH=/lib64-only LD_PRELOAD=/lib64-only/shim.so \
        sh "$PAK/scripts/run.sh" "$@"
}

# --- argument handling --------------------------------------------------------
set +e
run >/dev/null 2>&1; [ $? -eq 2 ] || fail "no argument should exit 2"
run "$CARD/missing.chd" >/dev/null 2>&1; [ $? -eq 1 ] || fail "a missing game should exit 1"
set -e

# --- a normal launch ----------------------------------------------------------
run "$ROM" || fail "launch failed"
ARGS="$TMP/stub/args"
STATE="$CARD/.userdata/mlp1/Yabadabadoo"
expected="--library-path
$PAK/runtime/lib
--argv0
retroarch
$PAK/bin/retroarch
--verbose
-L
$PAK/cores/yabadabadoo_libretro.so
--config
$STATE/retroarch.cfg
--appendconfig
$STATE/managed.cfg
$ROM"
[ "$(cat "$ARGS")" = "$expected" ] || { cat "$ARGS" >&2; fail "loader arguments"; }

MANAGED="$STATE/managed.cfg"
grep -qx "system_directory = \"$CARD/BIOS/SATURN\"" "$MANAGED" || fail "BIOS directory"
grep -qx "savefile_directory = \"$CARD/Saves\"" "$MANAGED" || fail "saves directory"
grep -qx "savestate_directory = \"$CARD/States\"" "$MANAGED" || fail "states directory"
grep -qx 'input_player1_joypad_index = "0"' "$MANAGED" || fail "player 1 is the first roster pad"
grep -qx 'input_player2_joypad_index = "1"' "$MANAGED" || fail "player 2 is the second roster pad"
grep -qx 'input_menu_toggle_btn = "5"' "$MANAGED" || fail "menu on Guide"
grep -qx 'input_enable_hotkey_btn = "nul"' "$MANAGED" || fail "no hotkey modifier"
grep -qx 'menu_driver = "rgui"' "$MANAGED" || fail "RGUI without Leaf's assets"
grep -qx "joypad_autoconfig_dir = \"$PAK/defaults/autoconfig\"" "$MANAGED" ||
    fail "bundled controller profile without Leaf's"

ENV="$TMP/stub/env"
! grep -q '^LD_LIBRARY_PATH=' "$ENV" || fail "64-bit LD_LIBRARY_PATH leaked"
! grep -q '^LD_PRELOAD=' "$ENV" || fail "64-bit LD_PRELOAD leaked"
grep -qx 'SDL_VIDEODRIVER=wayland' "$ENV" || fail "SDL video driver"
grep -qx "HOME=$STATE/home" "$ENV" || fail "HOME"
grep -qx "PULSE_CLIENTCONFIG=$PAK/defaults/pulse-client.conf" "$ENV" || fail "Pulse client config"

# --- the user's settings survive, Leaf's assets are used when present --------
echo 'video_smooth = "true"' >>"$STATE/retroarch.cfg"
mkdir -p "$CARD/.system/leaf/platforms/mlp1/assets/ozone" \
    "$CARD/.system/leaf/platforms/mlp1/autoconfig"
: >"$CARD/.system/leaf/platforms/mlp1/autoconfig/Loong Gamepad.cfg"
run "$ROM" || fail "second launch failed"
grep -qx 'video_smooth = "true"' "$STATE/retroarch.cfg" || fail "user config overwritten"
grep -qx 'menu_driver = "ozone"' "$MANAGED" || fail "Ozone with Leaf's assets"
grep -qx "joypad_autoconfig_dir = \"$CARD/.system/leaf/platforms/mlp1/autoconfig\"" \
    "$MANAGED" || fail "Leaf's controller profile"

# --- an unwritable log never stops a launch -----------------------------------
rm -f "$ARGS"
mkdir -p "$TMP/ro-logs"
chmod 0555 "$TMP/ro-logs"
LOGS="$TMP/ro-logs/sub" run "$ROM" || fail "launch with an unwritable log dir"
chmod 0755 "$TMP/ro-logs"
[ -s "$ARGS" ] || fail "loader not reached with an unwritable log dir"

echo "PASS test-run-sh"
