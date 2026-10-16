#!/bin/sh
# RK3326 / ArkOS setup, sourced by MinUI.pak/launch.sh.
# Sourcing only defines functions; the launcher controls their execution order.
#
# Layout on the ArkOS card (EASYROMS partition, mounted at /roms):
#   /roms/nextui/            NextUI's own card root (Roms, Bios, Saves, .system, ...)
#   /roms/ports/NextUI.sh    the Ports entry that starts NextUI
# /roms/nextui is bind-mounted to /mnt/SDCARD, the path NextUI expects.

RK_NEXTUI_ROOT="${RK_NEXTUI_ROOT:-/roms/nextui}"

# Establish /mnt/SDCARD. The Ports entry normally did this already.
rk_mount_sdcard() {
	COMPAT_SDCARD_PATH="/mnt/SDCARD"
	if ! mountpoint -q "$COMPAT_SDCARD_PATH"; then
		mkdir -p "$COMPAT_SDCARD_PATH"
		mount --bind "$RK_NEXTUI_ROOT" "$COMPAT_SDCARD_PATH" 2>/dev/null || true
	fi
}

# Requires SYSTEM_PATH. Use ArkOS's own SDL2 (it rotates the V10's portrait
# panel to landscape); the bundled SDL2 in lib/sdl is a fallback for testing.
rk_setup_runtime() {
	export SDL_VIDEODRIVER="KMSDRM"
	export SDL_AUDIODRIVER="alsa"
	export SDL_VIDEO_EGL_DRIVER="libEGL.so"
	export SDL_JOYSTICK_DISABLE_UDEV=0
	if [ "$NEXTUI_BUNDLED_SDL" = "1" ]; then
		export LD_LIBRARY_PATH="$SYSTEM_PATH/lib/sdl:$LD_LIBRARY_PATH"
	fi
	export RK_MODEL="Powkiddy V10"
}

# Requires an initialized LAUNCH_LOG.
log_runtime_state() {
	echo "launch: runtime state $(date)" >> "$LAUNCH_LOG"
	echo "launch: user=$(id -u) LD_LIBRARY_PATH=$LD_LIBRARY_PATH" >> "$LAUNCH_LOG"
	echo "launch: SDL_VIDEODRIVER=$SDL_VIDEODRIVER bundled_sdl=${NEXTUI_BUNDLED_SDL:-0}" >> "$LAUNCH_LOG"
	ldd "$SYSTEM_PATH/bin/nextui.elf" >> "$LAUNCH_LOG" 2>&1 || true
}

# Hand control over from ArkOS services while NextUI runs.
# ogage (ArkOS's global hotkey daemon) would change volume/brightness a
# second time on every key press, so it is paused and restored on exit.
rk_prepare_arkos() {
	if systemctl is-active --quiet ogage 2>/dev/null; then
		systemctl stop ogage 2>/dev/null && touch /tmp/nextui-ogage-stopped
	fi
}

rk_restore_arkos() {
	if [ -f /tmp/nextui-ogage-stopped ]; then
		systemctl start ogage 2>/dev/null || true
		rm -f /tmp/nextui-ogage-stopped
	fi
}

# Show ROMs that already live in ArkOS's folders inside NextUI's systems, by
# bind-mounting each ArkOS folder over NextUI's matching Roms folder.
# Turn off by creating $USERDATA_PATH/no-arkos-roms.
rk_link_arkos_roms() {
	[ -f "$USERDATA_PATH/no-arkos-roms" ] && return 0
	while IFS='|' read -r ark next; do
		[ -n "$ark" ] || continue
		src="/roms/$ark"
		dst="$ROMS_PATH/$next"
		[ -d "$src" ] || continue
		# only folders that hold at least one file
		[ -n "$(find "$src" -maxdepth 1 -type f ! -name '.*' ! -name '*.txt' | head -1)" ] || continue
		mkdir -p "$dst"
		mountpoint -q "$dst" && continue
		mount --bind "$src" "$dst" 2>/dev/null \
			&& echo "$dst" >> /tmp/nextui-rom-binds \
			&& echo "launch: showing $src as $next" >> "$LAUNCH_LOG"
	done <<EOF
gb|Game Boy (GB)
gbc|Game Boy Color (GBC)
gba|Game Boy Advance (GBA)
nes|Nintendo Entertainment System (FC)
snes|Super Nintendo Entertainment System (SFC)
genesis|Sega Genesis (MD)
megadrive|Sega Genesis (MD)
psx|Sony PlayStation (PS)
EOF
}

rk_unlink_arkos_roms() {
	[ -f /tmp/nextui-rom-binds ] || return 0
	while read -r dst; do
		umount "$dst" 2>/dev/null || true
	done < /tmp/nextui-rom-binds
	rm -f /tmp/nextui-rom-binds
}
