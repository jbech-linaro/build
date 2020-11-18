# Todo
# 3. Enable ordinary boot w/o tftp
# 6. Run Image and/or Image.gz
# 8. Load and pass QEMU DTB
# 9. Modify DTB
# 10. Create boot.scr or uboot.env

################################################################################
# Paths to git projects and various binaries
################################################################################
CCACHE ?= $(shell which ccache) # Don't remove this comment (space is needed)

ROOT				?= $(PWD)

BUILD_PATH			?= $(ROOT)/build
BR_PATH				?= $(ROOT)/buildroot
LINUX_PATH			?= $(ROOT)/linux
OUT_PATH			?= $(ROOT)/out
QEMU_PATH			?= $(ROOT)/qemu
U-BOOT_PATH			?= $(ROOT)/u-boot
MKIMAGE_PATH			?= $(U-BOOT_PATH)/tools

DEBUG				?= n
PLATFORM			?= qemu

# Binaries
BIOS				?= $(U-BOOT_PATH)/u-boot.bin
CONFIG_FRAGMENT			?= $(BUILD_PATH)/.config-fragment
KERNEL				?= $(LINUX_PATH)/arch/arm64/boot/Image
#KERNEL				?= $(LINUX_PATH)/arch/arm64/boot/Image.gz
KERNEL_UIMAGE			?= $(OUT_PATH)/uImage
LINUX_VMLINUX			?= $(LINUX_PATH)/vmlinux
QEMU_BIN			?= $(QEMU_PATH)/aarch64-softmmu/qemu-system-aarch64
QEMU_DTB			?= $(OUT_PATH)/qemu-aarch64.dtb
QEMU_ENV			?= $(OUT_PATH)/envstore.img
ROOTFS				?= $(OUT_PATH)/rootfs.cpio.gz
UROOTFS				?= $(OUT_PATH)/urootfs.cpio.gz

################################################################################
# Targets
################################################################################
.PHONY: all
all: linux qemu uboot

include toolchain.mk

#################################################################################
## Buildroot
#################################################################################
BR_DEFCONFIG_FILES := $(BUILD_PATH)/br_kconfigs/br_qemu_aarch64_virt.conf
$(BR_PATH)/.config:
	cd $(BR_PATH) && \
	support/kconfig/merge_config.sh \
	$(BR_DEFCONFIG_FILES)

# Note that the AARCH64_PATH here is necessary and it's used in the
# br_kconfigs/br_qemu_aarch64_virt.conf file where a variable is used to find
# and set the # correct toolchain to use.
.PHONY: buildroot
buildroot: $(BR_PATH)/.config
	$(MAKE) -C $(BR_PATH) \
		AARCH64_PATH=$(AARCH64_PATH) \
		BR2_CCACHE_DIR="$(CCACHE_DIR)"

.PHONY: buildroot-clean
buildroot-clean:
	cd $(BR_PATH) && git clean -xdf

################################################################################
# Linux kernel
################################################################################
$(LINUX_PATH)/.config:
	$(MAKE) -C $(LINUX_PATH) \
		ARCH=arm64 \ 
		CROSS_COMPILE="$(CCACHE)$(AARCH64_CROSS_COMPILE)" \
		defconfig

.PHONY: linux
linux: $(LINUX_PATH)/.config
	$(MAKE) -C $(LINUX_PATH) \
		ARCH=arm64 CROSS_COMPILE="$(CCACHE)$(AARCH64_CROSS_COMPILE)" \
		Image.gz dtbs

.PHONY: linux-menuconfig
linux-menuconfig: $(LINUX_PATH)/.config
	$(MAKE) -C $(LINUX_PATH) ARCH=arm64 menuconfig

.PHONY: linux-clean
linux-clean:
	cd $(LINUX_PATH) && git clean -xdf

.PHONY: linux-cscope
linux-cscope:
	$(MAKE) -C $(LINUX_PATH) cscope

################################################################################
# QEMU
################################################################################
qemu-configure:
	cd $(QEMU_PATH) && \
	./configure --target-list=aarch64-softmmu \
		--cc="$(CCACHE)gcc" \
		--extra-cflags="-Wno-error" \
		--enable-virtfs

.PHONY: qemu
qemu: qemu-configure
	make -C $(QEMU_PATH)

.PHONY: qemu-clean
qemu-clean:
	cd $(QEMU_PATH) && git clean -xdf

dump-dtb:
	$(QEMU_BIN) -machine virt \
		-cpu cortex-a57 \
		-machine dumpdtb=$(QEMU_DTB)

create-env-image:
	@if [ ! -f $(QEMU_ENV) ]; then \
		echo "Creating envstore image ..."; \
		qemu-img create -f raw $(QEMU_ENV) 64M; \
	fi

################################################################################
# mkimage
################################################################################
uboot-images: uimage urootfs

KERNEL_ENTRY	?= 0x40400000
KERNEL_LOADADDR ?= 0x40400000
ROOTFS_ENTRY	?= 0x44000000
ROOTFS_LOADADDR ?= 0x44000000

# TODO: The linux.bin thing probably isn't necessary.
.PHONY: uimage
uimage: $(KERNEL)
	mkdir -p $(OUT_PATH) && \
	${AARCH64_CROSS_COMPILE}objcopy -O binary -R .note -R .comment -S $(LINUX_PATH)/vmlinux $(OUT_PATH)/linux.bin && \
	$(MKIMAGE_PATH)/mkimage -A arm64 \
				-O linux \
				-T kernel \
				-C none \
				-a $(KERNEL_LOADADDR) \
				-e $(KERNEL_ENTRY) \
				-n "Linux kernel" \
				-d $(OUT_PATH)/linux.bin $(KERNEL_UIMAGE)

.PHONY: urootfs
urootfs:
	mkdir -p $(OUT_PATH) && \
	$(MKIMAGE_PATH)/mkimage -A arm64 \
				-T ramdisk \
				-C gzip \
				-a $(ROOTFS_LOADADDR) \
				-e $(ROOTFS_ENTRY) \
				-n "Root files system" \
				-d $(ROOTFS) $(UROOTFS)


################################################################################
# U-boot
################################################################################
$(UBOOT_PATH)/.config:
	$(MAKE) -C $(UBOOT_PATH) \
		CROSS_COMPILE="$(CCACHE)$(AARCH64_CROSS_COMPILE)" \
		qemu_arm64_defconfig

.PHONY: uboot
uboot: $(UBOOT_PATH)/.config
	mkdir -p $(OUT_PATH) && \
	$(MAKE) -C $(UBOOT_PATH) \
		CROSS_COMPILE="$(CCACHE)$(AARCH64_CROSS_COMPILE)" && \
	ln -sf $(BIOS) $(OUT_PATH)/

.PHONY: uboot-menuconfig
uboot-menuconfig: uboot-defconfig
	$(MAKE) -C $(UBOOT_PATH) \
		CROSS_COMPILE="$(CCACHE)$(AARCH64_CROSS_COMPILE)" \
		menuconfig

.PHONY: uboot-clean
uboot-clean:
	cd $(UBOOT_PATH) && git clean -xdf

.PHONY: uboot-cscope
uboot-cscope:
	$(MAKE) -C $(UBOOT_PATH) cscope

################################################################################
# Run targets
################################################################################
QEMU_BIOS	?= -bios u-boot.bin
QEMU_KERNEL	?= -kernel Image.gz

QEMU_ARGS	+= -nographic \
		   -smp 1 \
		   -machine virt \
		   -cpu cortex-a57 \
		   -d unimp \
		   -m 128 \
		   -no-acpi

ifeq ($(GDB),y)
QEMU_ARGS	+= -s -S

# For convenience, setup path to gdb
$(shell ln -sf $(AARCH64_PATH)/bin/aarch64-none-linux-gnu-gdb $(ROOT)/gdb)
endif

# Target to run U-boot and Linux kernel where U-boot is the bios and the kernel
# is pulled from the block device.
.PHONY: run
run: create-env-image
	cd $(OUT_PATH) && \
	$(QEMU_BIN) \
		$(QEMU_ARGS) \
		$(QEMU_BIOS) \
		-semihosting-config enable,target=native \
                -append 'console=ttyAMA0,38400 keep_bootcon root=/dev/vda2'


# Target to run U-boot and Linux kernel where U-boot is the bios and the kernel
# is pulled from tftp.
#
# To then boot using DHCP do:
#  setenv serverip <host-computer-ip>
#  tftp 0x40400000 uImage
.PHONY: run-netboot
run-netboot: create-env-image uimage
	cd $(OUT_PATH) && \
	$(QEMU_BIN) \
		$(QEMU_ARGS) \
		$(QEMU_BIOS) \
		-netdev user,id=vmnic -device virtio-net-device,netdev=vmnic \
		-drive if=pflash,format=raw,index=1,file=envstore.img

# Target to run just Linux kernel directly. Here it's expected that the root fs
# has been compiled into the kernel itself.
.PHONY: run-kernel
run-kernel:
	cd $(OUT_PATH) && \
	$(QEMU_BIN) \
		$(QEMU_ARGS) \
		$(QEMU_KERNEL) \
                -append "console=ttyAMA0"

# Target to run just Linux kernel directly and pulling the root fs separately.
.PHONY: run-kernel-initrd
run-kernel-initrd:
	cd $(OUT_PATH) && \
	$(QEMU_BIN) \
		$(QEMU_ARGS) \
		$(QEMU_KERNEL) \
		-initrd $(ROOTFS) \
                -append "console=ttyAMA0"


################################################################################
# Clean
################################################################################
.PHONY: clean
clean: buildroot-clean linux-clean qemu-clean uboot-clean

.PHONY: distclean
distclean: clean
	rm -rf $(OUT_PATH)
