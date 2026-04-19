# Makefile — Mini Container Runtime
#
# Targets:
#   make          — build user-space engine and workload programs
#   make module   — build the kernel module
#   make all      — build everything (engine + module)
#   make ci       — CI-safe compile check (user-space only, no sudo/headers needed)
#   make clean    — remove all build artifacts
#   make load     — insert the kernel module (requires root)
#   make unload   — remove the kernel module (requires root)

# ── User-space build settings ─────────────────────────────────────────────
CC      := gcc
CFLAGS  := -Wall -Wextra -O2 -pthread
LDFLAGS := -pthread

# Binaries
ENGINE      := engine
CPU_HOG     := cpu_hog
CPU_TEST    := cpu_test
MEM_HOG     := memory_hog
MEM_TEST    := memory_test
IO_PULSE    := io_pulse
WORKLOAD_IO := workload_io

# Sources
ENGINE_SRC      := engine.c
CPU_HOG_SRC     := cpu_hog.c
CPU_SRC         := cpu_test.c
MEM_HOG_SRC     := memory_hog.c
MEM_SRC         := memory_test.c
IO_PULSE_SRC    := io_pulse.c
WORKLOAD_IO_SRC := workload_io.c

# ── Kernel module build settings ──────────────────────────────────────────
MODULE_NAME  := monitor
MODULE_SRCS  := monitor.c
KDIR         := /lib/modules/$(shell uname -r)/build
PWD          := $(shell pwd)

# ── Default target: user-space only ───────────────────────────────────────
.PHONY: default
default: $(ENGINE) $(CPU_HOG) $(CPU_TEST) $(MEM_HOG) $(MEM_TEST) $(IO_PULSE) $(WORKLOAD_IO)
	@echo "==> User-space binaries built. Run 'make module' to build the kernel module."

# Build everything
.PHONY: all
all: default module

# ── CI-safe target (GitHub Actions) ───────────────────────────────────────
# Builds only user-space binaries.  Does NOT require sudo, kernel headers,
# module loading, rootfs setup, or a running supervisor.
.PHONY: ci
ci: $(ENGINE) $(CPU_HOG) $(CPU_TEST) $(MEM_HOG) $(MEM_TEST) $(IO_PULSE) $(WORKLOAD_IO)
	@echo "==> CI: user-space compile check passed."
	@./$(ENGINE) 2>/dev/null || true

# ── engine ────────────────────────────────────────────────────────────────
$(ENGINE): $(ENGINE_SRC) monitor_ioctl.h
	$(CC) $(CFLAGS) -o $@ $< $(LDFLAGS)
	@echo "==> Built: $(ENGINE)"

# ── Workload programs ─────────────────────────────────────────────────────
$(CPU_HOG): $(CPU_HOG_SRC)
	$(CC) $(CFLAGS) -O2 -o $@ $<
	@echo "==> Built: $(CPU_HOG)"

$(CPU_TEST): $(CPU_SRC)
	$(CC) $(CFLAGS) -O2 -o $@ $<
	@echo "==> Built: $(CPU_TEST)"

$(MEM_HOG): $(MEM_HOG_SRC)
	$(CC) $(CFLAGS) -O0 -o $@ $<
	@echo "==> Built: $(MEM_HOG)"

$(MEM_TEST): $(MEM_SRC)
	$(CC) $(CFLAGS) -O0 -o $@ $<   # -O0 prevents dead-code elimination of memset
	@echo "==> Built: $(MEM_TEST)"

$(IO_PULSE): $(IO_PULSE_SRC)
	$(CC) $(CFLAGS) -O2 -o $@ $<
	@echo "==> Built: $(IO_PULSE)"

$(WORKLOAD_IO): $(WORKLOAD_IO_SRC)
	$(CC) $(CFLAGS) -O2 -o $@ $<
	@echo "==> Built: $(WORKLOAD_IO)"

# ── Kernel module ─────────────────────────────────────────────────────────
# The kernel build system is invoked in two stages:
#   1. kbuild reads this Makefile for 'obj-m' to know what to compile.
#   2. make recurses back into this directory with M= set.
obj-m += $(MODULE_NAME).o

.PHONY: module
module:
	@echo "==> Building kernel module $(MODULE_NAME).ko ..."
	$(MAKE) -C $(KDIR) M=$(PWD) modules
	@echo "==> Kernel module built: $(MODULE_NAME).ko"

# ── Load / unload ─────────────────────────────────────────────────────────
.PHONY: load
load: module
	@echo "==> Loading kernel module ..."
	sudo insmod $(MODULE_NAME).ko
	@echo "==> Module loaded. Check: ls -l /dev/container_monitor"
	@echo "==> dmesg tail:"
	@dmesg | tail -5

.PHONY: unload
unload:
	@echo "==> Unloading kernel module ..."
	sudo rmmod $(MODULE_NAME)
	@echo "==> Module unloaded."
	@dmesg | tail -5

# ── Clean ─────────────────────────────────────────────────────────────────
.PHONY: clean
clean:
	@echo "==> Cleaning user-space artifacts ..."
	rm -f $(ENGINE) $(CPU_HOG) $(CPU_TEST) $(MEM_HOG) $(MEM_TEST) $(IO_PULSE) $(WORKLOAD_IO)
	@echo "==> Cleaning kernel module artifacts ..."
	$(MAKE) -C $(KDIR) M=$(PWD) clean 2>/dev/null || true
	rm -f *.o *.ko *.mod *.mod.c *.symvers *.order .*.cmd
	rm -rf .tmp_versions
	@echo "==> Clean done."

# ── Help ──────────────────────────────────────────────────────────────────
.PHONY: help
help:
	@echo "Targets:"
	@echo "  make          Build engine + workload programs (user-space)"
	@echo "  make module   Build kernel module monitor.ko"
	@echo "  make all      Build everything"
	@echo "  make ci       CI-safe user-space compile check"
	@echo "  make load     sudo insmod monitor.ko"
	@echo "  make unload   sudo rmmod monitor"
	@echo "  make clean    Remove all build artifacts"
