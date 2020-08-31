################################################################################
# Paths to git projects and various binaries
################################################################################
CCACHE ?= $(shell which ccache) # Don't remove this comment (space is needed)

FIRMWARE_VERSION		?= firmware-imx-8.0

FIRMWARE_PATH			?= $(ROOT)/$(FIRMWARE_VERSION)
FLASH_BIN_PATH			?= $(ROOT)/imx-mkimage/iMX8M
LPDDR_BIN_PATH			?= $(FIRMWARE_PATH)/firmware/ddr/synopsys
MKIMAGE_PATH			?= $(ROOT)/imx-mkimage
TF_A_PATH			?= $(ROOT)/trusted-firmware-a
U-BOOT_PATH			?= $(ROOT)/u-boot

# Binaries
FIRMWARE_BIN			?= firmware-imx-8.0.bin
FLASH_BIN			?= $(FLASH_BIN_PATH)/flash.bin

# URLs
FIRMWARE_BIN_URL		?= https://www.nxp.com/lgfiles/NMG/MAD/YOCTO/$(FIRMWARE_BIN)

DEBUG = 0
PLATFORM ?= imx8mq

################################################################################
# Targets
################################################################################
all: tfa u-boot
clean: mkimage-clean tfa-clean u-boot-clean
dist-clean: clean setup-clean

include toolchain.mk

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
	rm $(ROOT)/mkimage_imx8

################################################################################
# Trusted Firmware A
################################################################################
TF_A_EXPORTS ?= \
	CROSS_COMPILE="$(CCACHE)$(AARCH64_CROSS_COMPILE)"

TF_A_DEBUG ?= $(DEBUG)
ifeq ($(TF_A_DEBUG),0)
TF_A_LOGLVL ?= 30
TF_A_OUT = $(TF_A_PATH)/build/$(PLATFORM)/release
else
TF_A_LOGLVL ?= 50
TF_A_OUT = $(TF_A_PATH)/build/$(PLATFORM)/debug
endif

TF_A_FLAGS ?= \
	PLAT=$(PLATFORM) bl31 \
	DEBUG=$(DEBUG)

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
setup: clone ddr-firmware

setup-clean:
	rm -rf ./$(FIRMWARE_VERSION)*

clone:
	git submodule update --init --recursive --jobs 8

# This is prebuilt binaries by NXP, download them and use them. Update path if
# it changes in the future.
ddr-firmware:
	@if [ ! -f "$(FIRMWARE_BIN)" ]; then wget $(FIRMWARE_BIN_URL); fi
	@if [ ! -d "$(FIRMWARE_PATH)" ]; then chmod 711 $(FIRMWARE_BIN) && ./$(FIRMWARE_BIN) --auto-accept; fi

################################################################################
# flash
################################################################################
flash: mkimage
	@lsblk -d -o "NAME,SIZE"
	@echo "\n  Find the name of your SD-card and type that below:"
	@echo "    !!! WARNING !!!     !!! WARNING !!!     !!! WARNING !!!"
	@echo "  Be careful to pick the correct name, since this will wipe the entire disc!"; \
		read -p "  name? " DISC; \
		echo "  You selected \"$$DISC\", correct? Otherwise hit ctrl+c withing 5 seconds";  \
		sleep 5; \
		echo "  execute this command manually:"; \
	        echo "  sudo dd if=$(FLASH_BIN) of=/dev/$$DISC bs=1k seek=33 conv=fsync"
