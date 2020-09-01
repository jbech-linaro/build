################################################################################
# Paths to git projects and various binaries
################################################################################
CCACHE ?= $(shell which ccache) # Don't remove this comment (space is needed)

FIRMWARE_VERSION		?= firmware-imx-8.0

BR_PATH				?= $(ROOT)/buildroot
BUILD_PATH			?= $(ROOT)/build
FIRMWARE_PATH			?= $(ROOT)/$(FIRMWARE_VERSION)
FLASH_BIN_PATH			?= $(ROOT)/imx-mkimage/iMX8M
LINUX_PATH			?= $(ROOT)/linux
LPDDR_BIN_PATH			?= $(FIRMWARE_PATH)/firmware/ddr/synopsys
MKIMAGE_PATH			?= $(ROOT)/imx-mkimage
TF_A_PATH			?= $(ROOT)/trusted-firmware-a
U-BOOT_PATH			?= $(ROOT)/u-boot

# Binaries
FIRMWARE_BIN			?= firmware-imx-8.0.bin
FLASH_BIN			?= $(FLASH_BIN_PATH)/flash.bin
IMX8_IMAGE			?= $(BUILD_PATH)/imx8mqevk.img

# URLs
FIRMWARE_BIN_URL		?= https://www.nxp.com/lgfiles/NMG/MAD/YOCTO/$(FIRMWARE_BIN)

DEBUG				?= 0
PLATFORM			?= imx8mq

################################################################################
# Targets
################################################################################
all: buildroot linux tfa u-boot mkimage
clean: buildroot-clean flash-image-clean linux-clean mkimage-clean tfa-clean u-boot-clean
dist-clean: clean ddr-firmare-clean

include toolchain.mk

################################################################################
# Buildroot
################################################################################
BR_DEFCONFIG_FILES := $(BR_PATH)/configs/freescale_imx8mqevk_defconfig \
		      $(BUILD_PATH)/kconfigs/br_imx8.conf

$(BR_PATH)/.config:
	cd $(BR_PATH) && \
		support/kconfig/merge_config.sh \
		$(BR_DEFCONFIG_FILES)

# Note that the AARCH64_PATH here is necessary and it's used in the
# build/kconfigs/br_imx8.conf file where a variable is used to find and set the
# correct toolchain to use.
buildroot: buildroot-defconfig
	make -C $(BR_PATH) AARCH64_PATH=$(AARCH64_PATH) BR2_CCACHE_DIR="$(CCACHE_DIR)"

.PHONY: buildroot-defconfig
buildroot-defconfig: $(BR_PATH)/.config

buildroot-clean:
	cd $(BR_PATH) && git clean -xdf

################################################################################
# imx-mkimage
################################################################################
mkimage: u-boot tfa ddr-firmware
	ln -sf $(LPDDR_BIN_PATH)/lpddr4_pmu_train_*.bin $(MKIMAGE_PATH)/iMX8M/
	make -C $(MKIMAGE_PATH) SOC=iMX8M flash_spl_uboot
#> +If you want to run with HDMI, copy signed_hdmi_imx8m.bin to imx-mkimage/iMX8M
#> +make SOC=iMX8M flash_spl_uboot or make SOC=iMX8M flash_hdmi_spl_uboot to
#> +generate flash.bin.
mkimage-clean:
	cd $(MKIMAGE_PATH) && git clean -xdf
	rm -f $(ROOT)/mkimage_imx8

################################################################################
# Linux kernel
################################################################################
LINUX_DEFCONFIG_FILES := $(LINUX_PATH)/arch/arm64/configs/imx_v8_defconfig \
			 $(BUILD_PATH)/kconfigs/imx8.conf


$(LINUX_PATH)/.config: $(LINUX_DEFCONFIG_FILES)
	cd $(LINUX_PATH) && \
                ARCH=arm64 \
                scripts/kconfig/merge_config.sh $(LINUX_DEFCONFIG_FILES)

.PHONY: linux-defconfig
linux-defconfig: $(LINUX_PATH)/.config

linux: linux-defconfig
	make -C $(LINUX_PATH) ARCH=arm64 CROSS_COMPILE="$(CCACHE)$(AARCH64_CROSS_COMPILE)" Image dtbs

linux-clean:
	cd $(LINUX_PATH) && git clean -xdf

################################################################################
# Trusted Firmware A
################################################################################
TF_A_EXPORTS 		?= CROSS_COMPILE="$(CCACHE)$(AARCH64_CROSS_COMPILE)"
TF_A_DEBUG 		?= $(DEBUG)
ifeq ($(TF_A_DEBUG),0)
TF_A_LOGLVL		?= 30
TF_A_OUT		= $(TF_A_PATH)/build/$(PLATFORM)/release
else
TF_A_LOGLVL		?= 50
TF_A_OUT		= $(TF_A_PATH)/build/$(PLATFORM)/debug
endif

TF_A_FLAGS ?=		PLAT=$(PLATFORM) bl31 DEBUG=$(DEBUG)

tfa: u-boot
	$(TF_A_EXPORTS) $(MAKE) -C $(TF_A_PATH) $(TF_A_FLAGS) all fip
	ln -sf $(TF_A_OUT)/bl31.bin $(MKIMAGE_PATH)/iMX8M/

tfa-clean:
	cd $(TF_A_PATH) && git clean -xdf

################################################################################
# U-boot
################################################################################
U-BOOT_EXPORTS ?= CROSS_COMPILE="$(CCACHE)$(AARCH64_CROSS_COMPILE)"

.PHONY: u-boot
u-boot:
	$(U-BOOT_EXPORTS) $(MAKE) -C $(U-BOOT_PATH) imx8mq_evk_defconfig
	$(U-BOOT_EXPORTS) $(MAKE) -C $(U-BOOT_PATH) all
	ln -sf $(U-BOOT_PATH)/u-boot-nodtb.bin                 $(MKIMAGE_PATH)/iMX8M/
	ln -sf $(U-BOOT_PATH)/spl/u-boot-spl.bin               $(MKIMAGE_PATH)/iMX8M/
	ln -sf $(U-BOOT_PATH)/arch/arm/dts/fsl-imx8mq-evk.dtb  $(MKIMAGE_PATH)/iMX8M/
	ln -sf $(U-BOOT_PATH)/tools/mkimage                    $(MKIMAGE_PATH)/iMX8M/mkimage_uboot

.PHONY: u-boot-clean
u-boot-clean:
	cd $(U-BOOT_PATH) && git clean -xdf

.PHONY: u-boot-cscope
u-boot-cscope:
	$(U-BOOT_EXPORTS) $(MAKE) -C $(U-BOOT_PATH) cscope

################################################################################
# Setup
################################################################################
# This is prebuilt binaries by NXP, download them and use them. Update path if
# it changes in the future.
ddr-firmware:
	@if [ ! -f "$(FIRMWARE_BIN)" ]; then wget $(FIRMWARE_BIN_URL); fi
	@if [ ! -d "$(FIRMWARE_PATH)" ]; then chmod 711 $(FIRMWARE_BIN) && ./$(FIRMWARE_BIN) --auto-accept; fi

ddr-firmware-clean:
	rm -rf $(FIRMWARE_BIN) $(FIRMWARE_PATH)

################################################################################
# flash
################################################################################
# Intentionally left out targets, since I want this to only flash. It's up to
# the user to run make before running make flash-image
flash-image:
	@rm -f $(IMX8_IMAGE)
	@cd $(BUILD_PATH) && ./create_image.sh
	@echo ""
	@echo "Devices / disks available on the local computer"
	@lsblk -d -o "NAME,SIZE"
	@echo ""
	@echo "Run:"
	@echo " sudo dd if=$(IMX8_IMAGE) | pv | sudo dd of=<sd-card-device> bs=1M conv=fsync"
	@echo " <sd-card-device> should be replaced with something like /dev/sdj for example"

flash-image-clean:
	rm -f $(IMX8_IMAGE)


flash-bootloader: mkimage
	@lsblk -d -o "NAME,SIZE"
	@echo "\n  Find the name of your SD-card and type that below:"
	@echo "    !!! WARNING !!!     !!! WARNING !!!     !!! WARNING !!!"
	@echo "  Be careful to pick the correct name, since this will wipe the entire disc!"; \
		read -p "  name? " DISC; \
		echo "  You selected \"$$DISC\", correct? Otherwise hit ctrl+c within 5 seconds";  \
		sleep 5; \
		echo "  execute this command manually:"; \
	        echo "  sudo dd if=$(FLASH_BIN) of=/dev/$$DISC bs=1k seek=33 conv=fsync"
