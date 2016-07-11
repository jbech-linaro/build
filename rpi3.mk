################################################################################
# Following variables defines how the NS_USER (Non Secure User - Client
# Application), NS_KERNEL (Non Secure Kernel), S_KERNEL (Secure Kernel) and
# S_USER (Secure User - TA) are compiled
################################################################################
override COMPILE_NS_USER   := 64
override COMPILE_NS_KERNEL := 64
override COMPILE_S_USER    := 64
override COMPILE_S_KERNEL  := 64

DEBUG ?= 1

# Firmware package to download, for convenience later on when unpacking etc,
# we split it up in three different variables. Note that this should be updated
# when newer firmware packages will be used.
RPI3_FIRMWARE_URL = https://github.com/raspberrypi/firmware/archive
RPI3_FIRMWARE_FILE = 046effa13ebc4cc7601df4f06f4834bd0eebb0f8
RPI3_FIRMWARE_FILE_EXT = zip

-include common.mk

################################################################################
# Mandatory definition to use common.mk
################################################################################
ifeq ($(COMPILE_NS_USER),64)
MULTIARCH			:= aarch64-linux-gnu
else
MULTIARCH			:= arm-linux-gnueabihf
endif

################################################################################
# Paths to git projects and various binaries
################################################################################
ARM_TF_PATH		?= $(ROOT)/arm-trusted-firmware
ARM_TF_OUT		?= $(ARM_TF_PATH)/build/rpi3/debug
ARM_TF_BIN		?= $(ARM_TF_OUT)/bl31.bin
ARM_TF_TMP		?= $(ARM_TF_OUT)/bl31.tmp
ARM_TF_HEAD		?= $(ARM_TF_OUT)/bl31.head
ARM_TF_BOOT             ?= $(ARM_TF_OUT)/optee.bin

U-BOOT_PATH		?= $(ROOT)/u-boot
U-BOOT_BIN		?= $(U-BOOT_PATH)/u-boot.bin
U-BOOT_JTAG_BIN		?= $(U-BOOT_PATH)/u-boot-jtag.bin

RPI3_FIRMWARE_PATH	?= $(ROOT)/firmware
RPI3_HEAD_BIN		?= $(RPI3_FIRMWARE_PATH)/head.bin
RPI3_BOOT_CONFIG	?= $(RPI3_FIRMWARE_PATH)/config.txt
RPI3_UBOOT_ENV		?= $(RPI3_FIRMWARE_PATH)/uboot.env
RPI3_OPTEE_INIT		?= $(RPI3_FIRMWARE_PATH)/optee
RPI3_OPTEE_ROOTFS	?= $(GEN_ROOTFS_PATH)/pi3_rootfs_overlay.tar.gz
RPI3_STOCK_FW_PATH	?= $(ROOT)/rpi3_firmware

OPTEE_OS_PAGER		?= $(OPTEE_OS_PATH)/out/arm/core/tee-pager.bin

LINUX_IMAGE		?= $(LINUX_PATH)/arch/arm64/boot/Image
LINUX_DTB		?= $(LINUX_PATH)/arch/arm64/boot/dts/broadcom/bcm2837-rpi-3-b.dtb
MODULE_OUTPUT		?= $(ROOT)/module_output

################################################################################
# Targets
################################################################################
all: arm-tf optee-os optee-client xtest u-boot linux update_rootfs
all-clean: arm-tf-clean u-boot-clean optee-os-clean \
	optee-client-clean


-include toolchain.mk

################################################################################
# ARM Trusted Firmware
################################################################################
ARM_TF_EXPORTS ?= \
	CFLAGS="-O0 -gdwarf-2" \
	CROSS_COMPILE="$(CCACHE)$(AARCH64_CROSS_COMPILE)"

ARM_TF_FLAGS ?= \
	BL32=$(OPTEE_OS_BIN) \
	DEBUG=1 \
	V=0 \
	CRASH_REPORTING=1 \
	LOG_LEVEL=40 \
	PLAT=rpi3 \
	SPD=opteed

arm-tf: optee-os
	$(ARM_TF_EXPORTS) $(MAKE) -C $(ARM_TF_PATH) $(ARM_TF_FLAGS) all
	cd $(ARM_TF_OUT) && \
	  dd if=/dev/zero of=scratch bs=1c count=131072 && \
	  cat $(ARM_TF_BIN) scratch > $(ARM_TF_TMP) && \
	  dd if=$(ARM_TF_TMP) of=$(ARM_TF_HEAD) bs=1c count=131072 && \
	  cat $(ARM_TF_HEAD) $(OPTEE_OS_PAGER) > $(ARM_TF_BOOT) && \
	  rm scratch $(ARM_TF_TMP) $(ARM_TF_HEAD)

arm-tf-clean:
	$(ARM_TF_EXPORTS) $(MAKE) -C $(ARM_TF_PATH) $(ARM_TF_FLAGS) clean

################################################################################
# Das U-Boot
################################################################################

U-BOOT_EXPORTS ?= CROSS_COMPILE=$(LEGACY_AARCH64_CROSS_COMPILE) ARCH=arm64

U-BOOT_DEFCONFIG_FILES := \
	$(U-BOOT_PATH)/configs/rpi_3_defconfig \
	$(ROOT)/build/kconfigs/u-boot_rpi3.conf

.PHONY: u-boot
u-boot:
	cd $(U-BOOT_PATH) && \
		scripts/kconfig/merge_config.sh $(U-BOOT_DEFCONFIG_FILES)
	$(U-BOOT_EXPORTS) $(MAKE) -C $(U-BOOT_PATH) all
	cd $(U-BOOT_PATH) && cat $(RPI3_HEAD_BIN) $(U-BOOT_BIN) > $(U-BOOT_JTAG_BIN)

u-boot-clean:
	$(U-BOOT_EXPORTS) $(MAKE) -C $(U-BOOT_PATH) clean

################################################################################
# Linux kernel
################################################################################
LINUX_DEFCONFIG_COMMON_ARCH := arm64
LINUX_DEFCONFIG_COMMON_FILES := \
		$(LINUX_PATH)/arch/arm64/configs/bcmrpi3_defconfig \
		$(CURDIR)/kconfigs/rpi3.conf

linux-defconfig: $(LINUX_PATH)/.config

LINUX_COMMON_FLAGS += ARCH=arm64

linux: linux-common
	$(MAKE) -C $(LINUX_PATH) $(LINUX_COMMON_FLAGS) INSTALL_MOD_PATH=$(MODULE_OUTPUT) modules_install

linux-defconfig-clean: linux-defconfig-clean-common

LINUX_CLEAN_COMMON_FLAGS += ARCH=arm64

linux-clean: linux-clean-common

LINUX_CLEANER_COMMON_FLAGS += ARCH=arm64

linux-cleaner: linux-cleaner-common

################################################################################
# OP-TEE
################################################################################
OPTEE_OS_COMMON_FLAGS += PLATFORM=rpi3
optee-os: optee-os-common

OPTEE_OS_CLEAN_COMMON_FLAGS += PLATFORM=rpi3
optee-os-clean: optee-os-clean-common

optee-client: optee-client-common

optee-client-clean: optee-client-clean-common

################################################################################
# Raspberry Pi 3 firmware
################################################################################
.PHONY: rpi3-firmware
rpi3-firmware:
ifeq ("$(wildcard $(ROOT)/out/$(RPI3_FIRMWARE_FILE).$(RPI3_FIRMWARE_FILE_EXT))","")
	echo "Downloading Raspberry Pi 3 firmware ..."
	mkdir -p $(ROOT)/out
	wget $(RPI3_FIRMWARE_URL)/$(RPI3_FIRMWARE_FILE).$(RPI3_FIRMWARE_FILE_EXT) -O $(ROOT)/out/$(RPI3_FIRMWARE_FILE).$(RPI3_FIRMWARE_FILE_EXT)
	unzip -a $(ROOT)/out/$(RPI3_FIRMWARE_FILE).$(RPI3_FIRMWARE_FILE_EXT) -d $(ROOT)
	mv $(ROOT)/firmware-$(RPI3_FIRMWARE_FILE) $(RPI3_STOCK_FW_PATH)
endif

.PHONY: rpi3-firmware-clean
rpi3-firmware-clean:
	rm -f $(ROOT)/out/$(RPI3_FIRMWARE_FILE).$(RPI3_FIRMWARE_FILE_EXT)

################################################################################
# xtest / optee_test
################################################################################
xtest: xtest-common

xtest-clean: xtest-clean-common

xtest-patch: xtest-patch-common

################################################################################
# Root FS
################################################################################
.PHONY: filelist-tee
filelist-tee:
	@echo "# xtest / optee_test" > $(GEN_ROOTFS_FILELIST)
	@find $(OPTEE_TEST_OUT_PATH) -type f -name "xtest" | sed 's/\(.*\)/file \/usr\/bin\/xtest \1 755 0 0/g' >> $(GEN_ROOTFS_FILELIST)
	@echo "# TAs" >> $(GEN_ROOTFS_FILELIST)
	@echo "dir /lib/optee_armtz 755 0 0" >> $(GEN_ROOTFS_FILELIST)
	@find $(OPTEE_TEST_OUT_PATH) -name "*.ta" | \
		sed 's/\(.*\)\/\(.*\)/file \/lib\/optee_armtz\/\2 \1\/\2 444 0 0/g' >> $(GEN_ROOTFS_FILELIST)
	@echo "# Secure storage dig" >> $(GEN_ROOTFS_FILELIST)
	@echo "dir /data 755 0 0" >> $(GEN_ROOTFS_FILELIST)
	@echo "dir /data/tee 755 0 0" >> $(GEN_ROOTFS_FILELIST)
	@echo "dir /data/tee 755 0 0" >> $(GEN_ROOTFS_FILELIST)
	@echo "dir /usr/bin 755 0 0" >> $(GEN_ROOTFS_FILELIST)
	@if [ -e $(OPTEE_GENDRV_MODULE) ]; then \
		echo "# OP-TEE device" >> $(GEN_ROOTFS_FILELIST); \
		echo "dir /lib/modules 755 0 0" >> $(GEN_ROOTFS_FILELIST); \
		echo "dir /lib/modules/$(call KERNEL_VERSION) 755 0 0" >> $(GEN_ROOTFS_FILELIST); \
		echo "file /lib/modules/$(call KERNEL_VERSION)/optee.ko $(OPTEE_GENDRV_MODULE) 755 0 0" >> $(GEN_ROOTFS_FILELIST); \
	fi
	@echo "# OP-TEE Client" >> $(GEN_ROOTFS_FILELIST)
	@echo "file /usr/include/tee_client_api.h $(OPTEE_CLIENT_EXPORT)/include/tee_client_api.h 755 0 0" >> $(GEN_ROOTFS_FILELIST)
	@echo "file /usr/include/teec_trace.h $(OPTEE_CLIENT_EXPORT)/include/teec_trace.h 755 0 0" >> $(GEN_ROOTFS_FILELIST)
	@echo "file /usr/bin/tee-supplicant $(OPTEE_CLIENT_EXPORT)/bin/tee-supplicant 755 0 0" >> $(GEN_ROOTFS_FILELIST)
	@echo "file /usr/lib/libteec.so.1.0 $(OPTEE_CLIENT_EXPORT)/lib/libteec.so.1.0 755 0 0" >> $(GEN_ROOTFS_FILELIST)
	@echo "slink /usr/lib/libteec.so.1 libteec.so.1.0 755 0 0" >> $(GEN_ROOTFS_FILELIST)
	@echo "slink /usr/lib/libteec.so libteec.so.1 755 0 0" >> $(GEN_ROOTFS_FILELIST)
	@echo "file /boot/u-boot-jtag.bin $(U-BOOT_JTAG_BIN) 755 0 0" >> $(GEN_ROOTFS_FILELIST)
	@echo "file /boot/optee.bin $(ARM_TF_BOOT) 755 0 0" >> $(GEN_ROOTFS_FILELIST)
	@echo "file /boot/Image $(LINUX_IMAGE) 755 0 0" >> $(GEN_ROOTFS_FILELIST)
	@echo "file /boot/bcm2837-rpi-3-b.dtb $(LINUX_DTB) 755 0 0" >> $(GEN_ROOTFS_FILELIST)
	@echo "file /boot/config.txt $(RPI3_BOOT_CONFIG) 755 0 0" >> $(GEN_ROOTFS_FILELIST)
	@echo "file /boot/uboot.env $(RPI3_UBOOT_ENV) 755 0 0" >> $(GEN_ROOTFS_FILELIST)
	@echo "dir  /lib/modules/$(call KERNEL_VERSION) 755 0 0" >> $(GEN_ROOTFS_FILELIST)

.PHONY: update_rootfs
update_rootfs:	arm-tf u-boot optee-client xtest filelist-tee
	cat $(GEN_ROOTFS_PATH)/filelist-final.txt $(GEN_ROOTFS_PATH)/filelist-tee.txt > $(GEN_ROOTFS_PATH)/filelist.tmp
	cd $(GEN_ROOTFS_PATH) && \
	        $(LINUX_PATH)/usr/gen_init_cpio $(GEN_ROOTFS_PATH)/filelist.tmp | gzip > $(GEN_ROOTFS_PATH)/filesystem.cpio.gz
	cd $(GEN_ROOTFS_PATH) && mkdir -p rootfs_overlay
	cd $(GEN_ROOTFS_PATH)/rootfs_overlay && gzip -d -c < $(GEN_ROOTFS_PATH)/filesystem.cpio.gz | cpio --extract --make-directories --no-preserve-owner
	mkdir -p $(MODULE_OUTPUT)
	mkdir -p $(MODULE_OUTPUT)/lib
	mkdir -p $(GEN_ROOTFS_PATH)/rootfs_overlay/etc/init.d
	cp $(RPI3_OPTEE_INIT) $(GEN_ROOTFS_PATH)/rootfs_overlay/etc/init.d/
	$(MAKE) -C $(LINUX_PATH) $(LINUX_COMMON_FLAGS) INSTALL_MOD_PATH=$(MODULE_OUTPUT) modules_install
	cd $(MODULE_OUTPUT)/lib && tar cf - firmware modules/$(call KERNEL_VERSION) | \
           (cd $(GEN_ROOTFS_PATH)/rootfs_overlay/lib ; tar xf -)
	cd $(RPI3_STOCK_FW_PATH) && tar cf - boot | (cd $(GEN_ROOTFS_PATH)/rootfs_overlay ; tar xf -)
	(rm -f $(GEN_ROOTFS_PATH)/rootfs_overlay/boot/kernel7.img > /dev/null 2>&1 || echo > /dev/null)
	(rm -f $(GEN_ROOTFS_PATH)/rootfs_overlay/boot/kernel.img > /dev/null 2>&1 || echo > /dev/null)
	(rm -f $(GEN_ROOTFS_PATH)/rootfs_overlay/boot/*.dtb > /dev/null 2>&1 || echo > /dev/null)
	cp $(LINUX_DTB) $(GEN_ROOTFS_PATH)/rootfs_overlay/boot
	cd $(GEN_ROOTFS_PATH)/rootfs_overlay && tar zcf $(RPI3_OPTEE_ROOTFS) .
	cd $(GEN_ROOTFS_PATH) && rm -rf rootfs_overlay
