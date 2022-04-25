################################################################################
# Paths to git projects and various binaries
################################################################################
CCACHE ?= $(shell which ccache) # Don't remove this comment (space is needed)

ROOT				?= $(PWD)
OUT_PATH			?= $(ROOT)/out

BINARIES_PATH			?= $(ROOT)/out/bin
BUILD_PATH			?= $(ROOT)/build
BUSYBOX_PATH			?= $(ROOT)/busybox
FUN_SIM_PATH			?= $(ROOT)/fun_sim
FUN_SIM_APP_PATH		?= $(ROOT)/fun_sim_app
GOOGLETEST_PATH			?= $(ROOT)/googletest
GOOGLETEST_OUT			?= $(GOOGLETEST_PATH)/build
GOOGLETEST_LIB_DIR		?= $(GOOGLETEST_OUT)/lib
GOOGLETEST_LIB			?= $(GOOGLETEST_LIB_DIR)/libgtest.a
GOOGLETEST_INCLUDE_DIR		?= $(GOOGLETEST_PATH)/googletest/include
LINUX_PATH			?= $(ROOT)/linux
MODULE_OUTPUT			?= $(OUT_PATH)/kernel_modules
NTL_PATH			?= $(ROOT)/ntl
NTL_ARM64_PREBUILT_PATH		?= $(BUILD_PATH)/prebuilt/arm64/ntl-v11.5.1
GMP_ARM64_PREBUILT_PATH		?= $(BUILD_PATH)/prebuilt/arm64/gmp-6.2.1
QEMU_PATH			?= $(ROOT)/qemu
UDMABUF_PATH			?= $(ROOT)/udmabuf

DEBUG				?= n
CCACHE_DIR			?= $(HOME)/.ccache

# Configuration
ARCH				?=
CFG_ENABLE_NTL_TESTS		?= n
CFG_ENABLE_GTESTS		?= y

CROSS_COMPILE_PREFIX		?=
ifeq ($(ARCH),arm64)
	# Use x86 gcc by default
	CROSS_COMPILE_PREFIX		:= aarch64-linux-gnu-

	# Enable VIRT FS when using Arm64 by default
	QEMU_VIRTFS_ENABLE ?= y
endif

################################################################################
# Sanity checks
################################################################################
# This project and Makefile is based around running it from the root folder. So
# to avoid people making mistakes running it from the "build" folder itself add
# a sanity check that we're indeed are running it from the root.
ifeq ($(wildcard ./.repo), )
$(error Make should be run from the root of the project!)
endif

################################################################################
# Targets
################################################################################
TARGET_DEPS := build busybox fun-sim linux qemu

ifeq ($(CFG_ENABLE_GTESTS),y)
TARGET_DEPS += googletest
endif

.PHONY: all
all: $(TARGET_DEPS)

# build each sub project sequencially but still enable parallel builds in the 
# subprojects.
.NOTPARALLEL:

include $(BUILD_PATH)/toolchain.mk

################################################################################
# Busybox
################################################################################
BUSYBOX_OUT=$(OUT_PATH)/busybox
INITRAMFS_OUT=$(OUT_PATH)/initramfs
INIT=$(INITRAMFS_OUT)/busybox/init
PROFILE=$(INITRAMFS_OUT)/busybox/.profile
SETUP=$(INITRAMFS_OUT)/busybox/bin/setup.sh

busybox-defconfig:
	rm -rf $(BUSYBOX_OUT)
	mkdir -pv $(BUSYBOX_OUT)
	$(MAKE) -C $(BUSYBOX_PATH) O=$(BUSYBOX_OUT) defconfig
	sed -i 's/# CONFIG_STATIC is not set/CONFIG_STATIC=y/g' $(BUSYBOX_OUT)/.config

busybox-build: busybox-defconfig
	$(MAKE) -C $(BUSYBOX_OUT) \
		CROSS_COMPILE="$(CCACHE)$(CROSS_COMPILE_PREFIX)" \
		install

busybox-initramfs: busybox-build udmabuf fun-sim-app
	rm -rf $(INITRAMFS_OUT)
	mkdir -p $(INITRAMFS_OUT)/busybox/bin
	mkdir -p $(INITRAMFS_OUT)/busybox/sbin
	mkdir -p $(INITRAMFS_OUT)/busybox/etc
	mkdir -p $(INITRAMFS_OUT)/busybox/proc
	mkdir -p $(INITRAMFS_OUT)/busybox/sys
	mkdir -p $(INITRAMFS_OUT)/busybox/usr
	mkdir -p $(INITRAMFS_OUT)/busybox/usr/bin
	mkdir -p $(INITRAMFS_OUT)/busybox/usr/sbin
	mkdir -p $(INITRAMFS_OUT)/busybox/lib/modules
	cp -av $(BUSYBOX_OUT)/_install/* $(INITRAMFS_OUT)/busybox
	cp -av $(UDMABUF_PATH)/u-dma-buf.ko $(INITRAMFS_OUT)/busybox/lib/modules
	cp -av $(FUN_SIM_APP_PATH)/fun_sim_app $(INITRAMFS_OUT)/busybox/usr/bin

busybox-init: busybox-initramfs
	echo "alias ll='ls -all'" > $(PROFILE)
	echo "#!/bin/sh"  > $(SETUP)
	echo "insmod /lib/modules/u-dma-buf.ko dma_mask_bit=64 udmabuf0=1048576 udmabuf1=1048576" >> $(SETUP)
	echo "echo '1234 11e8' > /sys/bus/pci/drivers/uio_pci_generic/new_id" >> $(SETUP)
	chmod +x $(SETUP)
	echo "#!/bin/sh"  > $(INIT)
	echo "mount -t proc none /proc" >> $(INIT)
	echo "mount -t sysfs none /sys" >> $(INIT)
	echo "mount -t devtmpfs none /dev" >> $(INIT)
	echo "echo -e \"\\\nBoot took \$$(cut -d' ' -f1 /proc/uptime) seconds\\\n\"" >> $(INIT)
ifeq ($(QEMU_VIRTFS_ENABLE),y)
	echo "alias fsa='echo Running fun_sim_app locally && ./host/fun_sim_app/fun_sim_app'" >> $(PROFILE)
	echo "mkdir /host" >> $(INIT)
	echo "mount -t 9p -o trans=virtio host /host" >> $(INIT)
endif
	echo "exec /bin/sh +m -l" >> $(INIT)
	chmod +x $(INIT)

busybox-cpio: busybox-init
	cd $(INITRAMFS_OUT)/busybox && find . -print0 | \
		cpio --null -ov --format=newc | \
		gzip -9 > $(OUT_PATH)/initramfs.cpio.gz

busybox: busybox-cpio

busybox-clean: udmabuf-clean fun-sim-app-clean
	rm -rf $(BUSYBOX_OUT) $(INITRAMFS_OUT)
	cd $(BUILD_PATH) && git clean -xdf


################################################################################
# NTL
################################################################################
ntl-configure:
	if [ ! -f $(NTL_PATH)/include/NTL/config.h ]; then \
		cd $(NTL_PATH)/src && ./configure PREFIX=$(OUT_PATH)/ntl; \
	fi

ntl-tests: ntl-compile
ifeq ($(CFG_ENABLE_NTL_TESTS),y)
	$(MAKE) -C $(NTL_PATH)/src check
endif

ntl-install: ntl-compile
	$(MAKE) -C $(NTL_PATH)/src install

ntl-compile: ntl-configure
	$(MAKE) -C $(NTL_PATH)/src CXX="$(CCACHE)g++"

ntl: ntl-configure ntl-tests ntl-install ntl-compile

ntl-clean:
	rm -rf $(OUT_PATH)/ntl
	cd $(NTL_PATH) && git clean -xdf

################################################################################
# Googletest
################################################################################
$(GOOGLETEST_LIB): googletest/CMakeLists.txt
	@echo "\nBuilding Googletest\n"
	$(VB)mkdir -p $(GOOGLETEST_OUT);
	$(VB)cd $(GOOGLETEST_OUT); \
		cmake -DCMAKE_C_COMPILER="$(CROSS_COMPILE_PREFIX)gcc" \
		-DCMAKE_CXX_COMPILER="$(CROSS_COMPILE_PREFIX)g++" .. && \
		$(MAKE)

googletest: $(GOOGLETEST_LIB)

googletest-clean:
	rm -rf $(GOOGLETEST_OUT)

################################################################################
# fun_sim
################################################################################
ifeq ($(ARCH),arm64)
fun-sim:
	cd $(FUN_SIM_PATH) && export NTL_PATH=$(NTL_ARM64_PREBUILT_PATH) && \
		export GMP_PATH=$(GMP_ARM64_PREBUILT_PATH) && \
		export CROSS_COMPILE=$(CROSS_COMPILE_PREFIX) && \
		export GOOGLETEST_LIB_DIR=$(GOOGLETEST_LIB_DIR) && \
		export GOOGLETEST_INCLUDE_DIR=$(GOOGLETEST_INCLUDE_DIR) && \
		$(MAKE)
else
fun-sim: ntl
	cd $(FUN_SIM_PATH) && export NTL_PATH=$(OUT_PATH)/ntl/ && \
		export GOOGLETEST_LIB_DIR=$(GOOGLETEST_LIB_DIR) && \
		export GOOGLETEST_INCLUDE_DIR=$(GOOGLETEST_INCLUDE_DIR) && \
		$(MAKE)
endif

ifeq ($(ARCH),arm64)
fun-sim-clean:
else
fun-sim-clean: ntl-clean
endif
	cd $(FUN_SIM_PATH) && $(MAKE) clean

################################################################################
# fun_sim_app
################################################################################
.PHONY: fun-sim-app
fun-sim-app:
	cd $(FUN_SIM_APP_PATH) && \
	$(CCACHE)$(CROSS_COMPILE_PREFIX)gcc -static -o fun_sim_app fun_sim_app.c

.PHONY: fun-sim-app-clean
fun-sim-app-clean:
	cd $(FUN_SIM_APP_PATH) && rm -f fun_sim_app

################################################################################
# Linux kernel
################################################################################
ifeq ($(ARCH),arm64)
LINUX_DEFCONFIG_COMMON_ARCH := arm64
LINUX_DEFCONFIG_COMMON_FILES := \
	$(LINUX_PATH)/arch/arm64/configs/defconfig
else
LINUX_DEFCONFIG_COMMON_ARCH := x86
LINUX_DEFCONFIG_COMMON_FILES := \
	$(LINUX_PATH)/arch/x86/configs/x86_64_defconfig
endif

LINUX_COMMON_FLAGS ?= LOCALVERSION=
LINUX_CLEAN_COMMON_FLAGS += ARCH=$(LINUX_DEFCONFIG_COMMON_ARCH)

linux: linux-common
	mkdir -p $(BINARIES_PATH)
	#ln -sf $(LINUX_PATH)/arch/arm64/boot/Image $(BINARIES_PATH)

.PHONY: linux-common
linux-common: linux-defconfig
	$(MAKE) -C $(LINUX_PATH) CROSS_COMPILE="$(CCACHE)$(CROSS_COMPILE_PREFIX)" $(LINUX_COMMON_FLAGS)

$(LINUX_PATH)/.config: $(LINUX_DEFCONFIG_COMMON_FILES)
	cd $(LINUX_PATH) && \
		ARCH=$(LINUX_DEFCONFIG_COMMON_ARCH) \
		CROSS_COMPILE="$(CCACHE)$(CROSS_COMPILE_PREFIX)" \
		scripts/kconfig/merge_config.sh $(LINUX_DEFCONFIG_COMMON_FILES) \
		$(BUILD_PATH)/kernel.conf

linux-defconfig: $(LINUX_PATH)/.config

linux-modules: linux
	$(MAKE) -C $(LINUX_PATH) CROSS_COMPILE="$(CCACHE)$(CROSS_COMPILE_PREFIX)" $(LINUX_COMMON_FLAGS) modules
	$(MAKE) -C $(LINUX_PATH) $(LINUX_COMMON_FLAGS) INSTALL_MOD_STRIP=1 INSTALL_MOD_PATH=$(MODULE_OUTPUT) modules_install

linux-defconfig-clean: linux-defconfig-clean

.PHONY: linux-defconfig-clean
linux-defconfig-clean:
	rm -f $(LINUX_PATH)/.config

.PHONY: linux-clean
linux-clean: linux-defconfig-clean
	$(MAKE) -C $(LINUX_PATH) $(LINUX_CLEAN_COMMON_FLAGS) clean

.PHONY: linux-cleaner
linux-cleaner: linux-defconfig-clean
	$(MAKE) -C $(LINUX_PATH) $(LINUX_CLEANER_COMMON_FLAGS) distclean

################################################################################
# Linux kernel module: udmabuf
################################################################################

.PHONY: udmabuf
udmabuf: linux
	cd $(UDMABUF_PATH) && \
	$(MAKE) KERNEL_SRC=$(LINUX_PATH)

.PHONY: udmabuf-clean
udmabuf-clean:
	cd $(UDMABUF_PATH) && \
	$(MAKE) KERNEL_SRC=$(LINUX_PATH) clean

#################################################################################
# QEMU
#################################################################################
QEMU_TARGET ?= x86_64-softmmu
ifeq ($(ARCH),arm64)
	QEMU_TARGET := aarch64-softmmu
endif

qemu-configure:
	cd $(QEMU_PATH) && \
	./configure --target-list=$(QEMU_TARGET) \
		--cc="$(CCACHE)gcc" \
		--extra-cflags="-Wno-error" \
		--enable-virtfs

# Helper target to run configure if config-host.mak doesn't exist or has been
# updated. This avoid re-run configure every time we run the "qemu" target.
$(QEMU_PATH)/config-host.mak:
	$(MAKE) qemu-configure

# Need a PHONY target here, otherwise it mixes it with the folder name "qemu".
.PHONY: qemu
qemu: $(QEMU_PATH)/config-host.mak
	$(MAKE) -C $(QEMU_PATH)

qemu-create-env-image:
	@if [ ! -f $(QEMU_ENV) ]; then \
		echo "Creating envstore image ..."; \
		qemu-img create -f raw $(QEMU_ENV) 64M; \
	fi

qemu-help:
	@echo "\n================================================================================"
	@echo "= QEMU                                                                         ="
	@echo "================================================================================"
	@echo "Mount host filesystem in Buildroot"
	@echo "  Run this at the shell in Buildroot:"
	@echo "    mkdir /host && mount -t 9p -o trans=virtio host /host"
	@echo "  Once done, you can access the host PC's files"

.PHONY: qemu-clean
qemu-clean:
	cd $(QEMU_PATH) && git clean -xdf && \
		git submodule foreach git clean -xdf

#################################################################################
# Helper targets
#################################################################################
$(OUT_PATH):
	mkdir -p $@


#################################################################################
# Run targets
#################################################################################
.PHONY: ctxtAdd
ctxtAdd: fun-sim
	cd $(FUN_SIM_PATH) && ./build/examples/ctxtAdd

QEMU_BIN		?= $(QEMU_PATH)/build/qemu-system-x86_64
QEMU_CONSOLE		?= -append "console=ttyS0 cma=2080MG"
QEMU_KERNEL		?= -kernel $(LINUX_PATH)/arch/x86_64/boot/bzImage
QEMU_INITRD		?= -initrd $(OUT_PATH)/initramfs.cpio.gz
QEMU_ARGS		?= -nographic \
			   -m 4096 \
			   -device edu,dma_mask=0xffffffffffffffff
QEMU_ENV		?= $(OUT_PATH)/envstore.img

ifeq ($(ARCH),arm64)
QEMU_BIN		:= $(QEMU_PATH)/build/qemu-system-aarch64
QEMU_CONSOLE		:= -append "console=ttyAMA0 cma=2080MG"
QEMU_KERNEL		:= -kernel $(LINUX_PATH)/arch/arm64/boot/Image.gz
QEMU_ARGS		+= -smp 1 \
			   -machine virt \
			   -cpu cortex-a57 \
			   -d unimp \
			   -no-acpi \
			   -netdev user,id=vmnic,tftp=$(ROOT)/out,bootfile=uEnv.txt \
			   -device virtio-net-device,netdev=vmnic
QEMU_VIRTFS_HOST_DIR	?= $(CURDIR)

ifeq ($(QEMU_VIRTFS_ENABLE),y)
QEMU_EXTRA_ARGS +=\
	-fsdev local,id=fsdev0,path=$(QEMU_VIRTFS_HOST_DIR),security_model=none \
	-device virtio-9p-device,fsdev=fsdev0,mount_tag=host
endif

ifeq ($(ENVSTORE),y)
QEMU_EXTRA_ARGS +=\
	-drive if=pflash,format=raw,index=1,file=envstore.img
endif
endif # ARCH=arm64

# Enable GDB debugging
ifeq ($(GDB),y)
QEMU_EXTRA_ARGS	+= -s -S
endif

.PHONY: run-kernel
run-kernel:
	cd $(OUT_PATH) && \
	$(QEMU_BIN) \
		$(QEMU_ARGS) \
		$(QEMU_KERNEL) \
		$(QEMU_INITRD) \
                $(QEMU_CONSOLE) \
		$(QEMU_EXTRA_ARGS)


################################################################################
# Clean
################################################################################
.PHONY: clean
clean: busybox-clean fun-sim-clean googletest-clean linux-clean qemu-clean

.PHONY: distclean
distclean: clean
	rm -rf $(OUT_PATH)
