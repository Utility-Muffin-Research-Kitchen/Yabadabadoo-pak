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

# RUN_ENV holds extra NAME=value words for one launch (no spaces in values);
# RUN_PATH replaces PATH for it.
RUN_ENV=""
RUN_PATH=""
run() {
    # shellcheck disable=SC2086
    env -i PATH="${RUN_PATH:-$PATH}" STUB_OUT="$TMP/stub" $RUN_ENV \
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
$STATE/session.cfg
--appendconfig
$STATE/managed.cfg
$ROM"
[ "$(cat "$ARGS")" = "$expected" ] || { cat "$ARGS" >&2; fail "loader arguments"; }

MANAGED="$STATE/managed.cfg"
SESSION="$STATE/session.cfg"
grep -qx "system_directory = \"$CARD/BIOS/SATURN\"" "$MANAGED" || fail "BIOS directory"
grep -qx "savefile_directory = \"$CARD/Saves\"" "$MANAGED" || fail "saves directory"
grep -qx "savestate_directory = \"$CARD/States\"" "$MANAGED" || fail "states directory"
grep -qx 'input_player1_joypad_index = "0"' "$MANAGED" || fail "player 1 is the first roster pad"
grep -qx 'input_player2_joypad_index = "1"' "$MANAGED" || fail "player 2 is the second roster pad"
grep -qx 'input_menu_toggle_btn = "5"' "$MANAGED" || fail "menu on Guide"
grep -qx 'input_enable_hotkey_btn = "nul"' "$MANAGED" || fail "no hotkey modifier"
grep -qx 'menu_driver = "rgui"' "$MANAGED" || fail "RGUI without Leaf's assets"
grep -qx 'ozone_menu_color_theme = "13"' "$MANAGED" || fail "Leaf's Ozone theme"
grep -qx 'user_language = "0"' "$MANAGED" || fail "English without a language"
grep -qx "joypad_autoconfig_dir = \"$PAK/defaults/autoconfig\"" "$MANAGED" ||
    fail "bundled controller profile without Leaf's"

ENV="$TMP/stub/env"
! grep -q '^LD_LIBRARY_PATH=' "$ENV" || fail "64-bit LD_LIBRARY_PATH leaked"
! grep -q '^LD_PRELOAD=' "$ENV" || fail "64-bit LD_PRELOAD leaked"
grep -qx 'SDL_VIDEODRIVER=wayland' "$ENV" || fail "SDL video driver"
grep -qx "HOME=$STATE/home" "$ENV" || fail "HOME"
grep -qx "PULSE_CLIENTCONFIG=$PAK/defaults/pulse-client.conf" "$ENV" || fail "Pulse client config"

# --- no Leaf files: the pak's defaults are the whole session config ----------
# This card has neither Leaf's packaged defaults nor a shared config.
[ -s "$SESSION" ] || fail "no session config without Leaf files"
while IFS= read -r line; do
    case "$line" in ''|'#'*) continue ;; esac
    grep -qxF -- "$line" "$SESSION" || fail "pak default missing from session.cfg: $line"
done <"$PAK/defaults/retroarch.cfg"
[ ! -e "$STATE/retroarch.cfg" ] || fail "a launch must not create the 0.2.0 retroarch.cfg"

# Every key exactly once: RetroArch keeps the first occurrence in a file.
assert_unique_keys() {
    dups="$(sed -e '/^[[:space:]]*#/d' -e '/^[[:space:]]*$/d' -e 's/[[:space:]]*=.*//' "$SESSION" |
        sort | uniq -d)"
    [ -z "$dups" ] || fail "$1: keys written more than once: $dups"
}
assert_unique_keys "no Leaf files"

# --- 0.2.0's retroarch.cfg is no longer read, and is left in place ------------
printf '%s\n' 'video_smooth = "true"' 'aspect_ratio_index = "9"' >"$STATE/retroarch.cfg"
cp "$STATE/retroarch.cfg" "$TMP/legacy.cfg"
run "$ROM" || fail "launch with a 0.2.0 retroarch.cfg"
cmp -s "$STATE/retroarch.cfg" "$TMP/legacy.cfg" || fail "0.2.0 retroarch.cfg was modified"
! grep -q "retroarch.cfg" "$ARGS" || fail "0.2.0 retroarch.cfg still passed to RetroArch"
grep -qx 'video_smooth = "false"' "$SESSION" || fail "0.2.0 retroarch.cfg still read"
grep -qx 'aspect_ratio_index = "22"' "$SESSION" || fail "0.2.0 retroarch.cfg still read"

# --- Leaf's settings come across through the allowlist ------------------------
LEAF="$CARD/.system/leaf/platforms/mlp1"
SHARED_DIR="$CARD/.umrk/mlp1/retroarch"
mkdir -p "$LEAF/defaults" "$SHARED_DIR" "$LEAF/assets/ozone" "$LEAF/autoconfig"
: >"$LEAF/autoconfig/Loong Gamepad.cfg"
cat >"$LEAF/defaults/retroarch.cfg" <<'EOF'
# Leaf's packaged defaults
input_player1_a_btn = "0"
input_player1_b_btn = "1"
input_player1_joypad_index = "0"
input_player1_analog_dpad_mode = "1"
input_enable_hotkey_btn = "5"
input_hotkey_block_delay = "0"
input_menu_toggle_btn = "nul"
aspect_ratio_index = "21"
video_scale_integer = "true"
menu_driver = "ozone"
EOF
{
    cat <<'EOF'
# The user's shared config
input_player1_a_btn = "7"
  input_player2_b_btn="3"
input_player5_a_btn = "2"
input_player1_joypad_index = "3"
input_player1_mouse_index = "2"
input_player1_device_reservation_type = "1"
input_player1_reserved_device = "Some Pad"
video_smooth = "true"
video_smooth = "false"
video_smooth_extra = "1"
fps_show = "true"
savestate_auto_save = "true"
#video_rotation = "3"
input_save_state_btn = "10"
input_load_state_btn = "11"
input_enable_hotkey_btn = "2"
input_hotkey_block_delay = "30"
input_menu_toggle_btn = "11"
audio_latency = "50"
menu_driver = "xmb"
video_shader_enable = "true"
cheevos_username = "tester"
cheevos_password = "hunter2-secret"
cheevos_token = "tok-secret"
EOF
    printf 'video_crop_overscan = "true"\r\n'
} >"$SHARED_DIR/retroarch.cfg"
cp "$LEAF/defaults/retroarch.cfg" "$TMP/leaf-defaults.orig"
cp "$SHARED_DIR/retroarch.cfg" "$TMP/leaf-shared.orig"

run "$ROM" || fail "launch with Leaf's files"
assert_unique_keys "Leaf files"

has() { grep -qxF -- "$1" "$SESSION"; }
lacks() { ! grep -q -- "$1" "$SESSION"; }

has 'input_player1_a_btn = "7"' || fail "shared bind must beat Leaf's defaults"
! has 'input_player1_a_btn = "0"' || fail "Leaf's default bind survived the shared one"
has 'input_player1_b_btn = "1"' || fail "a bind only in Leaf's defaults"
has 'input_player1_analog_dpad_mode = "1"' || fail "analog dpad mode bind"
has 'input_player2_b_btn = "3"' || fail "a bind written without spaces"
lacks 'input_player5_' || fail "player 5 is not Yabadabadoo's"
lacks 'joypad_index' || fail "joypad_index belongs to managed.cfg"
lacks 'mouse_index' || fail "device selection is per launch: mouse_index"
lacks 'reserved_device' || fail "device selection is per launch: reserved_device"
lacks 'device_reservation_type' || fail "device selection is per launch: reservation type"
has 'video_smooth = "true"' || fail "video_smooth from the shared config"
lacks 'video_smooth_extra' || fail "only the named keys come across"
has 'fps_show = "true"' || fail "fps_show from the shared config"
has 'savestate_auto_save = "true"' || fail "savestate_auto_save from the shared config"
has 'video_crop_overscan = "true"' || fail "a CRLF line"
! grep -q "$(printf '\r')" "$SESSION" || fail "carriage return in session.cfg"
lacks 'video_rotation' || fail "a commented key came across"
has 'aspect_ratio_index = "21"' || fail "Leaf's defaults must beat the pak's"
has 'video_scale_integer = "true"' || fail "video_scale_integer from Leaf's defaults"

# Hotkeys assume Menu is held as the modifier, which this wrapper does not have.
for key in input_save_state_btn input_load_state_btn input_enable_hotkey_btn \
    input_hotkey_block_delay input_menu_toggle_btn; do
    lacks "$key" || fail "hotkey key $key came across"
done
# Anything not on the allowlist stays the pak's, however the shared config is set.
has 'audio_latency = "128"' || fail "audio_latency is not Leaf's to set"
lacks 'menu_driver' || fail "menu_driver came across"
has 'video_shader_enable = "false"' || fail "video_shader_enable is not Leaf's to set"
# The managed block still wins on the keys it owns.
grep -qx 'input_player1_joypad_index = "0"' "$MANAGED" || fail "player 1 roster index"
grep -qx 'input_enable_hotkey_btn = "nul"' "$MANAGED" || fail "no hotkey modifier with Leaf files"
grep -qx 'input_menu_toggle_btn = "5"' "$MANAGED" || fail "menu on Guide with Leaf files"

# Credentials never reach any file the pak writes.
if grep -rEn 'cheevos_(username|password|token)|hunter2-secret|tok-secret' \
    "$CARD/.userdata" "$TMP/stub"; then
    fail "RetroAchievements credentials were copied"
fi
# Both Leaf files are read-only inputs.
cmp -s "$LEAF/defaults/retroarch.cfg" "$TMP/leaf-defaults.orig" || fail "Leaf's defaults modified"
cmp -s "$SHARED_DIR/retroarch.cfg" "$TMP/leaf-shared.orig" || fail "Leaf's shared config modified"

# A settings change in Leaf shows up on the next launch; nothing is cached.
sed -i.bak 's/^fps_show = "true"/fps_show = "false"/' "$SHARED_DIR/retroarch.cfg"
rm -f "$SHARED_DIR/retroarch.cfg.bak"
run "$ROM" || fail "launch after a settings change"
has 'fps_show = "false"' || fail "session.cfg is not rebuilt on every launch"
assert_unique_keys "second launch"

# UMRK_INTERNAL_DATA_PATH moves the shared config.
mkdir -p "$TMP/internal/retroarch"
printf '%s\n' 'aspect_ratio_index = "5"' >"$TMP/internal/retroarch/retroarch.cfg"
RUN_ENV="UMRK_INTERNAL_DATA_PATH=$TMP/internal"
run "$ROM" || fail "launch with UMRK_INTERNAL_DATA_PATH"
RUN_ENV=""
has 'aspect_ratio_index = "5"' || fail "UMRK_INTERNAL_DATA_PATH shared config"
! has 'input_player1_a_btn = "7"' || fail "the default shared config was read as well"

# --- Leaf's language, theme and assets ---------------------------------------
run "$ROM" || fail "launch with Leaf's assets"
grep -qx 'menu_driver = "ozone"' "$MANAGED" || fail "Ozone with Leaf's assets"
grep -qx 'ozone_menu_color_theme = "13"' "$MANAGED" || fail "Leaf's Ozone theme with Ozone"
grep -qx "joypad_autoconfig_dir = \"$LEAF/autoconfig\"" "$MANAGED" || fail "Leaf's controller profile"

language() { # <expected> <env words...>
    want="$1"
    shift
    RUN_ENV="$*"
    run "$ROM" || fail "launch with $*"
    RUN_ENV=""
    grep -qx "user_language = \"$want\"" "$MANAGED" || fail "user_language for '$*' should be $want"
}
language 12 UMRK_LANGUAGE=zh_CN
language 12 JAWAKA_LANGUAGE=zh_CN
language 12 UMRK_LANGUAGE= JAWAKA_LANGUAGE=zh_CN
language 0 UMRK_LANGUAGE=en JAWAKA_LANGUAGE=zh_CN
language 0 UMRK_LANGUAGE=en
language 0 UMRK_LANGUAGE=zh_TW
language 0 JAWAKA_LANGUAGE=de
language 0 ""

# --- bad Leaf files never stop a launch --------------------------------------
# A directory where the shared config should be.
rm -f "$ARGS"
rm "$SHARED_DIR/retroarch.cfg"
mkdir "$SHARED_DIR/retroarch.cfg"
run "$ROM" || fail "launch with a directory for the shared config"
[ -s "$ARGS" ] || fail "loader not reached with a directory for the shared config"
has 'aspect_ratio_index = "21"' || fail "Leaf's defaults still apply without a shared config"
rmdir "$SHARED_DIR/retroarch.cfg"

# An unreadable shared config (root reads anything, so only the launch is checked).
cp "$TMP/leaf-shared.orig" "$SHARED_DIR/retroarch.cfg"
chmod 0000 "$SHARED_DIR/retroarch.cfg"
rm -f "$ARGS"
run "$ROM" || fail "launch with an unreadable shared config"
[ -s "$ARGS" ] || fail "loader not reached with an unreadable shared config"
chmod 0644 "$SHARED_DIR/retroarch.cfg"

# An awk that fails: the pak's defaults alone still make a working config.
mkdir -p "$TMP/badawk"
printf '#!/bin/sh\necho "input_player1_a_btn = \\"9\\""\nexit 3\n' >"$TMP/badawk/awk"
chmod +x "$TMP/badawk/awk"
rm -f "$ARGS"
RUN_PATH="$TMP/badawk:$PATH"
run "$ROM" || fail "launch with a failing awk"
RUN_PATH=""
[ -s "$ARGS" ] || fail "loader not reached with a failing awk"
! has 'input_player1_a_btn = "9"' || fail "output of a failing awk was kept"
has 'audio_latency = "128"' || fail "pak defaults after a failing awk"

# Leaf's files removed again: back to the pak's defaults alone.
rm -f "$SHARED_DIR/retroarch.cfg" "$LEAF/defaults/retroarch.cfg"
run "$ROM" || fail "launch after Leaf's files are gone"
has 'aspect_ratio_index = "22"' || fail "pak defaults once Leaf's files are gone"
lacks 'input_player' || fail "binds left over once Leaf's files are gone"

# --- an unwritable log never stops a launch -----------------------------------
rm -f "$ARGS"
mkdir -p "$TMP/ro-logs"
chmod 0555 "$TMP/ro-logs"
LOGS="$TMP/ro-logs/sub"
run "$ROM" || fail "launch with an unwritable log dir"
LOGS=""
chmod 0755 "$TMP/ro-logs"
[ -s "$ARGS" ] || fail "loader not reached with an unwritable log dir"

echo "PASS test-run-sh"
