// rk3326 (Powkiddy V10 on ArkOS)
//
// Volume:     ALSA card 0 (rk817 codec), simple control 'Playback' (0-237)
// Brightness: /sys/class/backlight/backlight (0-255)
// Color temperature / contrast / saturation / exposure / display calibration
// have no hardware knobs on the RK3326 panel; values are stored so the UI
// keeps them, but nothing is applied yet.

#include <stdio.h>
#include <stdlib.h>
#include <unistd.h>
#include <fcntl.h>
#include <sys/mman.h>
#include <errno.h>
#include <sys/stat.h>
#include <string.h>
#include <dirent.h>

#include "displaycal.h"
#include "msettings.h"

///////////////////////////////////////

typedef struct SettingsV1 {
	int version; // future proofing
	int brightness;
	int colortemperature;
	int headphones;
	int speaker;
	int contrast;
	int saturation;
	int exposure;
	int unused[2]; // for future use
	// NOTE: doesn't really need to be persisted but still needs to be shared
	int jack;
	int audiosink; // AUDIO_SINK_*
	int displaycal_enabled;
	int displaycal_red_gain;
	int displaycal_green_gain;
	int displaycal_blue_gain;
} SettingsV1;

#define SETTINGS_VERSION 1
typedef SettingsV1 Settings;
static Settings DefaultSettings = {
	.version = SETTINGS_VERSION,
	.brightness = SETTINGS_DEFAULT_BRIGHTNESS,
	.colortemperature = SETTINGS_DEFAULT_COLORTEMP,
	.headphones = SETTINGS_DEFAULT_HEADPHONE_VOLUME,
	.speaker = SETTINGS_DEFAULT_VOLUME,
	.contrast = SETTINGS_DEFAULT_CONTRAST,
	.saturation = SETTINGS_DEFAULT_SATURATION,
	.exposure = SETTINGS_DEFAULT_EXPOSURE,
	.jack = 0,
	.audiosink = AUDIO_SINK_DEFAULT,
	.displaycal_enabled = 0,
	.displaycal_red_gain = DISPLAYCAL_DEFAULT_RED_GAIN,
	.displaycal_green_gain = DISPLAYCAL_DEFAULT_GREEN_GAIN,
	.displaycal_blue_gain = DISPLAYCAL_DEFAULT_BLUE_GAIN,
};
static Settings* settings;

#define SHM_KEY "/SharedSettings"
static char SettingsPath[256];
static int shm_fd = -1;
static int is_host = 0;
static int shm_size = sizeof(Settings);

#define BACKLIGHT_DIR "/sys/class/backlight"
#define MIXER_CONTROL "Playback"

int scaleBrightness(int);
int scaleColortemp(int);
int scaleContrast(int);
int scaleSaturation(int);
int scaleExposure(int);
int scaleVolume(int);

int getInt(char* path) {
	int i = 0;
	FILE *file = fopen(path, "r");
	if (file!=NULL) {
		if (fscanf(file, "%i", &i) != 1) i = 0;
		fclose(file);
	}
	return i;
}
void putFile(char* path, char* contents) {
	FILE* file = fopen(path, "w");
	if (file) {
		fputs(contents, file);
		fclose(file);
	}
}
void putInt(char* path, int value) {
	char buffer[16];
	snprintf(buffer, sizeof(buffer), "%d", value);
	putFile(path, buffer);
}

void touch(char* path) {
	close(open(path, O_RDWR|O_CREAT, 0777));
}
int exactMatch(char* str1, char* str2) {
	if (!str1 || !str2) return 0; // NULL isn't safe here
	size_t len1 = strlen(str1);
	if (len1!=strlen(str2)) return 0;
	return (strncmp(str1,str2,len1)==0);
}

// first device under /sys/class/backlight ("backlight" on the V10)
static const char* backlightPath(void) {
	static char path[256] = {0};
	if (path[0]) return path;
	DIR *dir = opendir(BACKLIGHT_DIR);
	if (dir) {
		struct dirent *entry;
		while ((entry = readdir(dir)) != NULL) {
			if (entry->d_name[0] == '.') continue;
			snprintf(path, sizeof(path), BACKLIGHT_DIR "/%s", entry->d_name);
			break;
		}
		closedir(dir);
	}
	if (!path[0]) snprintf(path, sizeof(path), BACKLIGHT_DIR "/backlight");
	return path;
}

static void loadSettings(void) {
	FILE *file = fopen(SettingsPath, "rb");
	if (!file) return;

	Settings saved;
	if (fread(&saved, sizeof(saved), 1, file) == 1 &&
		saved.version == SETTINGS_VERSION && fgetc(file) == EOF && !ferror(file)) {
		memcpy(settings, &saved, sizeof(saved));
	}
	fclose(file);
}

void InitSettings(void) {
	const char *userdata = getenv("USERDATA_PATH");
	snprintf(SettingsPath, sizeof(SettingsPath), "%s/msettings.bin", userdata ? userdata : "/tmp");

	shm_fd = shm_open(SHM_KEY, O_RDWR | O_CREAT | O_EXCL, 0644); // see if it exists
	if (shm_fd==-1 && errno==EEXIST) { // already exists
		shm_fd = shm_open(SHM_KEY, O_RDWR, 0644);
		settings = mmap(NULL, shm_size, PROT_READ | PROT_WRITE, MAP_SHARED, shm_fd, 0);
	}
	else { // host
		is_host = 1;
		if (ftruncate(shm_fd, shm_size) != 0)
			perror("msettings: ftruncate");
		settings = mmap(NULL, shm_size, PROT_READ | PROT_WRITE, MAP_SHARED, shm_fd, 0);

		memcpy(settings, &DefaultSettings, shm_size);
		loadSettings();
	}

	SetVolume(GetVolume());
	SetBrightness(GetBrightness());
}
int InitializedSettings(void) {
	return (settings != NULL);
}
void QuitSettings(void) {
	munmap(settings, shm_size);
	if (is_host) shm_unlink(SHM_KEY);
}
static inline void SaveSettings(void) {
	int fd = open(SettingsPath, O_CREAT|O_WRONLY|O_TRUNC, 0644);
	if (fd>=0) {
		if (write(fd, settings, shm_size) != shm_size)
			perror("msettings: write");
		close(fd);
		sync();
	}
}

///////// Getters exposed in public API

int GetBrightness(void) { return settings->brightness; } // 0-10
int GetColortemp(void) { return settings->colortemperature; } // 0-40
int GetVolume(void) { // 0-20
	if(settings->jack || settings->audiosink != AUDIO_SINK_DEFAULT)
		return settings->headphones;
	return settings->speaker;
}
int GetContrast(void) { return settings->contrast; }
int GetSaturation(void) { return settings->saturation; }
int GetExposure(void) { return settings->exposure; }
int GetDisplayCalEnabled(void) { return settings->displaycal_enabled; }
int GetDisplayCalRedGain(void) { return settings->displaycal_red_gain; }
int GetDisplayCalGreenGain(void) { return settings->displaycal_green_gain; }
int GetDisplayCalBlueGain(void) { return settings->displaycal_blue_gain; }
int GetJack(void) { return settings->jack; }
int GetAudioSink(void) { return settings->audiosink; }
int GetHDMI(void) { return 0; } // no HDMI on the V10

///////// Setters exposed in public API

void SetBrightness(int value) {
	SetRawBrightness(scaleBrightness(value));
	settings->brightness = value;
	SaveSettings();
}
void SetColortemp(int value) {
	settings->colortemperature = value;
	SaveSettings();
}
void SetContrast(int value) {
	settings->contrast = value;
	SaveSettings();
}
void SetSaturation(int value) {
	settings->saturation = value;
	SaveSettings();
}
void SetExposure(int value){
	settings->exposure = value;
	SaveSettings();
}
void SetDisplayCalEnabled(int is_enabled) {
	settings->displaycal_enabled = (is_enabled != 0);
	SaveSettings();
}
void SetDisplayCalRedGain(int value) {
	settings->displaycal_red_gain = DisplayCal_clampGainValue(value);
	SaveSettings();
}
void SetDisplayCalGreenGain(int value) {
	settings->displaycal_green_gain = DisplayCal_clampGainValue(value);
	SaveSettings();
}
void SetDisplayCalBlueGain(int value) {
	settings->displaycal_blue_gain = DisplayCal_clampGainValue(value);
	SaveSettings();
}
void SetVolume(int value) { // 0-20
	SetRawVolume(scaleVolume(value));
	if (settings->jack || settings->audiosink != AUDIO_SINK_DEFAULT)
		settings->headphones = value;
	else
		settings->speaker = value;
	SaveSettings();
}
void SetJack(int value) {
	settings->jack = value;
	SetVolume(GetVolume());
}
void SetAudioSink(int value) {
	settings->audiosink = value;
	SetVolume(GetVolume());
}
void SetHDMI(int value) { (void)value; }

///////// Platform specific scaling

// The rk817 'Playback' control is in dB steps (0-237, about 0.5 dB each), so
// raw percentages are far too quiet below ~80%. SetRawVolume uses amixer's
// perceptual mapping (-M) instead, which spreads 0-100 over the dB range.
int scaleVolume(int value) {
	if (value <= 0) return 0;
	if (value > 20) value = 20;
	return value * 5; // 5% .. 100% (mapped)
}

int scaleBrightness(int value) {
	switch (value) {
		case 0: return 4;
		case 1: return 8;
		case 2: return 14;
		case 3: return 22;
		case 4: return 34;
		case 5: return 50;
		case 6: return 72;
		case 7: return 100;
		case 8: return 140;
		case 9: return 190;
		case 10: return 255;
		default: return 72;
	}
}
int scaleColortemp(int value) { return value; }
int scaleContrast(int value) { return value; }
int scaleSaturation(int value) { return value; }
int scaleExposure(int value) { return value; }

///////// Platform specific, unscaled accessors

void SetRawBrightness(int val) { // 0 - 255
	char path[300];
	snprintf(path, sizeof(path), "%s/max_brightness", backlightPath());
	int max = getInt(path);
	if (max <= 0) max = 255;
	int raw = val * max / 255;
	if (val > 0 && raw == 0) raw = 1;
	snprintf(path, sizeof(path), "%s/brightness", backlightPath());
	putInt(path, raw);
}
void SetRawColortemp(int val) { (void)val; }

void SetRawVolume(int val) { // in: 0-100
	char cmd[128];
	snprintf(cmd, sizeof(cmd), "amixer -q -M -c 0 sset '" MIXER_CONTROL "' %d%% >/dev/null 2>&1", val);
	if (system(cmd) != 0) {
		// the control name differs on some kernels; fall back to the card's master
		snprintf(cmd, sizeof(cmd), "amixer -q -M -c 0 sset Master %d%% >/dev/null 2>&1", val);
		if (system(cmd) != 0) { /* nothing else to try */ }
	}
}

void SetRawContrast(int val) { (void)val; }
void SetRawSaturation(int val) { (void)val; }
void SetRawExposure(int val) { (void)val; }
void SetRawDisplayCal(int enabled, int red_gain, int green_gain, int blue_gain) {
	(void)enabled; (void)red_gain; (void)green_gain; (void)blue_gain;
}
