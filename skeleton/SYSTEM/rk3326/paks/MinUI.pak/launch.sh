#!/bin/sh
# MinUI.pak for RK3326 / Powkiddy V10 (runs on top of ArkOS, as root)

export PLATFORM="rk3326"
# Load beside the launcher: /mnt/SDCARD may not be available until mounted below.
. "$(dirname "$0")/../../bin/rk3326-init.sh"

rk_mount_sdcard

export SDCARD_PATH="$COMPAT_SDCARD_PATH"
export BIOS_PATH="$SDCARD_PATH/Bios"
export ROMS_PATH="$SDCARD_PATH/Roms"
export SAVES_PATH="$SDCARD_PATH/Saves"
export CHEATS_PATH="$SDCARD_PATH/Cheats"
export SYSTEM_PATH="$SDCARD_PATH/.system/$PLATFORM"
export CORES_PATH="$SYSTEM_PATH/cores"
export USERDATA_PATH="$SDCARD_PATH/.userdata/$PLATFORM"
export SHARED_USERDATA_PATH="$SDCARD_PATH/.userdata/shared"
export LOGS_PATH="$USERDATA_PATH/logs"
export HOOKS_PATH="$USERDATA_PATH/.hooks"
export HOME="$USERDATA_PATH"
LAUNCH_LOG="$LOGS_PATH/launch.txt"

# ArkOS's own libraries come first: they are newer than the bundled copies
# (which ArkOS's own tools such as systemctl and timedatectl cannot use).
# The bundled lib folder only fills in what ArkOS lacks (libmsettings,
# libchdr, ...).
export PATH="$SYSTEM_PATH/bin:/usr/bin:/bin:/usr/sbin:/sbin:$PATH"
export LD_LIBRARY_PATH="/usr/lib/aarch64-linux-gnu:/lib/aarch64-linux-gnu:$SYSTEM_PATH/lib"
rk_setup_runtime

#######################################

mkdir -p "$BIOS_PATH" "$ROMS_PATH" "$SAVES_PATH" "$CHEATS_PATH"
mkdir -p "$USERDATA_PATH" "$LOGS_PATH" "$HOOKS_PATH" "$SHARED_USERDATA_PATH/.minui"
echo "launch: starting $(date)" > "$LAUNCH_LOG"
export IS_NEXT="yes"
log_runtime_state

#######################################

rk_prepare_arkos
rk_refresh_frontend
rk_setup_audio
rk_link_arkos_roms

# clear shadercache unconditionally, until it properly invalidates itself
rm -rf "$SDCARD_PATH/.shadercache"

sh "$SYSTEM_PATH/bin/governor.sh" "auto"

keymon.elf > "$LOGS_PATH/keymon.txt" 2>&1 &
batmon.elf > "$LOGS_PATH/batmon.txt" 2>&1 &

#######################################

AUTO_PATH="$USERDATA_PATH/auto.sh"
if [ -f "$AUTO_PATH" ]; then
	"$AUTO_PATH"
fi

# Composable boot hooks (run after auto.sh for backward compatibility)
"$SYSTEM_PATH/bin/run_hooks.sh" boot.d

cd "$(dirname "$0")"

#######################################
# Hook system

parse_hook_cmd() {
	HOOK_CMD="$1"
	HOOK_EMU_PATH=$(echo "$HOOK_CMD" | sed "s/^'\\([^']*\\)'.*/\\1/")
	_remainder=$(echo "$HOOK_CMD" | sed "s/^'[^']*'//")
	if echo "$_remainder" | grep -q "'"; then
		HOOK_TYPE="rom"
		HOOK_ROM_PATH=$(echo "$_remainder" | sed "s/.*'\\([^']*\\)'.*/\\1/")
	else
		HOOK_TYPE="pak"
		HOOK_ROM_PATH=""
	fi
	[ -f /tmp/last.txt ] && HOOK_LAST=$(cat /tmp/last.txt) || HOOK_LAST=""
	export HOOK_CMD HOOK_EMU_PATH HOOK_TYPE HOOK_ROM_PATH HOOK_LAST
}

#######################################

rk_shutdown() {
	killall keymon.elf batmon.elf > /dev/null 2>&1 || true
	rk_restore_speaker
	rk_unlink_arkos_roms
	rk_restore_arkos
	sh "$SYSTEM_PATH/bin/governor.sh" "auto"
	sync
}

EXEC_PATH="/tmp/nextui_exec"
NEXT_PATH="/tmp/next"
rm -f /tmp/poweroff /tmp/reboot
touch "$EXEC_PATH" && sync
# rk_start_audio_monitor   # debug: live codec state to logs/audio-live.txt
while [ -f "$EXEC_PATH" ]; do
	echo "launch: starting nextui.elf $(date)" >> "$LAUNCH_LOG"
	nextui.elf > "$LOGS_PATH/nextui.txt" 2>&1
	EXIT_CODE=$?
	echo "launch: nextui.elf exited $EXIT_CODE $(date)" >> "$LAUNCH_LOG"
	# a crash (not a normal exit) returns to ArkOS instead of looping
	if [ "$EXIT_CODE" -gt 1 ] && [ ! -f "$NEXT_PATH" ]; then
		echo "launch: nextui.elf failed, returning to ArkOS" >> "$LAUNCH_LOG"
		break
	fi
	# default launched paks to performance, they can change it themselves after launch if they want
	sh "$SYSTEM_PATH/bin/governor.sh" "performance"

	if [ -f "$NEXT_PATH" ]; then
		CMD="$(cat "$NEXT_PATH")"
		parse_hook_cmd "$CMD"
		"$SYSTEM_PATH/bin/run_hooks.sh" pre-launch.d
		eval "$CMD"
		"$SYSTEM_PATH/bin/run_hooks.sh" post-launch.d
		rm -f "$NEXT_PATH"
		# reset to performance when exiting, UI will reset to auto if needed
		sh "$SYSTEM_PATH/bin/governor.sh" "performance"
	fi

	if [ -f "/tmp/poweroff" ] || [ -f "/tmp/reboot" ]; then
		break
	fi
done

rk_shutdown
# The Ports entry decides what /tmp/poweroff and /tmp/reboot mean.
exit 0
