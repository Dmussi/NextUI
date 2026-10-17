#!/bin/bash
# Make the Powkiddy V10 start NextUI instead of EmulationStation at power-on.
# Hold L1 while turning the V10 on to get ArkOS (EmulationStation) instead.
# Undo with "NextUI - Start at Boot OFF".

if [ "$(id -u)" != "0" ]; then
	exec sudo -E bash "$0" "$@"
fi

TTY=/dev/tty1
say() { printf '\033[2J\033[H%s\n' "$*" > "$TTY" 2>/dev/null; }

NEXTUI_ROOT=/roms/nextui
SRC="$NEXTUI_ROOT/.system/rk3326/bin/nextui-frontend.sh"
DROPIN=/etc/systemd/system/emulationstation.service.d

if [ ! -f "$SRC" ] || [ ! -f /roms/ports/NextUI.sh ]; then
	say "NextUI is not fully installed (missing nextui folder or ports/NextUI.sh)."
	sleep 6; exit 1
fi

install -m 755 "$SRC" /usr/local/bin/nextui-frontend.sh
mkdir -p "$DROPIN"
cat > "$DROPIN/nextui.conf" <<'CONF'
# Added by NextUI: start NextUI at boot (falls back to EmulationStation).
[Service]
ExecStart=
ExecStart=/usr/local/bin/nextui-frontend.sh
CONF
systemctl daemon-reload
mkdir -p "$NEXTUI_ROOT/.userdata/rk3326"
touch "$NEXTUI_ROOT/.userdata/rk3326/boot-nextui"
sync

say "NextUI will now start when the V10 turns on.

- Hold L1 while turning on to get ArkOS instead.
- In NextUI, Tools > ArkOS goes back to ArkOS.
- Run 'NextUI - Start at Boot OFF' from Ports to undo."
sleep 10
printf '\033c' > "$TTY" 2>/dev/null
