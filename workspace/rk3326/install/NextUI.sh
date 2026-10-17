#!/bin/bash
# NextUI for the Powkiddy V10 - ArkOS Ports entry.
# Lives in /roms/ports/; NextUI itself lives in /roms/nextui/.
#
# Started from Ports, Power Off inside NextUI returns to ArkOS
# (EmulationStation); create /roms/nextui/.userdata/rk3326/real-poweroff to
# make it really power off. Started at boot (nextui-frontend.sh sets
# NEXTUI_BOOT=1) it always powers off.

NEXTUI_ROOT="/roms/nextui"
LAUNCHER="$NEXTUI_ROOT/.system/rk3326/paks/MinUI.pak/launch.sh"
TTY=/dev/tty1

# ES runs ports as the "ark" user; NextUI needs root for mounts and services
if [ "$(id -u)" != "0" ]; then
	exec sudo -E bash "$0" "$@"
fi

say() { printf '%s\n' "$*" > "$TTY" 2>/dev/null; }
printf '\033c' > "$TTY" 2>/dev/null

if [ ! -f "$LAUNCHER" ]; then
	say "NextUI is not installed: $LAUNCHER is missing."
	say "Copy the 'nextui' folder to the root of the EASYROMS partition."
	sleep 6
	exit 1
fi

mkdir -p "$NEXTUI_ROOT/.userdata/rk3326/logs"
PORT_LOG="$NEXTUI_ROOT/.userdata/rk3326/logs/port.txt"
echo "port: start $(date)" > "$PORT_LOG"

mkdir -p /mnt/SDCARD
if ! mountpoint -q /mnt/SDCARD; then
	mount --bind "$NEXTUI_ROOT" /mnt/SDCARD >> "$PORT_LOG" 2>&1
fi

rm -f /tmp/poweroff /tmp/reboot
sh "$LAUNCHER" >> "$PORT_LOG" 2>&1
echo "port: launcher exited $? $(date)" >> "$PORT_LOG"

umount /mnt/SDCARD >> "$PORT_LOG" 2>&1 || true
# never hand ArkOS back a switched-off speaker
if amixer -c 0 sget 'Playback Path' 2>/dev/null | grep -q "Item0: 'OFF'"; then
	amixer -q -c 0 sset 'Playback Path' SPK
fi
printf '\033c' > "$TTY" 2>/dev/null

# In boot mode (started by nextui-frontend.sh) Power Off really powers off;
# from Ports it returns to ArkOS unless the real-poweroff file exists.
if [ -f /tmp/reboot ]; then
	rm -f /tmp/reboot
	touch /run/nextui-shutting-down
	sync; systemctl reboot
elif [ -f /tmp/poweroff ]; then
	rm -f /tmp/poweroff
	if [ "$NEXTUI_BOOT" = "1" ] || [ -f "$NEXTUI_ROOT/.userdata/rk3326/real-poweroff" ]; then
		touch /run/nextui-shutting-down
		sync; systemctl poweroff
	fi
fi
exit 0
