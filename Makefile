# Todo
# 1. Enable ordinary boot w/o tftp
# 2. Run Image and/or Image.gz
# 3. Modify DTB
# 4. Create boot.scr or uboot.env


################################################################################
# Paths to git projects and various binaries
################################################################################
CCACHE ?= $(shell which ccache) # Don't remove this comment (space is needed)

ROOT				?= $(PWD)

BR_DL_DIR			?= $(HOME)/br_download
BR_PATH				?= $(ROOT)/buildroot
BUILD_PATH			?= $(ROOT)/build
LINUX_PATH			?= $(ROOT)/linux
MKIMAGE_PATH			?= $(UBOOT_PATH)/tools
OUT_PATH			?= $(ROOT)/out
QEMU_PATH			?= $(ROOT)/qemu
UBOOT_PATH			?= $(ROOT)/u-boot

DEBUG				?= n
PLATFORM			?= qemu
CCACHE_DIR			?= $(HOME)/.ccache

# Binaries and general files
BIOS				?= $(UBOOT_PATH)/u-boot.bin
DTC				?= $(LINUX_PATH)/scripts/dtc/dtc
FITIMAGE			?= $(OUT_PATH)/image.fit
FITIMAGE_SRC			?= $(BUILD_PATH)/fit/fit.its
KERNEL_IMAGE			?= $(LINUX_PATH)/arch/arm64/boot/Image
KERNEL_IMAGEGZ			?= $(LINUX_PATH)/arch/arm64/boot/Image.gz
KERNEL_UIMAGE			?= $(OUT_PATH)/uImage
QEMU_BIN			?= $(QEMU_PATH)/aarch64-softmmu/qemu-system-aarch64
QEMU_DTB			?= $(OUT_PATH)/qemu-aarch64.dtb
QEMU_DTS			?= $(OUT_PATH)/qemu-aarch64.dts
QEMU_ENV			?= $(OUT_PATH)/envstore.img
ROOTFS_GZ			?= $(BR_PATH)/output/images/rootfs.cpio.gz
ROOTFS_UGZ			?= $(BR_PATH)/output/images/rootfs.cpio.uboot

# Load and entry addresses
KERNEL_ENTRY			?= 0x40400000
KERNEL_LOADADDR			?= 0x40400000
ROOTFS_ENTRY			?= 0x44000000
ROOTFS_LOADADDR			?= 0x44000000

# Keys
# Note that KEY_SIZE is also set in the FITIMAGE_SRC, that has to be adjusted
# accordingly.
KEY_SIZE			?= 2048
CONTROL_FDT_DTB			?= $(OUT_PATH)/control-fdt.dtb
CONTROL_FDT_DTS			?= $(BUILD_PATH)/fit/control-fdt.dts
CERTIFICATE			?= $(OUT_PATH)/private.crt
PRIVATE_KEY			?= $(OUT_PATH)/private.key

# EFI keys and certificates
EFI_CERT_IMG			?= $(OUT_PATH)/certs.img
EFI_DB_DIR			?= $(OUT_PATH)/tmp
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
TARGET_DEPS := linux qemu uboot buildroot
ifeq ($(SIGN),y)
TARGET_DEPS += fit-signed
else
TARGET_DEPS += fit
endif

.PHONY: all
all: $(TARGET_DEPS)

include toolchain.mk


#################################################################################
# Buildroot
#################################################################################
BR_DEFCONFIG_FILES := $(BUILD_PATH)/br_kconfigs/br_qemu_aarch64_virt.conf
$(BR_PATH)/.config:
	cd $(BR_PATH) && \
	support/kconfig/merge_config.sh \
	$(BR_DEFCONFIG_FILES)

# Note that the AARCH64_PATH here is necessary and it's used in the
# br_kconfigs/br_qemu_aarch64_virt.conf file where a variable is used to find
# and set the # correct toolchain to use.
buildroot: $(BR_PATH)/.config
	mkdir -p $(OUT_PATH)
	$(MAKE) -C $(BR_PATH) \
		BR2_CCACHE_DIR="$(CCACHE_DIR)" \
		AARCH64_PATH=$(AARCH64_PATH)
	ln -sf $(ROOTFS_GZ) $(OUT_PATH)/ && \
	ln -sf $(ROOTFS_UGZ) $(OUT_PATH)/

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

linux-defconfig: $(LINUX_PATH)/.config

linux: linux-defconfig
	yes | $(MAKE) -C $(LINUX_PATH) \
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

qemu: qemu-configure
	make -C $(QEMU_PATH)

$(QEMU_DTB): qemu
	$(QEMU_BIN) -machine virt \
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

qemu_mount_command:
	@echo "Run this in QEMU / Linux / Buildroot:"
	@echo "  mkdir /host && mount -t 9p -o trans=virtio host /host"
	@echo "\nOnce done, you can access the host PC's files"

.PHONY: qemu-clean
qemu-clean:
	cd $(QEMU_PATH) && git clean -xdf


################################################################################
# mkimage
################################################################################
# FIXME: The linux.bin thing probably isn't necessary.
uimage: $(KERNEL_IMAGE)
	mkdir -p $(OUT_PATH) && \
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

# FIXME: Names clashes ROOTFS_GZ and ROOTFS_UGZ, this will overwrite the u-rootfs from Buildroot.
urootfs:
	mkdir -p $(OUT_PATH) && \
	$(MKIMAGE_PATH)/mkimage -A arm64 \
				-T ramdisk \
				-C gzip \
				-a $(ROOTFS_LOADADDR) \
				-e $(ROOTFS_ENTRY) \
				-n "Root files system" \
				-d $(ROOTFS_GZ) $(ROOTFS_UGZ)

fit: buildroot $(QEMU_DTB) linux
	mkdir -p $(OUT_PATH) && \
	$(MKIMAGE_PATH)/mkimage -f $(FITIMAGE_SRC) \
				$(FITIMAGE)

fit-signed: buildroot $(QEMU_DTB) linux generate-control-fdt
	mkdir -p $(OUT_PATH) && \
	$(MKIMAGE_PATH)/mkimage -f $(FITIMAGE_SRC) \
				-K $(CONTROL_FDT_DTB) \
				-k $(OUT_PATH) \
				-r \
				$(FITIMAGE)


################################################################################
# U-boot
################################################################################
UBOOT_DEFCONFIG_FILES	:= $(UBOOT_PATH)/configs/qemu_arm64_defconfig \
			   $(BUILD_PATH)/u-boot_kconfigs/efi_deps.conf

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

.PHONY: uboot-clean
uboot-clean:
	cd $(UBOOT_PATH) && git clean -xdf


################################################################################
# Keys, signatures etc
################################################################################
$(PRIVATE_KEY): 
	mkdir -p $(OUT_PATH) && \
	openssl genrsa -F4 -out $(PRIVATE_KEY) $(KEY_SIZE)

generate-keys: $(PRIVATE_KEY)

$(CERTIFICATE): | generate-keys
	openssl req -batch -new -x509 -key $(PRIVATE_KEY) -out $(CERTIFICATE)

generate-certificate: $(CERTIFICATE)

$(CONTROL_FDT_DTB): linux
	$(DTC) $(CONTROL_FDT_DTS) -O dtb -o $(CONTROL_FDT_DTB)

generate-control-fdt: $(CONTROL_FDT_DTB) generate-certificate

keys-clean:
	rm -f $(PRIVATE_KEY) $(CONTROL_FDT_DTB) $(CERTIFICATE)


################################################################################
# Run targets
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
		   	   -no-acpi

QEMU_VIRTFS_ENABLE	?= y
QEMU_VIRTFS_HOST_DIR	?= $(ROOT)

ifeq ($(QEMU_VIRTFS_ENABLE),y)
QEMU_EXTRA_ARGS +=\
	-fsdev local,id=fsdev0,path=$(QEMU_VIRTFS_HOST_DIR),security_model=none \
	-device virtio-9p-device,fsdev=fsdev0,mount_tag=host
endif

# Enable GDB debugging
ifeq ($(GDB),y)
QEMU_ARGS	+= -s -S

# For convenience, setup path to gdb
$(shell ln -sf $(AARCH64_PATH)/bin/aarch64-none-linux-gnu-gdb $(ROOT)/gdb)
endif

# Actual targets
.PHONY: run-netboot
run-netboot: qemu-create-env-image uimage
	cd $(OUT_PATH) && \
	$(QEMU_BIN) \
		$(QEMU_ARGS) \
		$(QEMU_BIOS) \
		-netdev user,id=vmnic -device virtio-net-device,netdev=vmnic \
		-drive if=pflash,format=raw,index=1,file=envstore.img \
		$(QEMU_EXTRA_ARGS)

.PHONY: run-netbootefi
run-netbootefi: qemu-create-env-image uimage create-key-img
	cd $(OUT_PATH) && \
	$(QEMU_BIN) \
		$(QEMU_ARGS) \
		$(QEMU_BIOS) \
		-netdev user,id=vmnic -device virtio-net-device,netdev=vmnic \
		-drive if=pflash,format=raw,index=1,file=envstore.img \
		-semihosting-config enable,target=native \
		-drive if=none,format=raw,file=$(EFI_CERT_IMG),id=mydisk \
		-device nvme,drive=mydisk,serial=foo \
		$(QEMU_EXTRA_ARGS)

#   -monitor null -nographic \
#   -cpu cortex-a57 -bios bl1.bin  -machine virt,secure=on -d unimp \

# Target to run just Linux kernel directly. Here it's expected that the root fs
# has been compiled into the kernel itself (if not, this will fail!).
.PHONY: run-kernel
run-kernel: qemu-create-env-image
	cd $(OUT_PATH) && \
	$(QEMU_BIN) \
		$(QEMU_ARGS) \
		$(QEMU_KERNEL) \
                -append "console=ttyAMA0" \
		$(QEMU_EXTRA_ARGS)

# Target to run just Linux kernel directly and pulling the root fs separately.
.PHONY: run-kernel-initrd
run-kernel-initrd: qemu-create-env-image
	cd $(OUT_PATH) && \
	$(QEMU_BIN) \
		$(QEMU_ARGS) \
		$(QEMU_KERNEL) \
		-initrd $(ROOTFS_GZ) \
                -append "console=ttyAMA0" \
		$(QEMU_EXTRA_ARGS)

################################################################################
# EFI related stuff
################################################################################

$(EFI_DB_DIR):
	mkdir -p $@

$(EFI_PK_AUTH): $(EFI_DB_DIR)
	cd $(OUT_PATH) && \
	openssl req -x509 -sha256 -newkey rsa:2048 -subj /CN=TEST_PK/ -keyout PK.key -out PK.crt -nodes -days 365 && \
	cert-to-efi-sig-list -g 11111111-2222-3333-4444-123456789abc PK.crt PK.esl; sign-efi-sig-list -c PK.crt -k PK.key PK PK.esl PK.auth

$(EFI_KEK_AUTH): $(EFI_DB_DIR) $(EFI_PK_AUTH)
	cd $(OUT_PATH) && \
	openssl req -x509 -sha256 -newkey rsa:2048 -subj /CN=TEST_KEK/ -keyout KEK.key -out KEK.crt -nodes -days 365 && \
	cert-to-efi-sig-list -g 11111111-2222-3333-4444-123456789abc KEK.crt KEK.esl; sign-efi-sig-list -c PK.crt -k PK.key KEK KEK.esl KEK.auth

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
# Clean
################################################################################
.PHONY: clean
clean: buildroot-clean keys-clean linux-clean qemu-clean uboot-clean

.PHONY: distclean
distclean: clean
	rm -rf $(OUT_PATH)
