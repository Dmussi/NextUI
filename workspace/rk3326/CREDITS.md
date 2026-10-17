# NextUI for the Powkiddy V10 — credits and licenses

This is an unofficial, free, non-commercial port of NextUI to the Powkiddy V10
(Rockchip RK3326). It is not made or endorsed by any of the projects below.
Thank you to all of them: this port is built almost entirely on their work.

## What this port is made of

### NextUI, MinUI and the H700 fork
- **NextUI** by the LoveRetro team and contributors —
  https://github.com/LoveRetro/NextUI
  License: PolyForm Noncommercial 1.0.0 (see `LICENSE` in this repository).
- **MinUI** by Shaun Inman, which NextUI is based on —
  https://github.com/shauninman/MinUI
- **pvaibhav's NextUI fork for H700 devices** (h700 branch), used as the
  template for this port — https://github.com/pvaibhav/NextUI
- **BaseOS** by pvaibhav, whose approach (keep the vendor kernel, replace the
  userland with a small BusyBox system) NextUI OS follows —
  https://github.com/pvaibhav/BaseOS

Changes made for the V10 (platform code, input mapping, audio, launch
scripts, NextUI OS) are in the `workspace/rk3326` and `skeleton/*/rk3326`
folders of https://github.com/Dmussi/NextUI (branch `rk3326-v10`).

### dArkOS (used by NextUI OS, unmodified)
NextUI OS (the standalone SD card image) reuses these parts of
**dArkOS** by christianhaitian and the dArkOS team, taken unchanged from a
dArkOS (09022026) card for the RGB10/V10:
https://github.com/christianhaitian/dArkOS — license terms:
https://github.com/christianhaitian/dArkOS/blob/master/LICENSES.md
(dArkOS's own software and scripts: MIT License, © 2021-present dArkOS.)

| Part | Source | License |
|---|---|---|
| Linux kernel 4.4.189 (`Image`) and device tree `rk3326-odroidgo2-linux-v11.dtb` | https://github.com/christianhaitian/linux, branch `odroidgoA-4.4.y` (defconfig `odroidgoa_tweaked_defconfig`) | GPL-2.0 |
| Kernel modules (`/lib/modules/4.4.189`) | same as the kernel | GPL-2.0 |
| U-Boot bootloader (first 16 MB of the card) | https://github.com/christianhaitian/u-boot-rk3326 | GPL-2.0 |
| Boot logo `logo.bmp` | dArkOS | see dArkOS LICENSES.md |
| SDL2 2.32.10 with RK3326 screen rotation | https://github.com/christianhaitian/rk3326_core_builds (based on https://github.com/libsdl-org/SDL) | zlib |
| Mali-G31 GPU driver `libmali-bifrost-g31-rxp0-gbm.so` | Rockchip / Arm, distributed via https://github.com/christianhaitian/rk3326_core_builds | Rockchip/Arm binary license |
| librga (2D rotation) | https://github.com/christianhaitian/linux-rga | LGPL-2.0 |
| C library and other shared libraries (glibc, ALSA, libdrm, FreeType, libpng, zlib, SQLite and others) | Debian 13 "trixie" arm64 packages as installed in dArkOS; sources: https://sources.debian.org | each package's own license (mostly LGPL/GPL/MIT/BSD) |
| ALSA configuration (`/usr/share/alsa`) | alsa-lib via Debian | LGPL-2.1 |

### Written for this port
- NextUI OS boot scripts, `amixer` replacement (ALSA control ioctls and
  headphone-jack switching), crash logger and libcap stub — in
  `workspace/rk3326/os/` of https://github.com/Dmussi/NextUI.
- **BusyBox 1.36.1**, built from https://github.com/mirror/busybox (tag
  `1_36_1`, default config + static) — GPL-2.0. Build script:
  `workspace/rk3326/os/build-os.sh`.
- Time zone data from the IANA tz database (public domain), via Ubuntu tzdata.
- Built with the Zig toolchain (https://ziglang.org, MIT).

### Emulator cores (libretro)
| Core | Source | License |
|---|---|---|
| Gambatte (Game Boy / Color) | https://github.com/libretro/gambatte-libretro | GPL-2.0 |
| gpSP (Game Boy Advance) | https://github.com/libretro/gpsp | GPL-2.0 |
| FCEUmm (NES) | https://github.com/libretro/libretro-fceumm | GPL-2.0 |
| Snes9x (Super Nintendo) | https://github.com/libretro/snes9x | Snes9x license (non-commercial) |
| PicoDrive (Genesis / Mega Drive) | https://github.com/irixxxx/picodrive | PicoDrive license (non-commercial) |
| PCSX ReARMed (PlayStation) | https://github.com/libretro/pcsx_rearmed | GPL-2.0 |

Plus libretro-common (https://github.com/libretro/libretro-common) and the
libraries NextUI bundles (SDL2_image, SDL2_ttf, libsamplerate, libzip,
OpenSSL, zstd, lz4 and others), each under its own license.

## Source code
Everything written for this port, and the scripts that build the release,
are at https://github.com/Dmussi/NextUI (branch `rk3326-v10`). Sources for
the GPL parts listed above are at the linked repositories. The binary GPU
driver has no public source.

## Non-commercial
NextUI, Snes9x, PicoDrive and parts of dArkOS are licensed for
non-commercial use only. This release is free; do not sell it or devices
pre-loaded with it.

Games and BIOS files are not included. Use only games you own.
