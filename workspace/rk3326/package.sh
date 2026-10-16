#!/bin/bash
# Assemble a Powkiddy V10 (ArkOS) test release from built programs and cores.
#
# usage: package.sh <toolchain-prefix> <output-dir>
# Produces <output-dir>/NextUI-V10-<date>.zip containing:
#   nextui/            -> copy to the root of EASYROMS (becomes /roms/nextui)
#   ports/NextUI.sh    -> merge into EASYROMS/ports (becomes the Ports entry)

set -euo pipefail

REPO="$(cd "$(dirname "$0")/../.." && pwd)"
PREFIX="$(realpath "${1:?toolchain prefix}")"
OUT="$(realpath -m "${2:?output dir}")"
P=rk3326
NAME="NextUI-V10-$(date +%Y%m%d)-$(git -C "$REPO" rev-parse --short HEAD)"
STAGE="$OUT/$NAME"
W="$REPO/workspace"
S="$REPO/skeleton"

rm -rf "$STAGE"
mkdir -p "$STAGE/ports"
CARD="$STAGE/nextui"
SYS="$CARD/.system/$P"

# card root: Bios, Roms, Saves, Shaders, Overlays, Cheats, README
cp -R "$S/BASE/." "$CARD/"
rm -rf "$CARD/trimui" "$CARD/em_ui.sh"
find "$CARD" -name '.keep' -delete -o -name '*.meta' -delete

# system folder
mkdir -p "$CARD/.system"
cp -R "$S/SYSTEM/$P" "$SYS"
cp -R "$S/SYSTEM/res" "$CARD/.system/res"
mkdir -p "$SYS/bin" "$SYS/lib" "$SYS/lib/sdl" "$SYS/cores"

cp "$W/all/nextui/build/$P/nextui.elf" "$SYS/bin/"
cp "$W/all/minarch/build/$P/minarch.elf" "$SYS/bin/"
cp "$W/all/nextval/build/$P/nextval.elf" "$SYS/bin/"
cp "$W/all/syncsettings/build/$P/syncsettings.elf" "$SYS/bin/"
cp "$W/all/show2/build/$P/show2.elf" "$SYS/bin/"
cp "$W/all/batmon/build/$P/batmon.elf" "$SYS/bin/"
cp "$W/all/gametimectl/build/$P/gametimectl.elf" "$SYS/bin/"
cp "$W/$P/keymon/keymon.elf" "$SYS/bin/"

cp "$W/$P/libmsettings/libmsettings.so" "$SYS/lib/"
cp "$W/all/libbatmondb/build/$P/libbatmondb.so" "$SYS/lib/"
cp "$W/all/libgametimedb/build/$P/libgametimedb.so" "$SYS/lib/"
# minarch's runtime libraries (collected by its makefile)
cp -L "$W/all/minarch/build/$P/"*.so.* "$SYS/lib/"
cp -L "$PREFIX/lib/libsqlite3.so.0" "$PREFIX/lib/libz.so.1" "$SYS/lib/"
# fallback SDL2 (NEXTUI_BUNDLED_SDL=1); ArkOS's own SDL2 is used by default
cp -L "$PREFIX/lib/libSDL2-2.0.so.0" "$PREFIX/lib/libSDL2_image-2.0.so.0" "$PREFIX/lib/libSDL2_ttf-2.0.so.0" "$SYS/lib/sdl/"

# tools
mkdir -p "$CARD/Tools/$P"
cp -R "$S/EXTRAS/Tools/$P/." "$CARD/Tools/$P/"
cp "$W/all/settings/build/$P/settings.elf" "$CARD/Tools/$P/Settings.pak/"
cp "$W/all/minput/build/$P/minput.elf" "$CARD/Tools/$P/Input.pak/"
cp "$W/all/battery/build/$P/battery.elf" "$CARD/Tools/$P/Battery.pak/"
cp "$W/all/gametime/build/$P/gametime.elf" "$CARD/Tools/$P/Game Tracker.pak/"
cp "$W/all/clock/build/$P/clock.elf" "$CARD/Tools/$P/Clock.pak/"

# stock cores (whatever has been built)
for core in fceumm gambatte gpsp picodrive snes9x pcsx_rearmed; do
	f="$W/$P/cores/output/${core}_libretro.so"
	if [ -f "$f" ]; then cp "$f" "$SYS/cores/"; else echo "warning: core $core not built"; fi
done

# no build-machine library paths in the shipped binaries
find "$SYS" "$CARD/Tools" -type f \( -name '*.elf' -o -name '*.so' -o -name '*.so.*' \) -print0 |
	xargs -0 -n1 patchelf --remove-rpath

# ports entry + version
cp "$W/$P/install/NextUI.sh" "$STAGE/ports/NextUI.sh"
cp "$W/$P/install/NextUI Sound Test.sh" "$STAGE/ports/"
printf '%s\n%s\n' "$NAME" "$(git -C "$REPO" rev-parse --short HEAD)" > "$CARD/.system/version.txt"
cp "$W/$P/install/README-V10.txt" "$STAGE/README-V10.txt"

# exFAT has no exec bits, but keep them for anyone copying from Linux
find "$STAGE" -name '*.sh' -exec chmod +x {} +
find "$STAGE" -name '*.elf' -exec chmod +x {} +

(cd "$STAGE" && rm -f "../$NAME.zip" && zip -qr "../$NAME.zip" nextui ports README-V10.txt)
echo "$OUT/$NAME.zip"
