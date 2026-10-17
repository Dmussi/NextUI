#!/bin/sh
# Leave NextUI and go back to ArkOS (EmulationStation).
# Removing the exec marker ends NextUI's launch loop once this pak returns;
# the Ports entry or the boot front end then starts EmulationStation.
rm -f /tmp/nextui_exec
sync
