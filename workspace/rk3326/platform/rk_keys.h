// rk3326 - button code table shared by platform.c and keymon.
//
// The V10's raw evdev codes are not documented, so every code is a runtime
// value: compiled-in defaults (best guesses for the RK3326 gpio/adc joypad
// used by ArkOS) that a plain text file on the card can override without a
// rebuild:
//
//     $SYSTEM_PATH/keymap.txt   (or /mnt/SDCARD/.system/rk3326/keymap.txt)
//
//     # one NAME=code per line, -1 = button does not exist
//     A=305
//     B=304
//     HOTKEY=708
//
// Names: UP DOWN LEFT RIGHT A B X Y L1 R1 L2 R2 SELECT START MENU PLUS MINUS
//        POWER HOTKEY
// HOTKEY is the button held for volume / brightness combos in keymon.

#ifndef RK_KEYS_H
#define RK_KEYS_H

#include <stdio.h>
#include <stdlib.h>
#include <string.h>
#include <strings.h>

enum {
	RKK_UP, RKK_DOWN, RKK_LEFT, RKK_RIGHT,
	RKK_A, RKK_B, RKK_X, RKK_Y,
	RKK_L1, RKK_R1, RKK_L2, RKK_R2,
	RKK_SELECT, RKK_START, RKK_MENU,
	RKK_PLUS, RKK_MINUS, RKK_POWER, RKK_HOTKEY,
	RKK_COUNT
};

static const char *rk_key_names[RKK_COUNT] __attribute__((unused)) = {
	"UP", "DOWN", "LEFT", "RIGHT",
	"A", "B", "X", "Y",
	"L1", "R1", "L2", "R2",
	"SELECT", "START", "MENU",
	"PLUS", "MINUS", "POWER", "HOTKEY",
};

// Defaults: confirmed on a Powkiddy V10 running dArkOS (09022026), pad
// "GO-Advance Gamepad (rev 1.1)" on event2, power key on event0.
static int rk_keys[RKK_COUNT] __attribute__((unused)) = {
	544, 545, 546, 547,     // BTN_DPAD_UP/DOWN/LEFT/RIGHT
	305, 304, 307, 308,     // A B X Y
	310, 311, 706, 707,     // L1 R1 L2 R2
	704, 709, -1,           // SELECT (-), START (+), no MENU button
	708, 705,               // volume up / volume down buttons
	116,                    // KEY_POWER (rk8xx_pwrkey)
	709,                    // HOTKEY: START held + volume = brightness
};

static int rk_keys_loaded __attribute__((unused)) = 0;

static inline __attribute__((unused)) void rk_keys_load_file(const char *path) {
	FILE *f = fopen(path, "r");
	if (!f) return;
	char line[128];
	while (fgets(line, sizeof(line), f)) {
		char *eq = strchr(line, '=');
		if (line[0] == '#' || !eq) continue;
		*eq = '\0';
		char *name = line;
		while (*name == ' ' || *name == '\t') name++;
		char *end = name + strlen(name);
		while (end > name && (end[-1] == ' ' || end[-1] == '\t')) *--end = '\0';
		for (int i = 0; i < RKK_COUNT; i++) {
			if (strcasecmp(name, rk_key_names[i]) == 0) {
				rk_keys[i] = atoi(eq + 1);
				break;
			}
		}
	}
	fclose(f);
}

static inline __attribute__((unused)) void rk_keys_init(void) {
	if (rk_keys_loaded) return;
	rk_keys_loaded = 1;
	char path[512];
	const char *system_path = getenv("SYSTEM_PATH");
	if (system_path) {
		snprintf(path, sizeof(path), "%s/keymap.txt", system_path);
		rk_keys_load_file(path);
	}
	else {
		rk_keys_load_file("/mnt/SDCARD/.system/rk3326/keymap.txt");
	}
}

static inline __attribute__((unused)) int rk_key(int which) {
	rk_keys_init();
	return rk_keys[which];
}

#endif
