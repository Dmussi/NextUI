#!/bin/bash
# One-shot build of NextUI for the Powkiddy V10 (rk3326 on ArkOS).
#
# Needs: python3 + pip, git, cmake, ninja, make, perl, zip.
# usage: workspace/rk3326/build.sh [deps-dir] [toolchain-prefix] [output-dir]
#
# Steps: fetch sources -> build toolchain/sysroot -> build NextUI programs ->
#        build the six stock emulator cores -> package a test release zip.

set -euo pipefail

REPO="$(cd "$(dirname "$0")/../.." && pwd)"
DEPS="${1:-$HOME/rk3326-deps}"
PREFIX="${2:-/opt/rk3326}"
OUT="${3:-$REPO/releases}"
W="$REPO/workspace"

pip install --break-system-packages -q ziglang patchelf 2>/dev/null || pip install -q ziglang patchelf

#######################################
# sources (all from GitHub)
mkdir -p "$DEPS"
fetch() { # url ref dir [sparse-path]
	[ -d "$DEPS/$3" ] && return 0
	if [ -n "${4:-}" ]; then
		git clone -q --depth 1 --filter=blob:none --sparse ${2:+--branch "$2"} "$1" "$DEPS/$3"
		git -C "$DEPS/$3" sparse-checkout set "$4"
	else
		git clone -q --depth 1 ${2:+--branch "$2"} "$1" "$DEPS/$3"
	fi
}
fetch https://github.com/libsdl-org/SDL.git release-2.30.9 SDL
fetch https://github.com/libsdl-org/SDL_image.git release-2.8.8 SDL_image
fetch https://github.com/libsdl-org/SDL_ttf.git release-2.24.0 SDL_ttf
fetch https://github.com/libsdl-org/freetype.git VER-2-13-3-SDL freetype
fetch https://github.com/madler/zlib.git v1.3.1 zlib
fetch https://github.com/libsndfile/libsamplerate.git 0.2.2 libsamplerate
fetch https://github.com/KhronosGroup/EGL-Registry.git "" EGL-Registry
fetch https://github.com/KhronosGroup/OpenGL-Registry.git "" OpenGL-Registry
fetch https://github.com/alsa-project/alsa-lib.git v1.2.12 alsa-lib
fetch https://github.com/grate-driver/libdrm.git "" libdrm
fetch https://github.com/JeffyCN/mirrors.git libmali libmali include
fetch https://github.com/lz4/lz4.git v1.10.0 lz4
fetch https://github.com/libarchive/bzip2.git "" bzip2
fetch https://github.com/tukaani-project/xz.git v5.6.3 xz
fetch https://github.com/facebook/zstd.git v1.5.6 zstd
fetch https://github.com/nih-at/libzip.git v1.11.2 libzip
fetch https://github.com/openssl/openssl.git openssl-3.0.15 openssl
fetch https://github.com/azadkuh/sqlite-amalgamation.git "" sqlite

#######################################
bash "$W/rk3326/toolchain/build-toolchain.sh" "$DEPS" "$PREFIX"

export PATH="$PREFIX/bin:$PATH"
export CROSS_COMPILE=aarch64-linux-gnu- PREFIX PREFIX_LOCAL="$PREFIX"
export PLATFORM=rk3326 UNION_PLATFORM=rk3326
export CC=aarch64-linux-gnu-gcc CXX=aarch64-linux-gnu-g++ AR=aarch64-linux-gnu-ar RANLIB=aarch64-linux-gnu-ranlib
git -C "$REPO" rev-parse --short HEAD > "$W/hash.txt"

#######################################
make -C "$W/rk3326/libmsettings"
make -C "$W/rk3326/keymon"
for d in nextui minarch nextval syncsettings show2 minput settings \
         libbatmondb batmon battery libgametimedb gametimectl gametime; do
	echo "== $d"
	make -C "$W/all/$d"
done

#######################################
for core in gambatte gpsp fceumm snes9x picodrive pcsx_rearmed; do
	echo "== core $core"
	make -C "$W/rk3326/cores" "$core"
done

#######################################
bash "$W/rk3326/package.sh" "$PREFIX" "$OUT"
