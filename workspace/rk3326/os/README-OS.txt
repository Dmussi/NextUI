NextUI OS for the Powkiddy V10 - unofficial test build
======================================================

A small system that starts NextUI directly, without ArkOS. The bootloader,
Linux kernel and graphics driver come unchanged from dArkOS; everything
else is new and much smaller.

INSTALL (use a separate SD card - this erases the card you write it to)
1. Write NextUI-OS-V10-....img.gz to the SD card with balenaEtcher or
   Raspberry Pi Imager (they unpack the .gz themselves).
2. Put the card in the V10 and turn it on.
3. The first start sets the card up (about a minute): it creates the
   NEXTUI drive from the rest of the card and copies NextUI onto it.

THE SD CARD
- NEXTUI drive: your games, BIOS files and saves, like on any NextUI
  device. Put games in Roms/<system folder>, BIOS files in Bios
  (PlayStation: Bios/PS).
- NEXTUI_BOOT drive: the system itself. Leave it alone.

BUTTONS
- SELECT + START together = MENU (the V10 has no MENU button)
- Volume buttons = volume; hold START + volume buttons = brightness
- Power button = sleep / wake
- Power Off in NextUI's menu turns the V10 off.
- If a button is wrong, edit .system/rk3326/keymap.txt on the NEXTUI drive.

UPDATING NEXTUI
Copy a newer .system folder onto the NEXTUI drive. To reinstall the version
that came with this image, delete the .system folder and start the V10.

IF SOMETHING GOES WRONG
Logs are in .userdata/rk3326/logs/ on the NEXTUI drive (boot.txt,
launch.txt, nextui.txt, one file per emulator). Send those back.

Wi-Fi and Bluetooth are not supported.
