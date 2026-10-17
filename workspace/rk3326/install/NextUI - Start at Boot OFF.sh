#!/bin/bash
# Go back to starting EmulationStation at power-on.

if [ "$(id -u)" != "0" ]; then
	exec sudo -E bash "$0" "$@"
fi

TTY=/dev/tty1
say() { printf '\033[2J\033[H%s\n' "$*" > "$TTY" 2>/dev/null; }

rm -f /roms/nextui/.userdata/rk3326/boot-nextui
rm -f /etc/systemd/system/emulationstation.service.d/nextui.conf
rmdir /etc/systemd/system/emulationstation.service.d 2>/dev/null
systemctl daemon-reload
sync

say "The V10 will start ArkOS (EmulationStation) at power-on again.
NextUI is still available from Ports."
sleep 6
printf '\033c' > "$TTY" 2>/dev/null
