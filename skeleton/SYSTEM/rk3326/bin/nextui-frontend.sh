#!/bin/bash
# NextUI boot front end for the Powkiddy V10 on ArkOS.
#
# Installed by "NextUI - Start at Boot ON" as /usr/local/bin/nextui-frontend.sh
# and started by ArkOS's emulationstation.service (as user ark) in place of
# EmulationStation. Runs NextUI, then falls back to EmulationStation when:
#   - boot mode is off (flag file missing) or NextUI is not installed
#   - L1 is held while the V10 starts
#   - the "ArkOS" tool in NextUI was used
#   - NextUI exits without asking to power off (e.g. a crash)

NEXTUI_ROOT=/roms/nextui
FLAG="$NEXTUI_ROOT/.userdata/rk3326/boot-nextui"
PORT=/roms/ports/NextUI.sh
ES=/usr/bin/emulationstation/emulationstation.sh
LOG=/tmp/nextui-frontend.log

echo "frontend: start $(date)" > "$LOG"

# the EASYROMS partition can show up a moment after the service starts
for _ in $(seq 20); do
	[ -d "$NEXTUI_ROOT" ] && break
	sleep 0.5
done

# true when the L1 shoulder button is held right now
l1_held() {
	python3 - <<'PY' 2>/dev/null
import fcntl, glob, os, sys
L1 = 310
EVIOCGKEY = 0x80000000 | (96 << 16) | (ord('E') << 8) | 0x18
for dev in glob.glob('/sys/class/input/event*'):
    try:
        name = open(dev + '/device/name').read()
    except OSError:
        continue
    if 'Gamepad' not in name and 'joypad' not in name.lower():
        continue
    fd = os.open('/dev/input/' + os.path.basename(dev), os.O_RDONLY)
    state = bytearray(96)
    fcntl.ioctl(fd, EVIOCGKEY, state)
    os.close(fd)
    sys.exit(0 if state[L1 // 8] & (1 << (L1 % 8)) else 1)
sys.exit(1)
PY
}

if [ -f "$FLAG" ] && [ -f "$PORT" ]; then
	if l1_held; then
		echo "frontend: L1 held, starting EmulationStation" >> "$LOG"
	else
		echo "frontend: starting NextUI" >> "$LOG"
		NEXTUI_BOOT=1 bash "$PORT"
		echo "frontend: NextUI returned $?" >> "$LOG"
		# powering off / rebooting: don't flash EmulationStation on the way down
		if [ -f /run/nextui-shutting-down ]; then
			sleep 60
			exit 0
		fi
	fi
else
	echo "frontend: boot mode off, starting EmulationStation" >> "$LOG"
fi

exec "$ES"
