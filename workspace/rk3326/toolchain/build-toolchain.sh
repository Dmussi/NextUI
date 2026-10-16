#!/bin/bash
# Build the rk3326 (Powkiddy V10 / ArkOS) cross toolchain + sysroot.
#
# Compiler: Zig's clang (pip install ziglang) targeting aarch64 glibc 2.28,
# so binaries also run on ArkOS releases with an older userland.
# Everything else is built from source; GPU, DRM and ALSA libraries are
# header-only here and are loaded from ArkOS at runtime.
#
# usage: build-toolchain.sh <deps-dir> <prefix>
#   deps-dir holds the git checkouts (see fetch list in README.md)
#   prefix   is where bin/, include/ and lib/ are installed

set -euo pipefail

DEPS="$(realpath "${1:?deps dir}")"
PREFIX="$(realpath -m "${2:?prefix}")"
GLIBC="${GLIBC:-2.28}"
JOBS="$(nproc)"
TRIPLE=aarch64-linux-gnu

mkdir -p "$PREFIX"/{bin,include,lib/pkgconfig} "$PREFIX/build"
BUILD="$PREFIX/build"

log() { printf '\n==== %s\n' "$*"; }

#######################################
log "compiler wrappers"

ZIG="$(python3 -c 'import ziglang, os; print(os.path.join(os.path.dirname(ziglang.__file__), "zig"))')"
[ -x "$ZIG" ] || { echo "zig not found: pip install ziglang"; exit 1; }
for tool in gcc cc g++ c++; do
	lang=cc; { [ "$tool" = g++ ] || [ "$tool" = c++ ]; } && lang=c++
	cat > "$PREFIX/bin/$TRIPLE-$tool" <<EOF
#!/bin/bash
# GCC-compatible front end over zig's clang, targeting glibc $GLIBC.
# Drops the few GCC-only flags NextUI's makefiles pass.
case "\$1" in --print-sysroot|-print-sysroot) echo "$PREFIX"; exit 0 ;; esac
args=()
srcs=()
compile_only=0
has_out=0
for a in "\$@"; do
	case "\$a" in
		-mcpu=*|-mtune=*|-march=*|-flto|-Wl,--no-as-needed|-Wl,--as-needed) ;;
		-Wl,-no-undefined|-Wl,--no-undefined) args+=("-Wl,-z,defs") ;;
		-c) compile_only=1; args+=("\$a") ;;
		-o) has_out=1; args+=("\$a") ;;
		*.c|*.cc|*.cpp|*.cxx|*.S|*.s) srcs+=("\$a") ;;
		*) args+=("\$a") ;;
	esac
done
ZIGCC=("$ZIG" $lang -target $TRIPLE.$GLIBC -mcpu=cortex_a35)
# behave like a sysroot'd cross gcc: search the toolchain prefix by default
TAIL=(-idirafter "$PREFIX/include" -L"$PREFIX/lib" -Wno-error=incompatible-pointer-types-discards-qualifiers -Wno-error=tautological-constant-out-of-range-compare -Wno-error=pointer-bool-conversion)
# gcc compiles every source with "-c a.c b.c"; zig only does one, so split
if [ \$compile_only = 1 ] && [ \$has_out = 0 ] && [ \${#srcs[@]} -gt 1 ]; then
	for src in "\${srcs[@]}"; do
		"\${ZIGCC[@]}" "\${args[@]}" "\$src" "\${TAIL[@]}" || exit \$?
	done
	exit 0
fi
exec "\${ZIGCC[@]}" "\${args[@]}" "\${srcs[@]}" "\${TAIL[@]}"
EOF
	chmod +x "$PREFIX/bin/$TRIPLE-$tool"
done
for tool in ar ranlib; do
	printf '#!/bin/sh\nexec "%s" %s "$@"\n' "$ZIG" "$tool" > "$PREFIX/bin/$TRIPLE-$tool"
	chmod +x "$PREFIX/bin/$TRIPLE-$tool"
done
# zig has no strip; linking with -s already strips, so make strip a no-op
printf '#!/bin/sh\nexit 0\n' > "$PREFIX/bin/$TRIPLE-strip"
chmod +x "$PREFIX/bin/$TRIPLE-strip"

CC="$PREFIX/bin/$TRIPLE-gcc"
CXX="$PREFIX/bin/$TRIPLE-g++"

cat > "$BUILD/toolchain.cmake" <<EOF
set(CMAKE_SYSTEM_NAME Linux)
set(CMAKE_SYSTEM_PROCESSOR aarch64)
set(CMAKE_C_COMPILER $CC)
set(CMAKE_CXX_COMPILER $CXX)
set(CMAKE_AR $PREFIX/bin/$TRIPLE-ar)
set(CMAKE_RANLIB $PREFIX/bin/$TRIPLE-ranlib)
set(CMAKE_FIND_ROOT_PATH $PREFIX)
set(CMAKE_FIND_ROOT_PATH_MODE_PROGRAM NEVER)
set(CMAKE_FIND_ROOT_PATH_MODE_LIBRARY ONLY)
set(CMAKE_FIND_ROOT_PATH_MODE_INCLUDE ONLY)
set(CMAKE_FIND_ROOT_PATH_MODE_PACKAGE ONLY)
EOF
export PKG_CONFIG_LIBDIR="$PREFIX/lib/pkgconfig"
export PKG_CONFIG_PATH=""
export PKG_CONFIG_SYSROOT_DIR=""

cmake_build() { # src builddir args...
	local src="$1" dir="$2"; shift 2
	[ -f "$dir/.done" ] && { echo "(already built)"; return 0; }
	cmake -S "$src" -B "$dir" -G Ninja \
		-DCMAKE_TOOLCHAIN_FILE="$BUILD/toolchain.cmake" \
		-DCMAKE_BUILD_TYPE=Release \
		-DCMAKE_INSTALL_PREFIX="$PREFIX" \
		-DCMAKE_INSTALL_LIBDIR=lib \
		-DCMAKE_PREFIX_PATH="$PREFIX" "$@" > "$dir.log" 2>&1 || { tail -40 "$dir.log"; exit 1; }
	cmake --build "$dir" -j "$JOBS" >> "$dir.log" 2>&1 || { tail -40 "$dir.log"; exit 1; }
	cmake --install "$dir" >> "$dir.log" 2>&1
	touch "$dir/.done"
}

# stub shared library with a real soname, for link-time and for cmake's
# soname detection; the real one comes from ArkOS at runtime
stub_lib() { # soname source.c
	local soname="$1" src="$2" base="${1%%.so*}"
	"$CC" -shared -fPIC -o "$PREFIX/lib/$soname" -Wl,-soname,"$soname" "$src"
	ln -sf "$soname" "$PREFIX/lib/$base.so"
}

#######################################
log "GPU / DRM / ALSA headers"

cp -r "$DEPS/EGL-Registry/api/EGL" "$DEPS/EGL-Registry/api/KHR" "$PREFIX/include/"
cp -r "$DEPS/OpenGL-Registry/api/GLES2" "$DEPS/OpenGL-Registry/api/GLES3" "$PREFIX/include/"

mkdir -p "$PREFIX/include/libdrm"
cp "$DEPS/libdrm/include/drm/"*.h "$PREFIX/include/libdrm/"
cp "$DEPS/libdrm/xf86drm.h" "$DEPS/libdrm/xf86drmMode.h" "$PREFIX/include/"
GBM_H="$(find "$DEPS/libmali/include/GBM" -name gbm.h | sort -V | tail -1)"
cp "$GBM_H" "$PREFIX/include/gbm.h"

mkdir -p "$PREFIX/include/alsa/sound"
A="$DEPS/alsa-lib/include"
for h in "$A"/*.h; do
	case "$(basename "$h")" in asoundlib-head.h|asoundlib-tail.h|local.h|alsa-symbols.h|aserver.h|search.h|list.h|bswap.h|sys.h) ;;
	*) cp "$h" "$PREFIX/include/alsa/" ;; esac
done
cp "$A"/sound/uapi/*.h "$PREFIX/include/alsa/sound/" 2>/dev/null || true
cp "$A"/sound/*.h "$PREFIX/include/alsa/sound/" 2>/dev/null || true
VER="$(grep -m1 AC_INIT "$DEPS/alsa-lib/configure.ac" | grep -oE "[0-9]+\.[0-9]+\.[0-9]+" | tr . " ")"
set -- $VER
cat > "$PREFIX/include/alsa/version.h" <<EOF
#define SND_LIB_MAJOR $1
#define SND_LIB_MINOR $2
#define SND_LIB_SUBMINOR $3
#define SND_LIB_EXTRAVER 1000000
#define SND_LIB_VER(maj, min, sub) (((maj)<<16)|((min)<<8)|(sub))
#define SND_LIB_VERSION SND_LIB_VER(SND_LIB_MAJOR, SND_LIB_MINOR, SND_LIB_SUBMINOR)
#define SND_LIB_VERSION_STR "$1.$2.$3"
EOF
{
	cat "$A/asoundlib-head.h"
	echo '#include <endian.h>'
	for h in asoundef version global input output error conf pcm rawmidi ump timer hwdep control mixer seq_event seq seqmid seq_midi_event; do
		echo "#include <alsa/$h.h>"
	done
	cat "$A/asoundlib-tail.h"
} > "$PREFIX/include/alsa/asoundlib.h"

#######################################
log "runtime stubs (libdrm, libgbm, libEGL, libGLESv2, libasound)"

echo 'void __rk3326_stub(void) {}' > "$BUILD/empty.c"
stub_lib libdrm.so.2 "$BUILD/empty.c"
stub_lib libgbm.so.1 "$BUILD/empty.c"
stub_lib libEGL.so.1 "$BUILD/empty.c"
stub_lib libasound.so.2 "$BUILD/empty.c"

# libGLESv2: every gl* entry point the GLES 3.2 headers declare, so programs
# linking -lGLESv2 resolve at build time and bind to libmali at runtime
python3 - "$PREFIX/include/GLES3/gl32.h" "$PREFIX/include/GLES2/gl2ext.h" > "$BUILD/glesv2_stub.c" <<'PY'
import re, sys
names = set()
for path in sys.argv[1:]:
    for m in re.finditer(r'GL_APICALL\s+[^;]*?\bGL_APIENTRY\s+(gl\w+)\s*\(', open(path).read()):
        names.add(m.group(1))
for n in sorted(names):
    print('void %s(void) {}' % n)
PY
stub_lib libGLESv2.so.2 "$BUILD/glesv2_stub.c"

cat > "$PREFIX/lib/pkgconfig/libdrm.pc" <<EOF
prefix=$PREFIX
includedir=\${prefix}/include
libdir=\${prefix}/lib
Name: libdrm
Description: headers only (runtime from ArkOS)
Version: 2.4.100
Libs: -L\${libdir} -ldrm
Cflags: -I\${includedir} -I\${includedir}/libdrm
EOF
cat > "$PREFIX/lib/pkgconfig/gbm.pc" <<EOF
prefix=$PREFIX
includedir=\${prefix}/include
libdir=\${prefix}/lib
Name: gbm
Description: headers only (runtime from ArkOS libmali)
Version: 17.1.0
Libs: -L\${libdir} -lgbm
Cflags: -I\${includedir}
EOF
cat > "$PREFIX/lib/pkgconfig/glesv2.pc" <<EOF
prefix=$PREFIX
includedir=\${prefix}/include
libdir=\${prefix}/lib
Name: glesv2
Description: headers + link stub (runtime from ArkOS libmali)
Version: 3.2
Libs: -L\${libdir} -lGLESv2
Cflags: -I\${includedir}
EOF
cat > "$PREFIX/lib/pkgconfig/egl.pc" <<EOF
prefix=$PREFIX
includedir=\${prefix}/include
libdir=\${prefix}/lib
Name: egl
Description: headers + link stub (runtime from ArkOS libmali)
Version: 1.5
Libs: -L\${libdir} -lEGL
Cflags: -I\${includedir}
EOF
cat > "$PREFIX/lib/pkgconfig/alsa.pc" <<EOF
prefix=$PREFIX
includedir=\${prefix}/include
libdir=\${prefix}/lib
Name: alsa
Description: headers + link stub (runtime from ArkOS)
Version: 1.2.12
Libs: -L\${libdir} -lasound
Cflags: -I\${includedir}
EOF

#######################################
log "zlib"
cmake_build "$DEPS/zlib" "$BUILD/zlib" -DZLIB_BUILD_EXAMPLES=OFF
rm -f "$PREFIX/lib/libz.a"

#######################################
log "libsamplerate"
cmake_build "$DEPS/libsamplerate" "$BUILD/libsamplerate" \
	-DBUILD_SHARED_LIBS=ON -DBUILD_TESTING=OFF -DLIBSAMPLERATE_EXAMPLES=OFF -DLIBSAMPLERATE_INSTALL=ON

#######################################
log "SDL2 (KMS/DRM + GLES + ALSA, all loaded at runtime)"
cmake_build "$DEPS/SDL" "$BUILD/sdl2" \
	-DSDL_SHARED=ON -DSDL_STATIC=OFF -DSDL_TEST=OFF -DSDL2_DISABLE_SDL2MAIN=ON \
	-DSDL_KMSDRM=ON -DSDL_KMSDRM_SHARED=ON \
	-DSDL_OPENGL=OFF -DSDL_OPENGLES=ON -DSDL_VULKAN=OFF \
	-DSDL_X11=OFF -DSDL_WAYLAND=OFF -DSDL_RPI=OFF -DSDL_VIVANTE=OFF -DSDL_DIRECTFB=OFF -DSDL_OFFSCREEN=ON \
	-DSDL_ALSA=ON -DSDL_ALSA_SHARED=ON \
	-DSDL_PULSEAUDIO=OFF -DSDL_PIPEWIRE=OFF -DSDL_JACK=OFF -DSDL_SNDIO=OFF -DSDL_ESD=OFF -DSDL_ARTS=OFF -DSDL_NAS=OFF -DSDL_OSS=OFF \
	-DSDL_LIBUDEV=OFF -DSDL_DBUS=OFF -DSDL_IBUS=OFF -DSDL_HIDAPI=OFF -DSDL_LIBSAMPLERATE=OFF

#######################################
log "SDL2_image (stb backend: PNG + JPG, no external libs)"
cmake_build "$DEPS/SDL_image" "$BUILD/sdl2_image" \
	-DBUILD_SHARED_LIBS=ON -DSDL2IMAGE_SAMPLES=OFF -DSDL2IMAGE_TESTS=OFF -DSDL2IMAGE_VENDORED=OFF \
	-DSDL2IMAGE_BACKEND_STB=ON -DSDL2IMAGE_PNG=ON -DSDL2IMAGE_JPG=ON \
	-DSDL2IMAGE_AVIF=OFF -DSDL2IMAGE_JXL=OFF -DSDL2IMAGE_TIF=OFF -DSDL2IMAGE_WEBP=OFF \
	-DSDL2IMAGE_BMP=ON -DSDL2IMAGE_GIF=ON -DSDL2IMAGE_SVG=ON \
	-DSDL2IMAGE_LBM=OFF -DSDL2IMAGE_PCX=OFF -DSDL2IMAGE_PNM=OFF -DSDL2IMAGE_QOI=ON \
	-DSDL2IMAGE_TGA=OFF -DSDL2IMAGE_XCF=OFF -DSDL2IMAGE_XPM=OFF -DSDL2IMAGE_XV=OFF

#######################################
log "SDL2_ttf (vendored FreeType, no HarfBuzz)"
rm -rf "$DEPS/SDL_ttf/external/freetype"
ln -s "$DEPS/freetype" "$DEPS/SDL_ttf/external/freetype"
cmake_build "$DEPS/SDL_ttf" "$BUILD/sdl2_ttf" \
	-DBUILD_SHARED_LIBS=ON -DSDL2TTF_SAMPLES=OFF -DSDL2TTF_VENDORED=ON -DSDL2TTF_HARFBUZZ=OFF

#######################################
log "compression libraries (lz4, bzip2, xz, zstd, libzip)"
cmake_build "$DEPS/lz4/build/cmake" "$BUILD/lz4" -DBUILD_SHARED_LIBS=ON -DBUILD_STATIC_LIBS=OFF -DLZ4_BUILD_CLI=OFF
cmake_build "$DEPS/bzip2" "$BUILD/bzip2" -DENABLE_SHARED_LIB=ON -DENABLE_STATIC_LIB=OFF -DENABLE_APP=OFF -DENABLE_TESTS=OFF -DENABLE_DOCS=OFF -DENABLE_EXAMPLES=OFF
cmake_build "$DEPS/xz" "$BUILD/xz" -DBUILD_SHARED_LIBS=ON -DXZ_TOOL_XZ=OFF -DXZ_TOOL_XZDEC=OFF -DXZ_TOOL_LZMADEC=OFF -DXZ_TOOL_LZMAINFO=OFF -DXZ_TOOL_SCRIPTS=OFF -DXZ_DOC=OFF -DXZ_NLS=OFF -DCREATE_XZ_SYMLINKS=OFF -DCREATE_LZMA_SYMLINKS=OFF -DXZ_TOOL_SYMLINKS=OFF -DXZ_TOOL_SYMLINKS_LZMA=OFF
cmake_build "$DEPS/zstd/build/cmake" "$BUILD/zstd" -DZSTD_BUILD_SHARED=ON -DZSTD_BUILD_STATIC=OFF -DZSTD_BUILD_PROGRAMS=OFF -DZSTD_BUILD_TESTS=OFF -DZSTD_LEGACY_SUPPORT=OFF

#######################################
log "OpenSSL (libcrypto only)"
mkdir -p "$BUILD/openssl"
[ -f "$PREFIX/lib/libcrypto.so.3" ] || ( cd "$BUILD/openssl" && \
  CC="$CC" AR="$PREFIX/bin/$TRIPLE-ar" RANLIB="$PREFIX/bin/$TRIPLE-ranlib" \
  "$DEPS/openssl/Configure" linux-aarch64 shared no-tests no-engine no-async no-afalgeng \
	--prefix="$PREFIX" --libdir=lib --openssldir=/etc/ssl > configure.log 2>&1 && \
  make -j "$JOBS" build_libs > build.log 2>&1 && \
  make install_dev > install.log 2>&1 ) || { tail -30 "$BUILD/openssl/"*.log; exit 1; }
rm -f "$PREFIX/lib/libcrypto.a" "$PREFIX/lib/libssl.a"

cmake_build "$DEPS/libzip" "$BUILD/libzip" -DBUILD_SHARED_LIBS=ON -DBUILD_TOOLS=OFF -DBUILD_REGRESS=OFF -DBUILD_OSSFUZZ=OFF -DBUILD_EXAMPLES=OFF -DBUILD_DOC=OFF \
	-DENABLE_GNUTLS=OFF -DENABLE_MBEDTLS=OFF -DENABLE_OPENSSL=OFF -DENABLE_COMMONCRYPTO=OFF -DENABLE_WINDOWS_CRYPTO=OFF \
	-DENABLE_BZIP2=ON -DENABLE_LZMA=ON -DENABLE_ZSTD=ON

#######################################
log "SQLite"
"$CC" -O2 -fPIC -shared -o "$PREFIX/lib/libsqlite3.so.0" -Wl,-soname,libsqlite3.so.0 \
	-DSQLITE_THREADSAFE=1 -DSQLITE_OMIT_LOAD_EXTENSION "$DEPS/sqlite/sqlite3.c" -lpthread
ln -sf libsqlite3.so.0 "$PREFIX/lib/libsqlite3.so"
cp "$DEPS/sqlite/sqlite3.h" "$DEPS/sqlite/sqlite3ext.h" "$PREFIX/include/"

#######################################
log "done"
ls -l "$PREFIX/lib"/*.so* | awk '{print $NF}'
