#!/bin/bash
# Build "NextUI OS" for the Powkiddy V10: a flashable SD card image that boots
# straight into NextUI, without ArkOS (BaseOS-style: the bootloader, kernel,
# device tree and GPU driver come unchanged from dArkOS; everything else is a
# small BusyBox system).
#
# usage: build-os.sh <nextui-collect.tar.gz> <staged-release-dir> <output-dir>
#   nextui-collect.tar.gz  made on the V10 by "NextUI - Collect System Files"
#   staged-release-dir     the folder package.sh stages (holds nextui/)
#
# Needs on the build machine: zig toolchain (build-toolchain.sh), git,
# mksquashfs, mkfs.vfat, mtools, sfdisk, mkimage, cpio, unzip/zip,
# qemu-aarch64-static (only to list BusyBox's applets).

set -euo pipefail

COLLECT="$(realpath "${1:?nextui-collect.tar.gz}")"
STAGED="$(realpath "${2:?staged release dir}")"
OUT="$(realpath -m "${3:?output dir}")"
HERE="$(cd "$(dirname "$0")" && pwd)"
REPO="$(cd "$HERE/../../.." && pwd)"
WORK="$OUT/os-work"
ZIG="$(python3 -c 'import ziglang,os;print(os.path.join(os.path.dirname(ziglang.__file__),"zig"))')"
HASH="$(git -C "$REPO" rev-parse --short HEAD)"
VERSION="$(date +%Y%m%d)-$HASH"
NAME="NextUI-OS-V10-$VERSION"
BOOT_MB=256
BUSYBOX_TAG=1_36_1

rm -rf "$WORK"
mkdir -p "$WORK" "$OUT"

#######################################
echo "== collected dArkOS files"
C="$WORK/collect"
mkdir -p "$C"
tar -xzf "$COLLECT" -C "$C"
C="$C/nextui-collect"
mkdir -p "$WORK/libs" "$WORK/modules"
tar -xzf "$C/libs.tar.gz" -C "$WORK/libs"
tar -xzf "$C"/modules-*.tar.gz -C "$WORK/modules"
KVER=$(ls "$WORK/modules/lib/modules")

#######################################
echo "== static tools (busybox, amixer)"
CC_MUSL=("$ZIG" cc -target aarch64-linux-musl -mcpu=cortex_a35)
TOOLS="$OUT/os-tools"
mkdir -p "$TOOLS/bin"
cat > "$TOOLS/bin/aarch64-linux-musl-gcc" <<EOF
#!/bin/bash
args=()
for a in "\$@"; do case "\$a" in -mcpu=*|-mtune=*|-march=*|-Wl,--warn-common|-Wl,--sort-common|-Wl,--sort-section,*|-Wl,--gc-sections|-static-libgcc|-Wl,--verbose|-Wl,-Map,*|-Wl,--start-group|-Wl,--end-group) ;; *) args+=("\$a");; esac; done
exec ${CC_MUSL[*]} "\${args[@]}" -Wno-error -Wno-date-time
EOF
for t in ar ranlib objcopy; do printf '#!/bin/bash\nexec %s %s "$@"\n' "$ZIG" "$t" > "$TOOLS/bin/aarch64-linux-musl-$t"; done
printf '#!/bin/bash\nexec llvm-strip "$@" 2>/dev/null || true\n' > "$TOOLS/bin/aarch64-linux-musl-strip"
chmod +x "$TOOLS/bin/"*
if [ ! -x "$TOOLS/busybox" ]; then
	[ -d "$TOOLS/busybox-src" ] || git clone -q --depth 1 --branch "$BUSYBOX_TAG" https://github.com/mirror/busybox.git "$TOOLS/busybox-src"
	(
		cd "$TOOLS/busybox-src"
		export PATH="$TOOLS/bin:$PATH"
		make -s defconfig > /dev/null
		sed -i 's/^# CONFIG_STATIC is not set/CONFIG_STATIC=y/; s/^CONFIG_TC=y/# CONFIG_TC is not set/' .config
		yes '' | make -s oldconfig > /dev/null 2>&1 || true
		make -s -j"$(nproc)" CROSS_COMPILE=aarch64-linux-musl- busybox > /dev/null 2>&1
		cp busybox "$TOOLS/busybox"
	)
fi
"${CC_MUSL[@]}" -static -Os -Wall -o "$TOOLS/amixer" "$HERE/tools/amixer.c"

#######################################
echo "== system image (squashfs)"
R="$WORK/rootfs"
mkdir -p "$R"/{bin,sbin,lib,usr/bin,usr/sbin,usr/lib,usr/share,etc,proc,sys,dev,tmp,run,boot,mnt/SDCARD,root,var}
cp -R "$HERE/rootfs/." "$R/"
sed -i "s/@VERSION@/$VERSION/" "$R/etc/os-release"
echo "$NAME" > "$R/etc/nextui-os-version"
ln -sf /tmp/localtime "$R/etc/localtime"
ln -sf /proc/mounts "$R/etc/mtab"
ln -sf /tmp/var/log "$R/var/log"
ln -sf /tmp/var/tmp "$R/var/tmp"
ln -sf /run "$R/var/run"

# BusyBox and its applets
install -m 755 "$TOOLS/busybox" "$R/bin/busybox"
qemu-aarch64-static "$TOOLS/busybox" --list-full | while read -r app; do
	[ -e "$R/$app" ] && continue
	mkdir -p "$R/$(dirname "$app")"
	ln -s /bin/busybox "$R/$app"
done
install -m 755 "$TOOLS/amixer" "$R/usr/bin/amixer"

# dArkOS's C library, GPU driver (libmali), SDL2 (which rotates the portrait
# panel), ALSA and everything NextUI's programs and cores link against
L="$R/usr/lib/aarch64-linux-gnu"
mkdir -p "$L"
find "$WORK/libs/usr/lib/aarch64-linux-gnu" -maxdepth 1 \( -type f -o -type l \) ! -name '*.a' -exec cp -a {} "$L/" \;
cp -a "$WORK/libs/lib/ld-linux-aarch64.so.1" "$R/lib/" 2>/dev/null || cp -aL "$L/ld-linux-aarch64.so.1" "$R/lib/"
ln -sfn ../usr/lib/aarch64-linux-gnu "$R/lib/aarch64-linux-gnu"
# the collect step keeps first links and final targets; restore the links in
# between (libEGL.so -> libMali.so -> libmali-bifrost-g31-...) from the listing
for pass in 1 2 3; do
	sed -n 's/^l.* \([^ ]*\) -> \([^ ]*\)$/\1 \2/p' "$C/info/libdir-list.txt" | while read -r link target; do
		[ -e "$L/$link" ] || [ -L "$L/$link" ] && continue
		t="$target"; case "$t" in /*) t="$R$t" ;; *) t="$L/$t" ;; esac
		[ -e "$t" ] && ln -s "$target" "$L/$link"
	done
done
for lib in libEGL.so libGLESv2.so libgbm.so.1 libSDL2-2.0.so.0 libasound.so.2 libc.so.6 librga.so.2; do
	[ -e "$L/$lib" ] || { echo "missing $lib in the system image" >&2; exit 1; }
done

# ALSA configuration, kernel modules, time zones
cp -a "$C/etc/alsa-share" "$R/usr/share/alsa"
mkdir -p "$R/lib/modules"
cp -a "$WORK/modules/lib/modules/$KVER" "$R/lib/modules/"
rm -f "$R/lib/modules/$KVER/build" "$R/lib/modules/$KVER/source"
cp -a /usr/share/zoneinfo "$R/usr/share/zoneinfo"

mksquashfs "$R" "$WORK/nextui-os.squashfs" -comp gzip -all-root -noappend -quiet > /dev/null

#######################################
echo "== early boot (uInitrd)"
I="$WORK/initramfs"
mkdir -p "$I/bin"
install -m 755 "$TOOLS/busybox" "$I/bin/busybox"
install -m 755 "$HERE/initramfs/init" "$I/init"
(cd "$I" && find . | cpio -o -H newc --quiet | gzip -9) > "$WORK/initramfs.cpio.gz"
mkimage -A arm64 -O linux -T ramdisk -C none -n uInitrd -d "$WORK/initramfs.cpio.gz" "$WORK/uInitrd" > /dev/null

#######################################
echo "== NextUI for the card"
CARD="$WORK/card"
cp -R "$STAGED/nextui" "$CARD"
rm -rf "$CARD/Tools/rk3326/ArkOS.pak"
cp "$HERE/README-OS.txt" "$CARD/README-V10.txt"
(cd "$CARD" && zip -qr -9 "$WORK/nextui-card.zip" .)

#######################################
echo "== boot partition"
B="$WORK/boot.vfat"
rm -f "$B"
truncate -s ${BOOT_MB}M "$B"
mkfs.vfat -F 32 -n NEXTUI_BOOT "$B" > /dev/null
export MTOOLS_SKIP_CHECK=1
mcopy -i "$B" "$C/boot/Image" "$C/boot/rk3326-odroidgo2-linux-v11.dtb" "$C/boot/logo.bmp" ::/
mcopy -i "$B" "$HERE/boot/boot.ini" "$WORK/uInitrd" "$WORK/nextui-os.squashfs" "$WORK/nextui-card.zip" ::/
mcopy -i "$B" "$HERE/README-OS.txt" ::/README.txt
echo "$NAME" > "$WORK/version.txt"; mcopy -i "$B" "$WORK/version.txt" ::/

#######################################
echo "== card image"
IMG="$OUT/$NAME.img"
rm -f "$IMG" "$IMG.gz"
truncate -s $((16 + BOOT_MB))M "$IMG"
# bootloader (idbloader, u-boot, trust) as on the dArkOS card
dd if="$C/bootloader/head.img" of="$IMG" bs=1M count=16 conv=notrunc status=none
sfdisk --quiet --wipe never "$IMG" <<EOF
label: dos
unit: sectors

start=32768, size=$((BOOT_MB * 2048)), type=c, bootable
EOF
dd if="$B" of="$IMG" bs=1M seek=16 conv=notrunc status=none
gzip -9 "$IMG"

ls -la "$IMG.gz"
du -sh "$WORK/nextui-os.squashfs" "$WORK/nextui-card.zip" "$WORK/uInitrd"
echo "$IMG.gz"
