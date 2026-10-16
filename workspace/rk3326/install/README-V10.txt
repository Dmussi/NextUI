NextUI for the Powkiddy V10 (ArkOS) - unofficial test build
============================================================

This runs NextUI on top of ArkOS. ArkOS stays installed; NextUI starts
from the Ports menu and returns to ArkOS when you power off from NextUI.

INSTALL
1. Power off the V10 and put its SD card in your computer.
2. Open the EASYROMS drive.
3. Copy the "nextui" folder from this zip to the root of EASYROMS.
4. Copy "NextUI.sh" from this zip's "ports" folder into EASYROMS/ports.
5. Put the card back, start the V10, open Ports and choose NextUI.
   (If NextUI does not show in Ports, choose "Update Games List" in the
   EmulationStation start menu first.)

GAMES
- Games already in ArkOS's gb, gbc, gba, nes, snes, genesis/megadrive and
  psx folders show up in NextUI automatically.
- You can also put games in nextui/Roms/<system folder>.
- BIOS files go in nextui/Bios (PlayStation: nextui/Bios/PS).
- To stop NextUI from showing ArkOS's games, create an empty file named
  no-arkos-roms in nextui/.userdata/rk3326/

BUTTONS
- SELECT + START together = MENU (the V10 has no MENU button)
- Volume buttons = volume; hold START + volume buttons = brightness
- Power button = sleep / wake
- Power off from NextUI's menu = back to ArkOS. To make it really power
  off, create an empty file named real-poweroff in nextui/.userdata/rk3326/
- If a button is wrong, edit nextui/.system/rk3326/keymap.txt

IF SOMETHING GOES WRONG
Logs are in nextui/.userdata/rk3326/logs/ (port.txt, launch.txt,
nextui.txt, and one file per emulator). Send those back.

NOT YET WORKING
Wi-Fi and Bluetooth settings, deep sleep, Clock tool, LED and bootlogo
tools, Pak Store and updater.
