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
	# Without ArkOS's per-user ALSA setup, "default" plays silence on the
	# rk817; the plug device on card 0 is what the sound test proved works.
	export NEXTUI_ALSA_DEVICE="${NEXTUI_ALSA_DEVICE:-plughw:0,0}"
	export AUDIODEV="$NEXTUI_ALSA_DEVICE"
	export SDL_VIDEO_EGL_DRIVER="libEGL.so"
	# NextUI OS has no udev daemon: SDL must scan /dev/input itself
	export SDL_JOYSTICK_DISABLE_UDEV="${SDL_JOYSTICK_DISABLE_UDEV:-0}"
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
		[ -n "$(find "$src" -maxdepth 1 -type f ! -name '.*' ! -name '*.txt' -print -quit)" ] || continue
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

# Requires LOGS_PATH. Make sure the rk817 codec routes to the speaker and
# record the audio state. (No .asoundrc is copied into NextUI's HOME: NextUI
# reads a "type hw" entry there as a USB DAC and would move volume control.)
# Turn the speaker path back on if something left it OFF (ArkOS switches it
# between SPK and HP itself; OFF means silence everywhere, ArkOS included).
rk_restore_speaker() {
	path=$(amixer -c 0 sget 'Playback Path' 2>/dev/null | sed -n "s/.*Item0: '\(.*\)'.*/\1/p")
	if [ "$path" = "OFF" ] || [ -z "$path" ]; then
		amixer -q -c 0 sset 'Playback Path' SPK 2>/dev/null || true
	fi
}

rk_setup_audio() {
	rk_restore_speaker

	{
		echo "== audio $(date)"
		echo "user=$(id -u) HOME=$HOME"
		echo "-- /etc/asound.conf"; cat /etc/asound.conf 2>&1
		echo "-- \$HOME/.asoundrc"; cat "$HOME/.asoundrc" 2>&1
		echo "-- aplay -l"; aplay -l 2>&1
		echo "-- aplay -L"; aplay -L 2>&1 | head -40
		echo "-- amixer"; amixer -c 0 2>&1
		echo "-- who holds the sound device"; fuser /dev/snd/* 2>&1
	} > "$LOGS_PATH/audio.txt" 2>&1
}

# Requires LOGS_PATH. While NextUI runs, record the codec's live state every
# 5 s (mixer + what the PCM stream is actually doing) to audio-live.txt.
rk_start_audio_monitor() {
	(
		out="$LOGS_PATH/audio-live.txt"
		: > "$out"
		while [ -f /tmp/nextui_exec ]; do
			{
				echo "== $(date +%T)"
				amixer -c 0 sget Playback 2>&1 | grep -E 'Front Left|Mono'
				amixer -c 0 sget 'Playback Path' 2>&1 | grep Item0
				for f in /proc/asound/card0/pcm0p/sub0/status /proc/asound/card0/pcm0p/sub0/hw_params; do
					echo "-- $f"; cat "$f" 2>&1
				done
			} >> "$out"
			# keep the file small
			if [ "$(wc -l < "$out")" -gt 600 ]; then
				tail -n 300 "$out" > "$out.tmp" && mv "$out.tmp" "$out"
			fi
			sleep 5
		done
	) > /dev/null 2>&1 &
}

# Keep the installed boot front end (boot mode only) in step with this
# NextUI version, so updating the card also updates it.
rk_refresh_frontend() {
	installed=/usr/local/bin/nextui-frontend.sh
	[ -f "$installed" ] || return 0
	if ! cmp -s "$SYSTEM_PATH/bin/nextui-frontend.sh" "$installed"; then
		install -m 755 "$SYSTEM_PATH/bin/nextui-frontend.sh" "$installed" 2>/dev/null \
			&& echo "launch: updated $installed" >> "$LAUNCH_LOG"
	fi
}
