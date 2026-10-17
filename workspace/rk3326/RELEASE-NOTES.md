Unofficial, free, non-commercial port of [NextUI](https://github.com/LoveRetro/NextUI) to the **Powkiddy V10** (Rockchip RK3326). Not made or endorsed by the NextUI, dArkOS or ArkOS projects.

## Downloads — pick one

### 1. NextUI OS (standalone, recommended) — `NextUI-OS-V10-*.img.gz`
A small system that boots straight into NextUI, with no ArkOS. Write it to a **spare SD card** with balenaEtcher or Raspberry Pi Imager (this erases the card). On the first start the V10 sets up a NEXTUI drive from the rest of the card (about a minute). Put games in `Roms/<system>` on that drive, BIOS files in `Bios` (PlayStation: `Bios/PS`).

### 2. NextUI on top of dArkOS — `NextUI-V10-ArkOS-Port-*.zip`
For a card that already runs dArkOS: copy `nextui/` to the root of EASYROMS and the files in `ports/` into `EASYROMS/ports`, then start **NextUI** from Ports. Optional: **NextUI - Start at Boot ON** makes it start at power-on (hold L1 at power-on for ArkOS). See `README-V10.txt`.

## Working
Game Boy, Game Boy Color, Game Boy Advance, NES, SNES, Genesis/Mega Drive, PlayStation · sound with speaker/headphone switching · volume and brightness · in-game menu, save states and shaders · sleep and power off.

**Buttons:** SELECT + START together = MENU (the V10 has no MENU button) · volume buttons = volume · hold START + volume = brightness · power button = sleep.

## Known issues
- The clock resets to 2017 after power-off.
- The emulator can crash when quitting some SNES / Game Boy games (after the save is written).
- Wi-Fi and Bluetooth are not supported; fewer systems than ArkOS.

## Credits
Built on the work of others — thank you:
- **NextUI** — LoveRetro team and contributors (PolyForm Noncommercial 1.0.0)
- **MinUI** — Shaun Inman
- **pvaibhav** — the [NextUI H700 fork](https://github.com/pvaibhav/NextUI) used as the template, and [BaseOS](https://github.com/pvaibhav/BaseOS), whose approach NextUI OS follows
- **[dArkOS](https://github.com/christianhaitian/dArkOS)** by christianhaitian and the dArkOS team — NextUI OS reuses, **unmodified**, dArkOS's Linux kernel 4.4 ([source](https://github.com/christianhaitian/linux/tree/odroidgoA-4.4.y)), device tree and kernel modules, U-Boot ([source](https://github.com/christianhaitian/u-boot-rk3326)), boot logo, SDL2 with RK3326 rotation and the Mali-G31 driver ([rk3326_core_builds](https://github.com/christianhaitian/rk3326_core_builds)), librga ([source](https://github.com/christianhaitian/linux-rga)) and Debian 13 libraries. License terms: [dArkOS LICENSES.md](https://github.com/christianhaitian/dArkOS/blob/master/LICENSES.md). Everything else in the system (the BusyBox userland, boot scripts, audio tools) was replaced.
- **libretro cores** — Gambatte, gpSP, FCEUmm, Snes9x, PicoDrive (irixxxx), PCSX ReARMed
- **BusyBox** (GPL-2.0), **Debian** packages, the **IANA tz database**, the **Zig** toolchain

Full list with licenses and source links: [`workspace/rk3326/CREDITS.md`](https://github.com/Dmussi/NextUI/blob/rk3326-v10/workspace/rk3326/CREDITS.md) (also included as `CREDITS.txt` in both downloads). Source for this port: branch [`rk3326-v10`](https://github.com/Dmussi/NextUI/tree/rk3326-v10).

**Non-commercial:** NextUI, Snes9x, PicoDrive and parts of dArkOS are licensed for non-commercial use only. Don't sell this release or devices pre-loaded with it. No games or BIOS files are included.
