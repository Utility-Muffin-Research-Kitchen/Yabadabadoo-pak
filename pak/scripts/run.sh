#!/bin/sh
# Yabadabadoo launch wrapper for Leaf on MLP1.
#
# This is the `type: "path"` core target declared in pak.json
# (`scripts/run.sh`). Leaf/Jawaka execs it with one absolute content path:
#
#     run.sh /path/to/game.chd
#
# Yabadabadoo's SH-2 recompiler only exists for 32-bit ARM, so the core runs in
# the pak's own 32-bit RetroArch. The MLP1 rootfs has no 32-bit userland: the
# dynamic loader and every library RetroArch and the core load ship in
# runtime/lib, and nothing from the 64-bit system is mixed in.
#
# Paths come from the public runtime contract (docs/runtime-paths.md); the
# fallbacks below are only for a direct, manual launch outside the launcher.
set -u

ROOT_DIR="$(CDPATH= cd -- "$(dirname -- "$0")/.." && pwd)"

# --- runtime environment -----------------------------------------------------
# Source the launcher's exported environment when it is present, without
# overwriting per-launch bindings Jawaka already made for the selected source.
if [ -n "${UMRK_ENV_FILE:-}" ] && [ -f "$UMRK_ENV_FILE" ]; then
    . "$UMRK_ENV_FILE"
elif [ -n "${SDCARD_PATH:-}" ] && [ -n "${PLATFORM:-}" ] &&
     [ -f "$SDCARD_PATH/.system/leaf/platforms/$PLATFORM/launcher/env.sh" ]; then
    . "$SDCARD_PATH/.system/leaf/platforms/$PLATFORM/launcher/env.sh"
fi

: "${PLATFORM:=mlp1}"
: "${SDCARD_PATH:=/mnt/sdcard}"
: "${USERDATA_PATH:=$SDCARD_PATH/.userdata/$PLATFORM}"
: "${LOGS_PATH:=$USERDATA_PATH/logs}"
: "${SAVES_PATH:=$SDCARD_PATH/Saves}"
: "${STATES_PATH:=$SDCARD_PATH/States}"
: "${BIOS_PATH:=$SDCARD_PATH/BIOS}"
: "${UMRK_PLATFORM_PATH:=$SDCARD_PATH/.system/leaf/platforms/$PLATFORM}"

STATE_ROOT="$USERDATA_PATH/Yabadabadoo"
USER_CFG="$STATE_ROOT/retroarch.cfg"
MANAGED_CFG="$STATE_ROOT/managed.cfg"
LOADER="$ROOT_DIR/runtime/lib/ld-linux-armhf.so.3"
RETROARCH="$ROOT_DIR/bin/retroarch"
CORE="$ROOT_DIR/cores/yabadabadoo_libretro.so"

usage() {
    echo "usage: $0 /path/to/game" >&2
}

if [ "$#" -ne 1 ]; then
    usage
    exit 2
fi

ROM_PATH="$1"
case "$ROM_PATH" in
    /*) ;;
    *) ROM_PATH="$PWD/$ROM_PATH" ;;
esac
if [ ! -f "$ROM_PATH" ]; then
    echo "yabadabadoo: game not found: $ROM_PATH" >&2
    exit 1
fi
for file in "$LOADER" "$RETROARCH" "$CORE"; do
    if [ ! -f "$file" ]; then
        echo "yabadabadoo: missing $file; reinstall the pak" >&2
        exit 1
    fi
done

# --- durable state -----------------------------------------------------------
# RetroArch's own settings, core options and remaps live under the user-data
# tree, never in the pak, which Pak Rat replaces on every update. The user's
# retroarch.cfg starts as a copy of the defaults and is theirs from then on;
# managed.cfg is rewritten on every launch and wins over it.
mkdir -p "$STATE_ROOT/config" "$STATE_ROOT/home" "$STATE_ROOT/cache" \
    "$STATE_ROOT/screenshots" 2>/dev/null
if [ ! -f "$USER_CFG" ]; then
    cp "$ROOT_DIR/defaults/retroarch.cfg" "$USER_CFG" 2>/dev/null
fi

# A failed log must never stop a launch (the card can be read-only).
mkdir -p "$LOGS_PATH" 2>/dev/null
LOG_FILE="$LOGS_PATH/yabadabadoo.log"
# A subshell: a failed redirection on the `:` special builtin can end a POSIX
# shell outright.
if ! ( : >"$LOG_FILE" ) 2>/dev/null; then
    LOG_FILE=/dev/null
fi
if ! ( : >"$MANAGED_CFG" ) 2>/dev/null; then
    MANAGED_CFG="${TMPDIR:-/tmp}/yabadabadoo-managed.cfg"
fi

# Leaf's menu assets and its controller profile when the release carries them;
# otherwise RetroArch's built-in RGUI menu and the profile shipped here.
if [ -d "$UMRK_PLATFORM_PATH/assets/ozone" ]; then
    MENU_DRIVER=ozone
    ASSETS_DIR="$UMRK_PLATFORM_PATH/assets"
else
    MENU_DRIVER=rgui
    ASSETS_DIR="$STATE_ROOT/assets"
fi
if [ -f "$UMRK_PLATFORM_PATH/autoconfig/Loong Gamepad.cfg" ]; then
    AUTOCONFIG_DIR="$UMRK_PLATFORM_PATH/autoconfig"
else
    AUTOCONFIG_DIR="$ROOT_DIR/defaults/autoconfig"
fi

# Saves and states follow the game's card (Jawaka binds SAVES_PATH and
# STATES_PATH per launch) and land in a Yabadabadoo folder there, apart from
# YabaSanshiro's. The core writes the Saturn backup RAM (in-game saves) itself,
# as <game>.srm in that folder. The BIOS is read from BIOS/SATURN, where Leaf
# keeps Saturn BIOS files.
#
# Players follow the controller roster Jawaka publishes in
# SDL_JOYSTICK_DEVICE, as in Leaf's own RetroArch: a connected external
# controller is player 1 and the built-in pad comes after it. Leaf forwards a
# Menu tap as the built-in pad's Guide button (index 5 in the controller
# profile), and an external controller's Guide reaches RetroArch directly.
# RetroArch reads hotkeys from player 1 only, so player 1's Guide opens its
# menu; there is no hotkey modifier. Holding Menu quits through Leaf.
cat >"$MANAGED_CFG" <<EOF
system_directory = "$BIOS_PATH/SATURN"
savefile_directory = "$SAVES_PATH"
savestate_directory = "$STATES_PATH"
sort_savefiles_enable = "true"
sort_savestates_enable = "true"
sort_savefiles_by_content_enable = "false"
sort_savestates_by_content_enable = "false"
rgui_config_directory = "$STATE_ROOT/config"
cache_directory = "$STATE_ROOT/cache"
screenshot_directory = "$STATE_ROOT/screenshots"
assets_directory = "$ASSETS_DIR"
joypad_autoconfig_dir = "$AUTOCONFIG_DIR"
menu_driver = "$MENU_DRIVER"
video_driver = "gl"
video_context_driver = "sdl_gl"
video_fullscreen = "true"
video_threaded = "false"
video_refresh_rate = "60.000000"
audio_driver = "pulse"
audio_device = ""
input_driver = "sdl2"
input_joypad_driver = "sdl2"
input_autodetect_enable = "true"
input_player1_joypad_index = "0"
input_player2_joypad_index = "1"
input_player3_joypad_index = "2"
input_player4_joypad_index = "3"
input_menu_toggle_btn = "5"
input_enable_hotkey_btn = "nul"
input_menu_toggle_gamepad_combo = "0"
pause_nonactive = "false"
config_save_on_exit = "false"
history_list_enable = "false"
cheevos_enable = "false"
network_cmd_enable = "false"
menu_show_online_updater = "false"
menu_show_core_updater = "false"
EOF

# --- presentation and audio --------------------------------------------------
# Weston owns the panel transform on MLP1, so RetroArch runs a plain fullscreen
# Wayland window. The 64-bit library path and preloads Leaf exports cannot be
# loaded by a 32-bit process, so they are dropped rather than inherited.
unset LD_LIBRARY_PATH LD_PRELOAD
export SDL_VIDEODRIVER=wayland
export XDG_RUNTIME_DIR="${XDG_RUNTIME_DIR:-/run}"
export SDL_VIDEO_EGL_DRIVER=libEGL.so.1
export SDL_VIDEO_GL_DRIVER=libGLESv2.so.2
export SDL_JOYSTICK_DISABLE_UDEV=1
export PULSE_SERVER="${PULSE_SERVER:-unix:/tmp/pulse-socket}"
export PULSE_CLIENTCONFIG="$ROOT_DIR/defaults/pulse-client.conf"
export HOME="$STATE_ROOT/home"

exec "$LOADER" --library-path "$ROOT_DIR/runtime/lib" --argv0 retroarch \
    "$RETROARCH" --verbose -L "$CORE" \
    --config "$USER_CFG" --appendconfig "$MANAGED_CFG" \
    "$ROM_PATH" >"$LOG_FILE" 2>&1
