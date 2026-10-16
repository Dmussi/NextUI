#!/bin/bash
# NextUI V10 sound test - ArkOS Ports entry.
# Plays numbered tones through different audio paths. Count the beeps you
# hear in each test; results are also written to
# /roms/nextui/.userdata/rk3326/logs/soundtest.txt

if [ "$(id -u)" != "0" ]; then
	exec sudo -E bash "$0" "$@"
fi

TTY=/dev/tty1
LOG_DIR=/roms/nextui/.userdata/rk3326/logs
mkdir -p "$LOG_DIR"
LOG="$LOG_DIR/soundtest.txt"
WAV=/tmp/nextui-beep.wav

say() { printf '\033[2J\033[H%s\n' "$*" > "$TTY" 2>/dev/null; echo "$*" >> "$LOG"; }

echo "== sound test $(date)" > "$LOG"
amixer -c 0 sget Playback >> "$LOG" 2>&1
amixer -c 0 sget 'Playback Path' >> "$LOG" 2>&1
OLD_VOL=$(amixer -c 0 sget Playback | sed -n 's/.*Front Left: \([0-9]*\).*/\1/p')

# 0.4 s 660 Hz tone, 48 kHz stereo 16-bit
python3 - "$WAV" <<'PY'
import math, struct, sys, wave
rate = 48000
with wave.open(sys.argv[1], 'wb') as w:
    w.setnchannels(2); w.setsampwidth(2); w.setframerate(rate)
    frames = bytearray()
    for i in range(int(rate * 0.4)):
        v = int(12000 * math.sin(2 * math.pi * 660 * i / rate))
        frames += struct.pack('<hh', v, v)
    w.writeframes(bytes(frames))
PY

beeps() { # count device user
	for _ in $(seq "$1"); do
		if [ "$3" = "ark" ]; then
			sudo -u ark aplay -q -D "$2" "$WAV" >> "$LOG" 2>&1
		else
			aplay -q -D "$2" "$WAV" >> "$LOG" 2>&1
		fi
		echo "   aplay $2 as $3: exit $?" >> "$LOG"
		sleep 0.3
	done
	sleep 1.5
}

amixer -q -c 0 sset 'Playback Path' SPK
amixer -q -c 0 sset Playback 183   # ArkOS default level

say "Sound test 1 of 4: 1 beep"
sleep 1; beeps 1 default root

say "Sound test 2 of 4: 2 beeps"
sleep 1; beeps 2 plughw:0,0 root

say "Sound test 3 of 4: 3 beeps"
sleep 1; beeps 3 default ark

amixer -q -c 0 sset Playback 245   # the value NextUI build 2 left behind
say "Sound test 4 of 4: 4 beeps"
sleep 1; beeps 4 default root

amixer -q -c 0 sset Playback "${OLD_VOL:-183}"
amixer -c 0 sget Playback >> "$LOG" 2>&1
say "Done. Tell Claude how many beeps you heard in tests 1, 2, 3 and 4."
sleep 6
printf '\033c' > "$TTY" 2>/dev/null
rm -f "$WAV"
