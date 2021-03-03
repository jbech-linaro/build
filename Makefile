################################################################################
# Paths to git projects and various binaries
################################################################################
CCACHE ?= $(shell which ccache) # Don't remove this comment (space is needed)

ROOT				?= $(PWD)

BR_DL_DIR			?= $(HOME)/br_download
BR_PATH				?= $(ROOT)/buildroot
BUILD_PATH			?= $(ROOT)/build
GRUB2_PATH			?= $(ROOT)/grub2
LINUX_PATH			?= $(ROOT)/linux
MKIMAGE_PATH			?= $(UBOOT_PATH)/tools
OUT_PATH			?= $(ROOT)/out
QEMU_PATH			?= $(ROOT)/qemu
UBOOT_PATH			?= $(ROOT)/u-boot

DEBUG				?= n
PLATFORM			?= qemu
CCACHE_DIR			?= $(HOME)/.ccache

# Configuration
ENVSTORE			?= y
GDB				?= n
GRUB2				?= y
QEMU_VIRTFS_ENABLE		?= y
QEMU_VIRTFS_HOST_DIR		?= $(ROOT)
USE_CUSTOM_UBOOT_ENV		?= y
VARIABLES			?= n

# Binaries and general files
BIOS				?= $(UBOOT_PATH)/u-boot.bin
DTC				?= $(LINUX_PATH)/scripts/dtc/dtc
FITIMAGE			?= $(OUT_PATH)/image.fit
FITIMAGE_SRC			?= $(BUILD_PATH)/fit/fit.its
GRUB2_EFI			?= $(OUT_PATH)/grub2-arm64.efi
KERNEL_EXT4			?= $(OUT_PATH)/kernel.ext4
KERNEL_IMAGE			?= $(LINUX_PATH)/arch/arm64/boot/Image
KERNEL_IMAGEGZ			?= $(LINUX_PATH)/arch/arm64/boot/Image.gz
KERNEL_UIMAGE			?= $(OUT_PATH)/uImage
QEMU_BIN			?= $(QEMU_PATH)/aarch64-softmmu/qemu-system-aarch64
QEMU_DTB			?= $(OUT_PATH)/qemu-aarch64.dtb
QEMU_DTS			?= $(OUT_PATH)/qemu-aarch64.dts
QEMU_ENV			?= $(OUT_PATH)/envstore.img
ROOTFS_EXT4			?= $(BR_PATH)/output/images/rootfs.ext4
ROOTFS_GZ			?= $(BR_PATH)/output/images/rootfs.cpio.gz
ROOTFS_UGZ			?= $(BR_PATH)/output/images/rootfs.cpio.uboot
UBOOT_ENV_SRC			?= $(BUILD_PATH)/uboot-env.txt
UBOOT_ENV_CONF			?= $(BUILD_PATH)/kconfigs/u-boot/env.conf

# Load and entry addresses
KERNEL_ENTRY			?= 0x40400000
KERNEL_LOADADDR			?= 0x40400000
ROOTFS_ENTRY			?= 0x44000000
ROOTFS_LOADADDR			?= 0x44000000

# This is just a temporary writeable address high enough to not clash with the
# addresses used when U-Boot loads the images.
FITIMG_LOADADDR			?= 0x48000000

# FIT keys, certificates etc.
# Note that FIT_KEY_SIZE is also set in the FITIMAGE_SRC, that has to be
# adjusted accordingly.
FIT_KEY_SIZE			?= 2048
CONTROL_FDT_DTB			?= $(OUT_PATH)/control-fdt.dtb
CONTROL_FDT_DTS			?= $(BUILD_PATH)/fit/control-fdt.dts
FIT_CERTIFICATE			?= $(OUT_PATH)/private.crt
FIT_PRIVATE_KEY			?= $(OUT_PATH)/private.key

# EFI keys and certificates
EFI_KEY_SIZE			?= 2048
EFI_CERT_IMG			?= $(OUT_PATH)/certs.img
EFI_DB_DIR			?= $(OUT_PATH)/variables
EFI_PK_AUTH			?= $(EFI_DB_DIR)/PK.auth
EFI_KEK_AUTH			?= $(EFI_DB_DIR)/KEK.auth


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
TARGET_DEPS := linux qemu uboot buildroot uimage

ifeq ($(ENVSTORE),y)
TARGET_DEPS += qemu-create-env-image
endif

ifeq ($(GRUB2),y)
TARGET_DEPS += grub2 grub2-create-image
endif

ifeq ($(SIGN),y)
TARGET_DEPS += fit-signed
else
TARGET_DEPS += fit
endif

.PHONY: all
all: $(TARGET_DEPS)

# build each sub project sequencially but still enable parallel builds in the 
# subprojects.  This means don't min qemu with linux but do parallel inside of 
# each
.NOTPARALLEL:

include toolchain.mk

#################################################################################
# Helper targets
#################################################################################
help: grub2-help qemu-help uboot-help

$(OUT_PATH):
	mkdir -p $@


#################################################################################
# Buildroot
#################################################################################
BR_DEFCONFIG_FILES := $(BUILD_PATH)/kconfigs/buildroot/br-qemu-virt-aarch64.conf

$(BR_PATH)/.config:
	cd $(BR_PATH) && \
	support/kconfig/merge_config.sh \
	$(BR_DEFCONFIG_FILES)

# Note that the AARCH64_PATH here is necessary and it's used in the
# kconfigs/buildroot/br-qemu-virt-aarch64.conf file where a variable is used to
# find and set the correct toolchain to use.
buildroot: $(BR_PATH)/.config $(OUT_PATH)
	$(MAKE) -C $(BR_PATH) \
		BR2_CCACHE_DIR="$(CCACHE_DIR)" \
		AARCH64_PATH=$(AARCH64_PATH)
	ln -sf $(ROOTFS_GZ) $(OUT_PATH)/ && \
	ln -sf $(ROOTFS_UGZ) $(OUT_PATH)/ && \
	ln -sf $(ROOTFS_EXT4) $(OUT_PATH)/

.PHONY: buildroot-clean
buildroot-clean:
	-mv $(BR_PATH)/dl $(ROOT)/tmp-dl
	-cd $(BR_PATH) && git clean -xdf
	-mv $(ROOT)/tmp-dl $(BR_PATH)/dl

.PHONY: buildroot-distclean
buildroot-distclean:
	-mv $(BR_PATH)/dl $(ROOT)/buildroot-dl-$$(date +%Y-%m-%d-%H-%M-%S)
	cd $(BR_PATH) && git clean -xdf

################################################################################
# Grub2
################################################################################
GRUB2_TMP ?= $(OUT_PATH)/grub2

# When creating the image containing Linux kernel, we need to temporarily store
# the files somewhere.
$(GRUB2_TMP):
	mkdir -p $@

# Bootstrap if there is no configure or if it has been updated
$(GRUB2_PATH)/configure:
	@echo "Running grub2 bootstrap"
	cd $(GRUB2_PATH) && ./bootstrap

# Configure
$(GRUB2_PATH)/config.h: $(GRUB2_PATH)/configure
	cd $(GRUB2_PATH) && \
		./configure --with-platform=efi \
			    --target=aarch64-linux-gnu \
			    --disable-werror \
			    --localedir=$(GRUB2_PATH) \
			    TARGET_CC=$(AARCH64_CROSS_COMPILE)gcc \
			    TARGET_OBJCOPY=$(AARCH64_CROSS_COMPILE)objcopy \
			    TARGET_STRIP=$(AARCH64_CROSS_COMPILE)strip

# Compile
grub2-compile: $(GRUB2_PATH)/config.h
	$(MAKE) -C $(GRUB2_PATH)

grub2-create-image: $(GRUB2_TMP) linux
	# Use a written path to avoid rm -f real host machine files (in case
	# GRUB2_TMP has been set to an empty string)
	rm -f $(OUT_PATH)/grub2/*
	cp $(KERNEL_IMAGE) $(GRUB2_TMP)
	virt-make-fs -t vfat $(GRUB2_TMP) $(KERNEL_EXT4)

# Create the efi file
grub2: grub2-compile $(OUT_PATH)
	$(GRUB2_PATH)/grub-mkstandalone \
		-d $(GRUB2_PATH)/grub-core \
		-O arm64-efi \
		-o $(GRUB2_EFI)

grub2-help:
	@echo "\n================================================================================"
	@echo "= GRUB2 help                                                                   ="
	@echo "================================================================================"
	@echo "Boot kernel from grub2 shell:"
	@echo "  insmod linux"
	@echo "  linux (hd1)/Image root=/dev/vda"
	@echo "  boot"

.PHONY: grub2-clean
grub2-clean:
	cd $(GRUB2_PATH) && git clean -xdf


################################################################################
# Linux kernel
################################################################################
LINUX_DEFCONFIG_FILES := $(LINUX_PATH)/arch/arm64/configs/defconfig

$(LINUX_PATH)/.config: $(LINUX_DEFCONFIG_FILES)
	cd $(LINUX_PATH) && \
                ARCH=arm64 \
                scripts/kconfig/merge_config.sh $(LINUX_DEFCONFIG_FILES)

linux-defconfig: $(LINUX_PATH)/.config

linux: linux-defconfig $(OUT_PATH)
	yes "" | $(MAKE) -C $(LINUX_PATH) \
		ARCH=arm64 CROSS_COMPILE="$(CCACHE)$(AARCH64_CROSS_COMPILE)" \
		Image.gz dtbs && \
	ln -sf $(KERNEL_IMAGE) $(OUT_PATH)/ && \
	ln -sf $(KERNEL_IMAGEGZ) $(OUT_PATH)/

.PHONY: linux-menuconfig
linux-menuconfig: $(LINUX_PATH)/.config
	$(MAKE) -C $(LINUX_PATH) ARCH=arm64 menuconfig

.PHONY: linux-cscope
linux-cscope:
	$(MAKE) -C $(LINUX_PATH) cscope

.PHONY: linux-clean
linux-clean:
	cd $(LINUX_PATH) && git clean -xdf


################################################################################
# QEMU
################################################################################
qemu-configure:
	cd $(QEMU_PATH) && \
	./configure --target-list=aarch64-softmmu \
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

$(QEMU_DTB): qemu
	$(QEMU_BIN) -machine virt \
		-nographic \
		-cpu cortex-a57 \
		-machine dumpdtb=$(QEMU_DTB)

qemu-dump-dtb: $(QEMU_DTB)

$(QEMU_DTS): qemu-dump-dtb linux
	$(DTC) -I dtb -O dts $(QEMU_DTB) > $(QEMU_DTS)

qemu-dump-dts: $(QEMU_DTS)

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


################################################################################
# mkimage - create images to be loaded by U-boot
################################################################################
# Without the objcopy, the uImage will be 10x bigger.
uimage: linux $(OUT_PATH)
	${AARCH64_CROSS_COMPILE}objcopy -O binary \
					-R .note \
					-R .comment \
					-S $(LINUX_PATH)/vmlinux \
					$(OUT_PATH)/linux.bin && \
	$(MKIMAGE_PATH)/mkimage -A arm64 \
				-O linux \
				-T kernel \
				-C none \
				-a $(KERNEL_LOADADDR) \
				-e $(KERNEL_ENTRY) \
				-n "Linux kernel" \
				-d $(OUT_PATH)/linux.bin $(KERNEL_UIMAGE)

# This isn't direcly used anywhere, but in case the user want to convert his
# own gzip'd root file system, then then you use this, example
#    make urootfs ROOTFS_GZ=<my-own-rootfs>
urootfs: $(OUT_PATH)
	$(MKIMAGE_PATH)/mkimage -A arm64 \
				-T ramdisk \
				-C gzip \
				-a $(ROOTFS_LOADADDR) \
				-e $(ROOTFS_ENTRY) \
				-n "Root file system" \
				-d $(ROOTFS_GZ) $(ROOTFS_UGZ)

fit: buildroot $(QEMU_DTB) linux $(OUT_PATH)
	$(MKIMAGE_PATH)/mkimage -f $(FITIMAGE_SRC) \
				$(FITIMAGE)

fit-signed: buildroot $(QEMU_DTB) linux generate-control-fdt $(OUT_PATH)
	$(MKIMAGE_PATH)/mkimage -f $(FITIMAGE_SRC) \
				-K $(CONTROL_FDT_DTB) \
				-k $(OUT_PATH) \
				-r \
				$(FITIMAGE)

create-uboot-env: $(OUT_PATH)
	echo "Creating envstore image with load target ..."
	$(UBOOT_PATH)/tools/mkenvimage -s 0x4000000 -o $(QEMU_ENV) $(UBOOT_ENV_SRC)

################################################################################
# U-boot
################################################################################
UBOOT_DEFCONFIG_FILES	:= $(UBOOT_PATH)/configs/qemu_arm64_defconfig \
			   $(BUILD_PATH)/kconfigs/u-boot/efi-deps.conf

# There might be a better way to do this, basically all we want to do is to add
# the `CONFIG_DEFAULT_ENV_FILE` path so merge_config will pick it up. Seems
# like the AARCH64_PATH trick we did for buildroot doesn't work for U-Boot.
ifeq ($(USE_CUSTOM_UBOOT_ENV),y)
# We don't want to recreate this file, since it might force unnecessary
# recompiles and if a user want to manually change it, we don't want the file to
# be overridden.
ifeq (,$(wildcard $(UBOOT_ENV_CONF)))
$(info Creating $(UBOOT_ENV_CONF) ...)
$(shell echo "CONFIG_USE_DEFAULT_ENV_FILE=y" > $(UBOOT_ENV_CONF))
$(shell echo "CONFIG_DEFAULT_ENV_FILE=\"$(UBOOT_ENV_SRC)\"" >> $(UBOOT_ENV_CONF))
endif
UBOOT_DEFCONFIG_FILES	+= $(BUILD_PATH)/kconfigs/u-boot/env.conf
endif

ifeq ($(SIGN),y)
UBOOT_EXTRA_ARGS	?= EXT_DTB=$(CONTROL_FDT_DTB)
endif

$(UBOOT_PATH)/.config: $(UBOOT_DEFCONFIG_FILES)
	cd $(UBOOT_PATH) && \
                scripts/kconfig/merge_config.sh $(UBOOT_DEFCONFIG_FILES)

uboot-defconfig: $(UBOOT_PATH)/.config

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

.PHONY: uboot-cscope
uboot-cscope:
	$(MAKE) -C $(UBOOT_PATH) cscope

uboot-help:
	@echo "\n================================================================================"
	@echo "= U-boot                                                                       ="
	@echo "================================================================================"
	@echo "TFTP (bootm): U-Boot -> Kernel -> Buildroot shell"
	@echo '  setenv netboot "dhcp; setenv serverip 192.168.1.110; tftp $${kernel_addr_r} uImage; tftp $${ramdisk_addr_r} rootfs.cpio.uboot; bootm $${kernel_addr_r} $${ramdisk_addr_r} $${fdt_addr}"'
	@echo "\nTFTP (bootm) fit: U-Boot + fit-image -> Kernel -> Buildroot shell"
	@echo '  setenv netbootfit "dhcp; setenv serverip 192.168.1.110; tftp ${FITIMG_LOADADDR} image.fit; bootm"'
	@echo "\nTFTP (bootm) fit configs: U-Boot + fit-image#config-x -> Kernel -> Buildroot shell"
	@echo '  setenv netloadfit "dhcp; setenv serverip 192.168.1.110; tftp ${FITIMG_LOADADDR} image.fit"'
	@echo "  then one of these:"
	@echo '  setenv fitconfig1 "run netloadfit; bootm ${FITIMG_LOADADDR}#config-1"'
	@echo '  setenv fitconfig2 "run netloadfit; bootm ${FITIMG_LOADADDR}#config-2"'
	@echo '  setenv fitconfig3 "run netloadfit; bootm ${FITIMG_LOADADDR}#config-3"'
	@echo '  setenv fitconfig4 "run netloadfit; bootm ${FITIMG_LOADADDR}#config-4"'
	@echo "\nTFTP (bootefi): U-Boot -> grub2 -> Kernel -> Buildroot shell"
	@echo '  setenv netbootgrub "dhcp; setenv serverip 192.168.1.110; tftp $${kernel_addr_r} grub2-arm64.efi; bootefi $${kernel_addr_r}"'
	@echo "\nSave the U-boot environment variables"
	@echo "  1. Build with ENVSTORE=y (enabled by default)"
	@echo "  2. In U-boot, make changes, i.e., setenv etc"
	@echo "  3. saveenv"


.PHONY: uboot-clean
uboot-clean:
	cd $(UBOOT_PATH) && git clean -xdf


################################################################################
# Keys, signatures etc for fit images
################################################################################
$(FIT_PRIVATE_KEY): 
	mkdir -p $(OUT_PATH) && \
	openssl genrsa -F4 -out $(FIT_PRIVATE_KEY) $(FIT_KEY_SIZE)

generate-keys: $(FIT_PRIVATE_KEY)

$(FIT_CERTIFICATE): | generate-keys
	openssl req -batch -new -x509 -key $(FIT_PRIVATE_KEY) -out $(FIT_CERTIFICATE)

generate-certificate: $(FIT_CERTIFICATE)

$(CONTROL_FDT_DTB): linux
	$(DTC) $(CONTROL_FDT_DTS) -O dtb -o $(CONTROL_FDT_DTB)

generate-control-fdt: $(CONTROL_FDT_DTB) generate-certificate

.PHONY: keys-clean
keys-clean:
	rm -f $(FIT_PRIVATE_KEY) $(CONTROL_FDT_DTB) $(FIT_CERTIFICATE)


################################################################################
# Variables for EFI related stuff
################################################################################
$(EFI_DB_DIR):
	mkdir -p $@

$(EFI_PK_AUTH): $(EFI_DB_DIR)
	cd $(OUT_PATH) && \
	openssl req \
		-x509 \
		-sha256 \
		-newkey rsa:$(EFI_KEY_SIZE) \
		-subj /CN=TEST_PK/ \
		-keyout PK.key \
		-out PK.crt \
		-nodes \
		-days 365 && \
	cert-to-efi-sig-list -g 11111111-2222-3333-4444-123456789abc PK.crt PK.esl && \
	sign-efi-sig-list -c PK.crt -k PK.key PK PK.esl PK.auth

$(EFI_KEK_AUTH): $(EFI_DB_DIR) $(EFI_PK_AUTH)
	cd $(OUT_PATH) && \
	openssl req \
		-x509 \
		-sha256 \
		-newkey rsa:$(EFI_KEY_SIZE) \
		-subj /CN=TEST_KEK/ \
		-keyout KEK.key \
		-out KEK.crt \
		-nodes \
		-days 365 && \
	cert-to-efi-sig-list -g 11111111-2222-3333-4444-123456789abc KEK.crt KEK.esl && \
	sign-efi-sig-list -c PK.crt -k PK.key KEK KEK.esl KEK.auth

$(EFI_CERT_IMG): $(EFI_DB_DIR) $(EFI_KEK_AUTH)
	cp -u $(OUT_PATH)/PK.auth $(OUT_PATH)/KEK.auth $(EFI_DB_DIR)
	virt-make-fs -s 1M -t ext4 $(EFI_DB_DIR) $(EFI_CERT_IMG)

create-key-img: $(EFI_CERT_IMG)

# U-Boot commands
#   nvme scan
#   load nvme 0 0x70000000 PK.auth;
#   setenv -e -nv -bs -rt -at -i 0x70000000,$filesize PK
#   load nvme 0 0x70000000 KEK.auth
#   setenv -e -nv -bs -rt -at -i 0x70000000,$filesize KEK

################################################################################
# Run targets
#
# It should be noted that the run targets are intentionally written so that
# they just simply launch the target. I.e., there are no checks and not
# dependency rules added to build certain pieces if missing. The reason for
# this is that it should be quick to run your targets. This also means that it
# is likely that you get error if trying this and:
#  - You forgot to build
#  - You forgot to build some components
#  - You forgot to rebuild after making changes to some components.
################################################################################
# QEMU target setup
QEMU_BIOS		?= -bios $(BIOS)
QEMU_KERNEL		?= -kernel Image.gz

QEMU_ARGS		+= -nographic \
		   	   -smp 1 \
		   	   -machine virt \
		   	   -cpu cortex-a57 \
		   	   -d unimp \
		   	   -m 512 \
			   -no-acpi \
		-netdev user,id=vmnic,tftp=$(ROOT)/out,bootfile=uEnv.txt \
		-device virtio-net-device,netdev=vmnic \

ifeq ($(QEMU_VIRTFS_ENABLE),y)
QEMU_EXTRA_ARGS +=\
	-fsdev local,id=fsdev0,path=$(QEMU_VIRTFS_HOST_DIR),security_model=none \
	-device virtio-9p-device,fsdev=fsdev0,mount_tag=host
endif

ifeq ($(GRUB2),y)
QEMU_EXTRA_ARGS +=\
	-drive if=none,file=$(KERNEL_EXT4),format=raw,id=hd1 \
	-device virtio-blk-device,drive=hd1 \
	-drive file=$(ROOTFS_EXT4),if=none,format=raw,id=hd0 \
	-device virtio-blk-device,drive=hd0
endif

ifeq ($(ENVSTORE),y)
QEMU_EXTRA_ARGS +=\
	-drive if=pflash,format=raw,index=1,file=envstore.img
endif

# Enable GDB debugging
ifeq ($(GDB),y)
QEMU_EXTRA_ARGS	+= -s -S

# For convenience, setup path to gdb
$(shell ln -sf $(AARCH64_PATH)/bin/aarch64-none-linux-gnu-gdb $(ROOT)/gdb)
endif

# Actual targets
.PHONY: run-netboot
run-netboot:
	if [ ! -r $(OUT_PATH)/uEnv.txt ]; then \
		cp $(BUILD_PATH)/uEnv-example.txt $(OUT_PATH)/uEnv.txt; \
	fi
	cd $(OUT_PATH) && \
	$(QEMU_BIN) \
		$(QEMU_ARGS) \
		$(QEMU_BIOS) \
		$(QEMU_EXTRA_ARGS)

# Target to run just Linux kernel directly. Here it's expected that the root fs
# has been compiled into the kernel itself (if not, this will fail!).
.PHONY: run-kernel
run-kernel:
	cd $(OUT_PATH) && \
	$(QEMU_BIN) \
		$(QEMU_ARGS) \
		$(QEMU_KERNEL) \
                -append "console=ttyAMA0" \
		$(QEMU_EXTRA_ARGS)

# Target to run just Linux kernel directly and pulling the root fs separately.
.PHONY: run-kernel-initrd
run-kernel-initrd:
	cd $(OUT_PATH) && \
	$(QEMU_BIN) \
		$(QEMU_ARGS) \
		$(QEMU_KERNEL) \
		-initrd $(ROOTFS_GZ) \
                -append "console=ttyAMA0" \
		$(QEMU_EXTRA_ARGS)


################################################################################
# Clean
################################################################################
.PHONY: clean
clean: buildroot-clean keys-clean grub2-clean linux-clean qemu-clean uboot-clean

.PHONY: distclean
distclean: clean buildroot-distclean
	rm -rf $(OUT_PATH)
