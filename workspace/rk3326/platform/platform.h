// rk3326 (Powkiddy V10 running ArkOS)

#ifndef PLATFORM_H
#define PLATFORM_H

///////////////////////////////

#ifdef SDL
#	include "sdl.h"
#endif

#include "rk_keys.h"

///////////////////////////////

extern int panel_w;
extern int panel_h;
extern double panel_fps;

///////////////////////////////

#define BUTTON_UP		BUTTON_NA
#define BUTTON_DOWN		BUTTON_NA
#define BUTTON_LEFT		BUTTON_NA
#define BUTTON_RIGHT	BUTTON_NA

#define BUTTON_SELECT	BUTTON_NA
#define BUTTON_START	BUTTON_NA

#define BUTTON_A		BUTTON_NA
#define BUTTON_B		BUTTON_NA
#define BUTTON_X		BUTTON_NA
#define BUTTON_Y		BUTTON_NA

#define BUTTON_L1		BUTTON_NA
#define BUTTON_R1		BUTTON_NA
#define BUTTON_L2		BUTTON_NA
#define BUTTON_R2		BUTTON_NA
#define BUTTON_L3		BUTTON_NA
#define BUTTON_R3		BUTTON_NA
#define BUTTON_L4		BUTTON_NA
#define BUTTON_R4		BUTTON_NA

#define BUTTON_MENU		BUTTON_NA
#define BUTTON_MENU_ALT	BUTTON_NA
#define	BUTTON_POWER	116
#define	BUTTON_PLUS		BUTTON_NA
#define	BUTTON_MINUS	BUTTON_NA

///////////////////////////////
// Raw evdev codes. All runtime values from rk_keys.h so keymap.txt on the
// card can correct them without a rebuild.

#define CODE_UP			rk_key(RKK_UP)
#define CODE_DOWN		rk_key(RKK_DOWN)
#define CODE_LEFT		rk_key(RKK_LEFT)
#define CODE_RIGHT		rk_key(RKK_RIGHT)

#define CODE_SELECT		rk_key(RKK_SELECT)
#define CODE_START		rk_key(RKK_START)

#define CODE_A			rk_key(RKK_A)
#define CODE_B			rk_key(RKK_B)
#define CODE_X			rk_key(RKK_X)
#define CODE_Y			rk_key(RKK_Y)

#define CODE_L1			rk_key(RKK_L1)
#define CODE_R1			rk_key(RKK_R1)
#define CODE_L2			rk_key(RKK_L2)
#define CODE_R2			rk_key(RKK_R2)
#define CODE_L3			CODE_NA
#define CODE_R3			CODE_NA
#define CODE_L4			CODE_NA
#define CODE_R4			CODE_NA

// The V10 may have no dedicated MENU button. When MENU is -1 in the keymap,
// platform.c synthesizes MENU from SELECT+START held together.
#define CODE_MENU		rk_key(RKK_MENU)
#define CODE_POWER		rk_key(RKK_POWER)

#define CODE_PLUS		rk_key(RKK_PLUS)
#define CODE_MINUS		rk_key(RKK_MINUS)

///////////////////////////////
// SDL joystick indices: used for EXTERNAL pads only (USB / Bluetooth);
// the built-in pad is read through raw evdev. Xbox-style layout.

#define JOY_UP			JOY_NA
#define JOY_DOWN		JOY_NA
#define JOY_LEFT		JOY_NA
#define JOY_RIGHT		JOY_NA

#define JOY_SELECT		6
#define JOY_START		7

#define JOY_A			1
#define JOY_B			0
#define JOY_X			3
#define JOY_Y			2

#define JOY_L1			4
#define JOY_R1			5
#define JOY_L2			JOY_NA
#define JOY_R2			JOY_NA
#define JOY_L3			9
#define JOY_R3			10
#define JOY_L4			JOY_NA
#define JOY_R4			JOY_NA

#define JOY_MENU		8
#define JOY_POWER		JOY_NA
#define JOY_PLUS		JOY_NA
#define JOY_MINUS		JOY_NA

///////////////////////////////
// USER-ASSIGNABLE BUTTONS: the V10 has none.
#define BTN_FN1			BTN_NONE
#define BTN_FN2			BTN_NONE
#define BTN_FN3			BTN_NONE
#define BTN_FN1_NAME	""
#define BTN_FN2_NAME	""
#define BTN_FN3_NAME	""

///////////////////////////////

#define AXIS_L2			2	// external pads only
#define AXIS_R2			5
#define AXIS_LX			0
#define AXIS_LY			1
#define AXIS_RX			3
#define AXIS_RY			4

///////////////////////////////

#define BTN_RESUME			BTN_X
#define BTN_SLEEP 			BTN_POWER
#define BTN_WAKE 			BTN_POWER
#define BTN_MOD_VOLUME 		BTN_NONE
#define BTN_MOD_BRIGHTNESS 	BTN_MENU
#define BTN_MOD_COLORTEMP 	BTN_SELECT
#define BTN_MOD_PLUS 		BTN_PLUS
#define BTN_MOD_MINUS 		BTN_MINUS

///////////////////////////////

// No HDMI: leave HAS_HDMI undefined so defines.h maps HDMI_* to FIXED_*.

// 480x320 panel at 1x: logical canvas 480x320 (larger than the 320x240
// logical canvas of the 640x480 devices at 2x), with the @1x assets.
#define FIXED_SCALE 	1
#define FIXED_WIDTH		panel_w
#define FIXED_HEIGHT	panel_h
#define FIXED_BPP		2
#define FIXED_DEPTH		(FIXED_BPP * 8)
#define FIXED_PITCH		(FIXED_WIDTH * FIXED_BPP)
#define FIXED_SIZE		(FIXED_PITCH * FIXED_HEIGHT)

///////////////////////////////

// Rows above the button hints: (320 - 2*PADDING - PILL_SIZE) / PILL_SIZE
// = (320 - 20 - 30) / 30 = 9 rows.
#define MAIN_ROW_COUNT 9
#define QUICK_SWITCHER_COUNT 3
#define PADDING 10

///////////////////////////////

#define SDCARD_PATH "/mnt/SDCARD"
#define MUTE_VOLUME_RAW 0

#define SCREEN_FPS panel_fps

// ArkOS's stock SDL2 may pick a float format when allowed to; keep the device
// at the stereo S16 the audio callback writes (SDL converts if it must).
#define SND_ALLOWED_CHANGES (SDL_AUDIO_ALLOW_FREQUENCY_CHANGE | SDL_AUDIO_ALLOW_SAMPLES_CHANGE)
// Uncomment to log an audio heartbeat (callback/sample stats) every ~3 s.
// #define SND_DEBUG_HEARTBEAT 1

///////////////////////////////

#endif
