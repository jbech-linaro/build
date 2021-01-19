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
BR_DL_DIR			?= $(HOME)/br_download
LINUX_PATH			?= $(ROOT)/linux
OUT_PATH			?= $(ROOT)/out
QEMU_PATH			?= $(ROOT)/qemu
UBOOT_PATH			?= $(ROOT)/u-boot
MKIMAGE_PATH			?= $(UBOOT_PATH)/tools

DEBUG				?= n
PLATFORM			?= qemu
CCACHE_DIR			?= $(HOME)/.ccache

# Binaries
BIOS				?= $(UBOOT_PATH)/u-boot.bin
CONFIG_FRAGMENT			?= $(BUILD_PATH)/.config-fragment
DTC				?= $(LINUX_PATH)/scripts/dtc/dtc
FITB				?= $(OUT_PATH)/kernel.itb
FITS				?= $(BUILD_PATH)/fit/kernel.its
KERNEL				?= $(LINUX_PATH)/arch/arm64/boot/Image
KERNELZ				?= $(LINUX_PATH)/arch/arm64/boot/Image.gz
KERNEL_UIMAGE			?= $(OUT_PATH)/uImage
LINUX_VMLINUX			?= $(LINUX_PATH)/vmlinux
QEMU_BIN			?= $(QEMU_PATH)/aarch64-softmmu/qemu-system-aarch64
QEMU_DTB			?= $(OUT_PATH)/qemu-aarch64.dtb
QEMU_DTS			?= $(OUT_PATH)/qemu-aarch64.dts
QEMU_ENV			?= $(OUT_PATH)/envstore.img
ROOTFS				?= $(BR_PATH)/output/images/rootfs.cpio.gz
UROOTFS				?= $(BR_PATH)/output/images/rootfs.cpio.uboot

# Keys
# Note that KEY_SIZE is also set in the fit/u-boot_pubkey.dts, that has to be
# adjusted accordingly.
KEY_SIZE			?= 2048
PRIVATE_KEY			?= $(OUT_PATH)/private.key
CERTIFICATE			?= $(OUT_PATH)/private.crt
PUBKEY_DTS			?= $(BUILD_PATH)/fit/u-boot_pubkey.dts
PUBKEY_DTB			?= $(OUT_PATH)/u-boot_pubkey.dtb


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
.PHONY: all
all: linux qemu uboot buildroot

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
	mkdir -p $(OUT_PATH)
	$(MAKE) -C $(BR_PATH) \
		BR2_CCACHE_DIR="$(CCACHE_DIR)" \
		AARCH64_PATH=$(AARCH64_PATH)
	ln -sf $(ROOTFS) $(OUT_PATH)/ && \
	ln -sf $(UROOTFS) $(OUT_PATH)/

.PHONY: buildroot-clean
buildroot-clean:
	cd $(BR_PATH) && git clean -xdf

################################################################################
# Linux kernel
################################################################################
LINUX_DEFCONFIG_FILES := $(LINUX_PATH)/arch/arm64/configs/defconfig


$(LINUX_PATH)/.config: $(LINUX_DEFCONFIG_FILES)
	cd $(LINUX_PATH) && \
                ARCH=arm64 \
                scripts/kconfig/merge_config.sh $(LINUX_DEFCONFIG_FILES)

.PHONY: linux-defconfig
linux-defconfig: $(LINUX_PATH)/.config

.PHONY: linux
linux: linux-defconfig
	yes | $(MAKE) -C $(LINUX_PATH) \
		ARCH=arm64 CROSS_COMPILE="$(CCACHE)$(AARCH64_CROSS_COMPILE)" \
		Image.gz dtbs && \
	ln -sf $(KERNEL) $(OUT_PATH)/ && \
	ln -sf $(KERNELZ) $(OUT_PATH)/

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

$(QEMU_DTB): dump-dtb

dump-dtb:
	$(QEMU_BIN) -machine virt \
		-cpu cortex-a57 \
		-machine dumpdtb=$(QEMU_DTB)

dump-dtb-as-dts: dump-dtb
	$(DTC) -I dtb -O dts $(QEMU_DTB) > $(QEMU_DTS)

create-env-image:
	@if [ ! -f $(QEMU_ENV) ]; then \
		echo "Creating envstore image ..."; \
		qemu-img create -f raw $(QEMU_ENV) 64M; \
	fi

mount_command:
	@echo "Run this in QEMU / Linux / Buildroot:"
	@echo "  mkdir /host && mount -t 9p -o trans=virtio host /host"
	@echo "\nOnce done, you can access the host PC's files"

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

# FIXME: Names clashes ROOTFS and UROOTFS, this will overwrite the u-rootfs from Buildroot.
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

fit: $(ROOTFS) $(QEMU_DTB) linux
	mkdir -p $(OUT_PATH) && \
	$(MKIMAGE_PATH)/mkimage -f $(FITS) $(FITB)

################################################################################
# U-boot
################################################################################
UBOOT_DEFCONFIG_FILES	:= $(UBOOT_PATH)/configs/qemu_arm64_defconfig

ifeq ($(SIGN),y)
UBOOT_EXTRA_ARGS	?= EXT_DTB=$(PUBKEY_DTB)
endif

$(UBOOT_PATH)/.config: $(UBOOT_DEFCONFIG_FILES)
	cd $(UBOOT_PATH) && \
                scripts/kconfig/merge_config.sh $(UBOOT_DEFCONFIG_FILES)

.PHONY: uboot-defconfig
uboot-defconfig: $(UBOOT_PATH)/.config

.PHONY: uboot
uboot: uboot-defconfig
	mkdir -p $(OUT_PATH) && \
	$(MAKE) -C $(UBOOT_PATH) \
		$(UBOOT_EXTRA_ARGS) \
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
# Keys, signatures etc
################################################################################
$(PRIVATE_KEY): 
	openssl genrsa -F4 -out $(PRIVATE_KEY) $(KEY_SIZE)

generate-keys: $(PRIVATE_KEY)

$(CERTIFICATE): | generate-keys
	openssl req -batch -new -x509 -key $(PRIVATE_KEY) -out $(CERTIFICATE)

generate-certificate: $(CERTIFICATE)

keys-clean:
	rm -rf $(PRIVATE_KEY) $(CERTIFICATE)

.PHONY: generate-uboot-pubkey
generate-uboot-pubkey:
	$(DTC) $(PUBKEY_DTS) -O dtb -o $(PUBKEY_DTB)



fit-signed: generate-uboot-pubkey
	mkdir -p $(OUT_PATH) && \
	$(MKIMAGE_PATH)/mkimage -f $(FITS) \
		-K $(PUBKEY_DTB) -k $(OUT_PATH) -r $(FITB)

################################################################################
# Run targets
################################################################################
QEMU_BIOS		?= -bios $(BIOS)
QEMU_KERNEL		?= -kernel Image.gz

QEMU_ARGS		+= -nographic \
		   	   -smp 1 \
		   	   -machine virt \
		   	   -cpu cortex-a57 \
		   	   -d unimp \
		   	   -m 512 \
		   	   -no-acpi

QEMU_VIRTFS_ENABLE	?= y
QEMU_VIRTFS_HOST_DIR	?= $(ROOT)

ifeq ($(QEMU_VIRTFS_ENABLE),y)
QEMU_EXTRA_ARGS +=\
	-fsdev local,id=fsdev0,path=$(QEMU_VIRTFS_HOST_DIR),security_model=none \
	-device virtio-9p-device,fsdev=fsdev0,mount_tag=host
endif

ifeq ($(GDB),y)
QEMU_ARGS	+= -s -S

# For convenience, setup path to gdb
$(shell ln -sf $(AARCH64_PATH)/bin/aarch64-none-linux-gnu-gdb $(ROOT)/gdb)
endif

## Target to run U-boot and Linux kernel where U-boot is the bios and the kernel
## is pulled from the block device.
#.PHONY: run
#run: create-env-image
#	cd $(OUT_PATH) && \
#	$(QEMU_BIN) \
#		$(QEMU_ARGS) \
#		$(QEMU_BIOS) \
#		-semihosting-config enable,target=native
#
## -append 'console=ttyAMA0,38400 keep_bootcon root=/dev/vda2'


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
		-drive if=pflash,format=raw,index=1,file=envstore.img \
		$(QEMU_EXTRA_ARGS)

# Target to run just Linux kernel directly. Here it's expected that the root fs
# has been compiled into the kernel itself.
.PHONY: run-kernel
run-kernel: create-env-image
	cd $(OUT_PATH) && \
	$(QEMU_BIN) \
		$(QEMU_ARGS) \
		$(QEMU_KERNEL) \
                -append "console=ttyAMA0" \
		$(QEMU_EXTRA_ARGS)

# Target to run just Linux kernel directly and pulling the root fs separately.
.PHONY: run-kernel-initrd
run-kernel-initrd: create-env-image
	cd $(OUT_PATH) && \
	$(QEMU_BIN) \
		$(QEMU_ARGS) \
		$(QEMU_KERNEL) \
		-initrd $(ROOTFS) \
                -append "console=ttyAMA0" \
		$(QEMU_EXTRA_ARGS)


################################################################################
# Clean
################################################################################
.PHONY: clean
clean: buildroot-clean keys-clean linux-clean qemu-clean uboot-clean

.PHONY: distclean
distclean: clean
	rm -rf $(OUT_PATH)
