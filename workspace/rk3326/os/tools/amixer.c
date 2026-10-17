// Minimal "amixer" for the standalone V10 system (no alsa-utils).
// Talks to the kernel's ALSA control interface directly. Supports the
// subset NextUI and its scripts use:
//
//   amixer [-q] [-c N] sset  NAME VALUE    VALUE: number, N% or enum item
//   amixer [-q] [-c N] sget  NAME
//   amixer [-c N]                          list controls with their values
//   amixer [--invert] --hp-watch                      daemon: route audio to the
//                                          headphones while they are plugged
//                                          in, to the speaker otherwise
//
// Output of sget mimics alsa-utils closely enough for
//   grep "Item0: 'OFF'"   and   sed "s/.*Item0: '\(.*\)'.*/\1/p"

#include <dirent.h>
#include <errno.h>
#include <fcntl.h>
#include <linux/input.h>
#include <poll.h>
#include <stdio.h>
#include <stdlib.h>
#include <string.h>
#include <strings.h>
#include <sys/ioctl.h>
#include <unistd.h>
#include <sound/asound.h>

static int quiet = 0;

static int ctl_open(int card) {
	char path[64];
	snprintf(path, sizeof(path), "/dev/snd/controlC%d", card);
	int fd = open(path, O_RDWR);
	if (fd < 0 && !quiet) fprintf(stderr, "amixer: cannot open %s: %s\n", path, strerror(errno));
	return fd;
}

// all control ids of the card (caller frees)
static struct snd_ctl_elem_id *ctl_list(int fd, unsigned *count) {
	struct snd_ctl_elem_list list;
	memset(&list, 0, sizeof(list));
	if (ioctl(fd, SNDRV_CTL_IOCTL_ELEM_LIST, &list) < 0) return NULL;
	unsigned n = list.count;
	struct snd_ctl_elem_id *ids = calloc(n ? n : 1, sizeof(*ids));
	list.space = n;
	list.pids = ids;
	if (ioctl(fd, SNDRV_CTL_IOCTL_ELEM_LIST, &list) < 0) { free(ids); return NULL; }
	*count = list.used;
	return ids;
}

// find a mixer control by name; also accept "NAME Volume"/"NAME Switch" forms
static int ctl_find(int fd, const char *name, struct snd_ctl_elem_id *out) {
	unsigned n = 0;
	struct snd_ctl_elem_id *ids = ctl_list(fd, &n);
	if (!ids) return -1;
	int found = -1;
	const char *suffixes[] = { "", " Playback Volume", " Volume", " Playback Switch", " Switch", NULL };
	for (int s = 0; suffixes[s] && found < 0; s++) {
		char want[128];
		snprintf(want, sizeof(want), "%s%s", name, suffixes[s]);
		for (unsigned i = 0; i < n; i++) {
			if (strcasecmp((const char *)ids[i].name, want) == 0) { *out = ids[i]; found = 0; break; }
		}
	}
	free(ids);
	return found;
}

static int ctl_info(int fd, struct snd_ctl_elem_id *id, struct snd_ctl_elem_info *info) {
	memset(info, 0, sizeof(*info));
	info->id = *id;
	return ioctl(fd, SNDRV_CTL_IOCTL_ELEM_INFO, info);
}

static int enum_item_name(int fd, struct snd_ctl_elem_id *id, unsigned item, char *buf, size_t len) {
	struct snd_ctl_elem_info info;
	memset(&info, 0, sizeof(info));
	info.id = *id;
	info.value.enumerated.item = item;
	if (ioctl(fd, SNDRV_CTL_IOCTL_ELEM_INFO, &info) < 0) return -1;
	snprintf(buf, len, "%s", info.value.enumerated.name);
	return 0;
}

static void print_control(int fd, struct snd_ctl_elem_id *id) {
	struct snd_ctl_elem_info info;
	struct snd_ctl_elem_value val;
	if (ctl_info(fd, id, &info) < 0) return;
	memset(&val, 0, sizeof(val));
	val.id = info.id;
	if (ioctl(fd, SNDRV_CTL_IOCTL_ELEM_READ, &val) < 0) return;
	printf("Simple mixer control '%s',0\n", info.id.name);
	if (info.type == SNDRV_CTL_ELEM_TYPE_ENUMERATED) {
		printf("  Items:");
		for (unsigned i = 0; i < info.value.enumerated.items; i++) {
			char nm[64];
			if (enum_item_name(fd, id, i, nm, sizeof(nm)) == 0) printf(" '%s'", nm);
		}
		printf("\n");
		for (unsigned c = 0; c < info.count; c++) {
			char nm[64] = "";
			enum_item_name(fd, id, val.value.enumerated.item[c], nm, sizeof(nm));
			printf("  Item%u: '%s'\n", c, nm);
		}
	}
	else if (info.type == SNDRV_CTL_ELEM_TYPE_INTEGER) {
		long mn = info.value.integer.min, mx = info.value.integer.max;
		printf("  Limits: Playback %ld - %ld\n", mn, mx);
		const char *chn[] = { "Front Left", "Front Right" };
		for (unsigned c = 0; c < info.count; c++) {
			long v = val.value.integer.value[c];
			int pct = mx > mn ? (int)((v - mn) * 100 / (mx - mn)) : 0;
			printf("  %s: Playback %ld [%d%%]\n", info.count == 1 ? "Mono" : (c < 2 ? chn[c] : "Channel"), v, pct);
		}
	}
	else if (info.type == SNDRV_CTL_ELEM_TYPE_BOOLEAN) {
		for (unsigned c = 0; c < info.count; c++)
			printf("  Channel%u: [%s]\n", c, val.value.integer.value[c] ? "on" : "off");
	}
}

static int set_control(int fd, struct snd_ctl_elem_id *id, const char *arg) {
	struct snd_ctl_elem_info info;
	struct snd_ctl_elem_value val;
	if (ctl_info(fd, id, &info) < 0) return -1;
	memset(&val, 0, sizeof(val));
	val.id = info.id;
	if (info.type == SNDRV_CTL_ELEM_TYPE_ENUMERATED) {
		int item = -1;
		for (unsigned i = 0; i < info.value.enumerated.items; i++) {
			char nm[64];
			if (enum_item_name(fd, id, i, nm, sizeof(nm)) == 0 && strcasecmp(nm, arg) == 0) { item = i; break; }
		}
		if (item < 0) {
			char *end;
			long v = strtol(arg, &end, 10);
			if (*end || v < 0 || v >= (long)info.value.enumerated.items) return -1;
			item = (int)v;
		}
		for (unsigned c = 0; c < info.count; c++) val.value.enumerated.item[c] = item;
	}
	else if (info.type == SNDRV_CTL_ELEM_TYPE_INTEGER) {
		long mn = info.value.integer.min, mx = info.value.integer.max;
		char *end;
		double d = strtod(arg, &end);
		long v = (*end == '%') ? mn + (long)((mx - mn) * d / 100.0 + 0.5) : (long)d;
		if (v < mn) v = mn;
		if (v > mx) v = mx;
		for (unsigned c = 0; c < info.count; c++) val.value.integer.value[c] = v;
	}
	else if (info.type == SNDRV_CTL_ELEM_TYPE_BOOLEAN) {
		int on = !(strcasecmp(arg, "off") == 0 || strcmp(arg, "0") == 0 || strcasecmp(arg, "mute") == 0);
		for (unsigned c = 0; c < info.count; c++) val.value.integer.value[c] = on;
	}
	else return -1;
	return ioctl(fd, SNDRV_CTL_IOCTL_ELEM_WRITE, &val);
}

//////////////////////////////////////////////
// headphone watcher

#define PATH_CONTROL "Playback Path"

static int open_jack(void) {
	DIR *d = opendir("/dev/input");
	if (!d) return -1;
	struct dirent *e;
	int fd = -1;
	while ((e = readdir(d))) {
		if (strncmp(e->d_name, "event", 5)) continue;
		char p[300];
		snprintf(p, sizeof(p), "/dev/input/%s", e->d_name);
		int f = open(p, O_RDONLY);
		if (f < 0) continue;
		char name[256] = "";
		ioctl(f, EVIOCGNAME(sizeof(name)), name);
		if (strstr(name, "Headphone")) { fd = f; break; }
		close(f);
	}
	closedir(d);
	return fd;
}

static void route(int card, int headphones) {
	int fd = ctl_open(card);
	if (fd < 0) return;
	struct snd_ctl_elem_id id;
	if (ctl_find(fd, PATH_CONTROL, &id) == 0) {
		set_control(fd, &id, headphones ? "HP" : "SPK");
	}
	close(fd);
}

static int hp_invert = 0;

static int hp_watch(int card) {
	int fd = -1;
	for (int tries = 0; fd < 0 && tries < 20; tries++) {
		fd = open_jack();
		if (fd < 0) sleep(1);
	}
	if (fd < 0) { fprintf(stderr, "amixer: no headphone jack input found\n"); return 1; }
	unsigned long sw[(SW_MAX + 8 * sizeof(long)) / (8 * sizeof(long))];
	memset(sw, 0, sizeof(sw));
	ioctl(fd, EVIOCGSW(sizeof(sw)), sw);
	int in = (sw[SW_HEADPHONE_INSERT / (8 * sizeof(long))] >> (SW_HEADPHONE_INSERT % (8 * sizeof(long)))) & 1;
	fprintf(stderr, "hp-watch: start, jack switch=%d invert=%d -> %s\n", in, hp_invert, (in ^ hp_invert) ? "HP" : "SPK");
	route(card, in ^ hp_invert);
	struct input_event ev;
	while (read(fd, &ev, sizeof(ev)) == sizeof(ev)) {
		if (ev.type != EV_SW) continue;
		fprintf(stderr, "hp-watch: %ld.%06ld switch code=%d value=%d\n", (long)ev.time.tv_sec, (long)ev.time.tv_usec, ev.code, ev.value);
		if (ev.code == SW_HEADPHONE_INSERT) route(card, ev.value ^ hp_invert);
	}
	return 0;
}

//////////////////////////////////////////////

int main(int argc, char **argv) {
	int card = 0;
	int i = 1;
	for (; i < argc && argv[i][0] == '-'; i++) {
		if (!strcmp(argv[i], "-q") || !strcmp(argv[i], "--quiet")) quiet = 1;
		else if (!strcmp(argv[i], "-c") && i + 1 < argc) card = atoi(argv[++i]);
		else if (!strcmp(argv[i], "-M") || !strcmp(argv[i], "-R")) {}
		else if (!strcmp(argv[i], "--invert")) hp_invert = 1;
		else if (!strcmp(argv[i], "--hp-watch")) return hp_watch(card);
		else { fprintf(stderr, "amixer: unknown option %s\n", argv[i]); return 1; }
	}
	int fd = ctl_open(card);
	if (fd < 0) return 1;

	if (i >= argc || !strcmp(argv[i], "scontents") || !strcmp(argv[i], "contents")) {
		unsigned n = 0;
		struct snd_ctl_elem_id *ids = ctl_list(fd, &n);
		for (unsigned k = 0; ids && k < n; k++) print_control(fd, &ids[k]);
		free(ids);
		return 0;
	}
	const char *cmd = argv[i++];
	if (i >= argc) { fprintf(stderr, "amixer: missing control name\n"); return 1; }
	const char *name = argv[i++];
	struct snd_ctl_elem_id id;
	if (ctl_find(fd, name, &id) < 0) {
		if (!quiet) fprintf(stderr, "amixer: Unable to find simple control '%s',0\n", name);
		return 1;
	}
	if (!strcmp(cmd, "sget") || !strcmp(cmd, "get")) {
		print_control(fd, &id);
		return 0;
	}
	if (!strcmp(cmd, "sset") || !strcmp(cmd, "set")) {
		if (i >= argc) { fprintf(stderr, "amixer: missing value\n"); return 1; }
		if (set_control(fd, &id, argv[i]) < 0) {
			if (!quiet) fprintf(stderr, "amixer: invalid value '%s'\n", argv[i]);
			return 1;
		}
		if (!quiet) print_control(fd, &id);
		return 0;
	}
	fprintf(stderr, "amixer: unknown command %s\n", cmd);
	return 1;
}
