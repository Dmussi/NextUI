#!/bin/bash
# Static check of a staged V10 release: every shipped ELF must be aarch64,
# need nothing newer than the glibc on ArkOS, carry no build-machine
# library path, and only need libraries that are either bundled or provided
# by ArkOS (list taken from the V10 probe of dArkOS 09022026).
#
# usage: verify-package.sh <staged nextui folder>

set -uo pipefail
CARD="$(realpath "${1:?staged nextui folder}")"
MAX_GLIBC="${MAX_GLIBC:-2.41}"

ARKOS_LIBS="libc.so.6 libm.so.6 libpthread.so.0 libdl.so.2 librt.so.1 ld-linux-aarch64.so.1
libSDL2-2.0.so.0 libSDL2_image-2.0.so.0 libSDL2_ttf-2.0.so.0 libGLESv2.so.2 libEGL.so.1
libasound.so.2 libdrm.so.2 libgbm.so.1 libstdc++.so.6 libgcc_s.so.1"

bundled=$(find "$CARD/.system/rk3326/lib" -maxdepth 1 -name '*.so*' -printf '%f\n')
fail=0
while IFS= read -r -d '' f; do
	file -b "$f" | grep -q '^ELF 64-bit LSB.*ARM aarch64' || continue
	rel="${f#$CARD/}"
	if readelf -d "$f" | grep -qE 'RPATH|RUNPATH'; then
		echo "FAIL $rel: has an rpath"; fail=1
	fi
	glibc=$(readelf -V "$f" 2>/dev/null | grep -oE 'GLIBC_[0-9.]+' | sed 's/GLIBC_//' | sort -uV | tail -1)
	if [ -n "$glibc" ] && [ "$(printf '%s\n%s\n' "$glibc" "$MAX_GLIBC" | sort -V | tail -1)" != "$MAX_GLIBC" ]; then
		echo "FAIL $rel: needs glibc $glibc"; fail=1
	fi
	for need in $(readelf -d "$f" | sed -n 's/.*NEEDED.*\[\(.*\)\]/\1/p'); do
		case " $(echo $ARKOS_LIBS) " in *" $need "*) continue ;; esac
		echo "$bundled" | grep -qx "$need" && continue
		# libraries the cores/tools expect next to themselves
		[ -f "$(dirname "$f")/$need" ] && continue
		echo "FAIL $rel: needs $need (not bundled, not on ArkOS)"; fail=1
	done
done < <(find "$CARD" -type f \( -name '*.elf' -o -name '*.so' -o -name '*.so.*' \) -print0)

[ $fail = 0 ] && echo "verify: all binaries OK"
exit $fail
