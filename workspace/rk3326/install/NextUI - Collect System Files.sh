#!/bin/bash
# Copy what a standalone (BaseOS-style) NextUI system for the Powkiddy V10
# needs from dArkOS: bootloader, kernel + device tree, kernel modules,
# firmware, graphics/audio/SDL libraries and a hardware report.
# Read-only for dArkOS: everything is written to EASYROMS as
#   /roms/nextui-collect.tar.gz
# (the working folder /roms/nextui-collect is removed at the end).

if [ "$(id -u)" != "0" ]; then
	exec sudo -E bash "$0" "$@"
fi

TTY=/dev/tty1
say() { printf '\033[2J\033[H%s\n' "$*" > "$TTY" 2>/dev/null; }

OUT=/roms/nextui-collect
TAR=/roms/nextui-collect.tar.gz
rm -rf "$OUT" "$TAR"
mkdir -p "$OUT"/{info,boot,bootloader,libs,etc}
LOG="$OUT/info/collect.log"
exec 2>>"$LOG"
step() { say "Collecting system files for NextUI...

$1

Please wait, do not turn the V10 off."; echo "== $1" >> "$LOG"; }

#######################################
step "1/7 hardware report"
I="$OUT/info"
{
	echo "== uname"; uname -a
	echo "== cmdline"; cat /proc/cmdline
	echo "== model"; tr -d '\0' < /proc/device-tree/model; echo
	echo "== compatible"; tr '\0' '\n' < /proc/device-tree/compatible
	echo "== os"; cat /etc/os-release; cat /etc/issue 2>/dev/null
	echo "== cpuinfo"; cat /proc/cpuinfo
	echo "== meminfo"; head -5 /proc/meminfo
} > "$I/system.txt" 2>&1
lsmod > "$I/lsmod.txt" 2>&1
dmesg > "$I/dmesg.txt" 2>&1
lsblk -o NAME,SIZE,TYPE,FSTYPE,LABEL,PARTLABEL,MOUNTPOINT > "$I/lsblk.txt" 2>&1
blkid > "$I/blkid.txt" 2>&1
mount > "$I/mount.txt" 2>&1
cat /etc/fstab > "$I/fstab.txt" 2>&1
ls -la /dev/input /dev/dri /dev/snd /dev/fb* /dev/mali* > "$I/dev.txt" 2>&1
cat /proc/bus/input/devices > "$I/input-devices.txt" 2>&1
{ aplay -l; amixer -c 0; cat /proc/asound/cards; } > "$I/audio.txt" 2>&1
alsactl store -f "$I/asound.state" 2>/dev/null
ls -laR /sys/class/drm/ > "$I/drm.txt" 2>&1
for c in /sys/class/drm/card*-*; do
	[ -f "$c/modes" ] && { echo "$c: $(cat "$c/status") $(cat "$c/modes" | tr '\n' ' ')"; }
done >> "$I/drm-modes.txt" 2>&1
ls -la /sys/class/power_supply/ /sys/class/backlight/ /sys/class/devfreq/ /sys/class/net/ /sys/class/leds/ > "$I/sysfs.txt" 2>&1
ip link > "$I/net.txt" 2>&1
systemctl list-units --no-pager > "$I/systemd-units.txt" 2>&1
systemctl list-unit-files --no-pager > "$I/systemd-unit-files.txt" 2>&1
ps aux > "$I/ps.txt" 2>&1
dpkg -l > "$I/dpkg.txt" 2>&1

#######################################
step "2/7 boot partition (kernel, device tree)"
BOOTDIR=$(findmnt -n -o TARGET -S LABEL=BOOT 2>/dev/null)
[ -z "$BOOTDIR" ] && [ -d /boot ] && BOOTDIR=/boot
echo "boot dir: $BOOTDIR" >> "$LOG"
[ -n "$BOOTDIR" ] && cp -a "$BOOTDIR/." "$OUT/boot/"

#######################################
step "3/7 bootloader"
ROOTSRC=$(findmnt -n -o SOURCE /roms 2>/dev/null)
DISK=/dev/$(lsblk -no PKNAME "$ROOTSRC" 2>/dev/null | head -1)
echo "disk: $DISK (from $ROOTSRC)" >> "$LOG"
if [ -b "$DISK" ]; then
	sfdisk -d "$DISK" > "$OUT/bootloader/partitions.sfdisk" 2>&1
	fdisk -l "$DISK" > "$OUT/bootloader/fdisk.txt" 2>&1
	# everything before the first partition: idbloader, u-boot, trust
	FIRST=$(sfdisk -d "$DISK" 2>/dev/null | sed -n 's/.*start= *\([0-9]*\).*/\1/p' | sort -n | head -1)
	[ -z "$FIRST" ] && FIRST=32768
	[ "$FIRST" -gt 131072 ] && FIRST=131072   # never more than 64 MB
	dd if="$DISK" of="$OUT/bootloader/head.img" bs=512 count="$FIRST" status=none
fi

#######################################
step "4/7 kernel modules"
KV=$(uname -r)
tar -czf "$OUT/modules-$KV.tar.gz" -C / "lib/modules/$KV" 2>>"$LOG"
cp -a /etc/modules /etc/modules-load.d /etc/modprobe.d "$OUT/etc/" 2>/dev/null

#######################################
step "5/7 firmware (Wi-Fi / Bluetooth)"
FW=/lib/firmware
[ -d /usr/lib/firmware ] && FW=/usr/lib/firmware
FWSIZE=$(du -sm "$FW" 2>/dev/null | cut -f1)
echo "firmware size: ${FWSIZE}MB" >> "$LOG"
if [ -n "$FWSIZE" ] && [ "$FWSIZE" -le 150 ]; then
	tar -czf "$OUT/firmware.tar.gz" -C "$(dirname "$FW")" "$(basename "$FW")" 2>>"$LOG"
else
	# only what the loaded drivers ask for
	for m in $(lsmod | awk 'NR>1{print $1}'); do modinfo -F firmware "$m" 2>/dev/null; done |
		sort -u | while read -r f; do ls "$FW"/$f 2>/dev/null; done > "$I/firmware-used.txt"
	tar -czf "$OUT/firmware.tar.gz" -T "$I/firmware-used.txt" 2>>"$LOG"
	ls -laR "$FW" > "$I/firmware-list.txt" 2>&1
fi

#######################################
step "6/7 libraries (graphics, SDL, audio, C library)"
# every shared library NextUI, its tools and its cores actually load
: > "$I/libs-needed.txt"
find /roms/nextui/.system /roms/nextui/Tools -type f \( -name '*.elf' -o -name '*.so' -o -name '*.so.*' \) 2>/dev/null |
while read -r f; do
	LD_LIBRARY_PATH="/usr/lib/aarch64-linux-gnu:/lib/aarch64-linux-gnu:/roms/nextui/.system/rk3326/lib" ldd "$f" 2>/dev/null
done | awk '/=> \//{print $3} /^\t\/lib/{print $1}' | sort -u > "$I/libs-needed.txt"
# graphics stack and everything SDL2 may dlopen at runtime
ls /usr/lib/aarch64-linux-gnu/lib{mali,EGL,GLES,gbm,drm,SDL2,asound,udev,evdev,pulse,wayland,mpg123,freetype,png,jpeg,webp,tiff,harfbuzz}* 2>/dev/null >> "$I/libs-needed.txt"
ls /usr/lib/aarch64-linux-gnu/ld-linux* /lib/ld-linux* 2>/dev/null >> "$I/libs-needed.txt"
sort -u -o "$I/libs-needed.txt" "$I/libs-needed.txt"
# keep symlinks and their targets
while read -r l; do
	[ -e "$l" ] || continue
	echo "$l"; readlink -f "$l"
done < "$I/libs-needed.txt" | sort -u > "$I/libs-files.txt"
tar -czf "$OUT/libs.tar.gz" -T "$I/libs-files.txt" 2>>"$LOG"
ls -la /usr/lib/aarch64-linux-gnu/ > "$I/libdir-list.txt" 2>&1
cp -a /usr/share/alsa "$OUT/etc/alsa-share" 2>/dev/null
cp -a /etc/asound.conf /etc/udev "$OUT/etc/" 2>/dev/null
dpkg -S /usr/lib/aarch64-linux-gnu/libmali* /usr/lib/aarch64-linux-gnu/libSDL2-2.0.so.0 > "$I/lib-packages.txt" 2>&1

#######################################
step "7/7 packing into nextui-collect.tar.gz"
tar -czf "$TAR" -C /roms nextui-collect 2>>"$LOG"
SIZE=$(du -m "$TAR" | cut -f1)
rm -rf "$OUT"
sync

say "Done.

Saved to EASYROMS as nextui-collect.tar.gz (${SIZE} MB).

Power off, put the card in your computer and send that file.
Nothing in ArkOS was changed."
sleep 12
printf '\033c' > "$TTY" 2>/dev/null
exit 0
