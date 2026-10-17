// Empty stand-in for libcap.so.2. dArkOS's libudev lists libcap as a
// dependency but uses none of its functions; without some libcap.so.2 the
// library fails to load, SDL2 cannot use udev and crashes during video setup.
void nextui_libcap_stub(void) {}
