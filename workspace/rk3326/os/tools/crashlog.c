// LD_PRELOAD helper for NextUI OS test builds: when a program crashes,
// write the signal, faulting address, registers, a backtrace and the
// process's memory map to stderr (which the launch scripts log), then
// crash as usual.

#define _GNU_SOURCE
#include <execinfo.h>
#include <fcntl.h>
#include <signal.h>
#include <stdio.h>
#include <string.h>
#include <ucontext.h>
#include <unistd.h>

static void out(const char *s) { write(2, s, strlen(s)); }

static void handler(int sig, siginfo_t *si, void *uc_) {
	ucontext_t *uc = uc_;
	char buf[256];
	char exe[128] = "";
	ssize_t n = readlink("/proc/self/exe", exe, sizeof(exe) - 1);
	if (n > 0) exe[n] = 0;
	snprintf(buf, sizeof(buf), "\n=== crashlog: %s got signal %d (code %d) at address %p\n",
		exe, sig, si->si_code, si->si_addr);
	out(buf);
#if defined(__aarch64__)
	snprintf(buf, sizeof(buf), "pc=%llx lr=%llx sp=%llx\n",
		(unsigned long long)uc->uc_mcontext.pc,
		(unsigned long long)uc->uc_mcontext.regs[30],
		(unsigned long long)uc->uc_mcontext.sp);
	out(buf);
	for (int i = 0; i < 30; i += 3) {
		snprintf(buf, sizeof(buf), "x%-2d=%016llx x%-2d=%016llx x%-2d=%016llx\n",
			i, (unsigned long long)uc->uc_mcontext.regs[i],
			i + 1, (unsigned long long)uc->uc_mcontext.regs[i + 1],
			i + 2, (unsigned long long)uc->uc_mcontext.regs[i + 2]);
		out(buf);
	}
#endif
	out("--- backtrace\n");
	void *frames[48];
	int count = backtrace(frames, 48);
	backtrace_symbols_fd(frames, count, 2);
	out("--- maps\n");
	int fd = open("/proc/self/maps", O_RDONLY);
	if (fd >= 0) {
		ssize_t r;
		while ((r = read(fd, buf, sizeof(buf))) > 0) write(2, buf, r);
		close(fd);
	}
	out("=== crashlog end\n");
	signal(sig, SIG_DFL);
	raise(sig);
}

__attribute__((constructor)) static void crashlog_init(void) {
	struct sigaction sa;
	memset(&sa, 0, sizeof(sa));
	sa.sa_sigaction = handler;
	sa.sa_flags = SA_SIGINFO | SA_RESETHAND | SA_ONSTACK;
	static char altstack[65536];
	stack_t ss = { .ss_sp = altstack, .ss_size = sizeof(altstack), .ss_flags = 0 };
	sigaltstack(&ss, NULL);
	int sigs[] = { SIGSEGV, SIGBUS, SIGILL, SIGFPE, SIGABRT };
	for (unsigned i = 0; i < sizeof(sigs) / sizeof(sigs[0]); i++) sigaction(sigs[i], &sa, NULL);
}
