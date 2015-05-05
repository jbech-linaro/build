BASH := $(shell which bash)
ROOT ?= ${HOME}/devel/optee
$(shell mkdir -p $(ROOT))

-include toolchain.mk

################################################################################
# Paths to git projects and various binaries
################################################################################
ARM_TF_PATH			?= $(ROOT)/arm-trusted-firmware

EDK2_PATH 			?= $(ROOT)/edk2
EDK2_BIN 			?= $(EDK2_PATH)/Build/ArmVExpress-FVP-AArch64/RELEASE_GCC49/FV/FVP_AARCH64_EFI.fd

LINUX_PATH 			?= $(ROOT)/linux
define KERNEL_VERSION
$(shell cd $(LINUX_PATH) && make kernelversion)
endef

OPTEE_OS_PATH 			?= $(ROOT)/optee_os
OPTEE_OS_BIN 			?= $(OPTEE_OS_PATH)/out/arm-plat-vexpress/core/tee.bin

OPTEE_CLIENT_PATH 		?= $(ROOT)/optee_client
OPTEE_LINUXDRIVER_PATH 		?= $(ROOT)/optee_linuxdriver

OPTEE_TEST_PATH 		?= $(ROOT)/optee_test
OPTEE_TEST_OUT_PATH 		?= $(ROOT)/out/optee_test

GEN_ROOTFS_PATH 		?= $(ROOT)/gen_rootfs
GEN_ROOTFS_FILELIST 		?= $(GEN_ROOTFS_PATH)/filelist-tee.txt

FOUNDATION_PATH			?= $(ROOT)/Foundation_Platformpkg

################################################################################
# Targets
################################################################################
all:

arm-tf: optee-os edk2
	CFLAGS="-O0 -gdwarf-2" \
	CROSS_COMPILE=$(AARCH64_NONE_CROSS_COMPILE) \
	BL32=$(OPTEE_OS_BIN) \
	BL33=$(EDK2_BIN) \
	make -C $(ARM_TF_PATH) \
	       -j`getconf _NPROCESSORS_ONLN` \
	       DEBUG=0 \
	       FVP_TSP_RAM_LOCATION=tdram \
	       FVP_SHARED_DATA_LOCATION=tdram \
	       PLAT=fvp \
	       SPD=opteed \
	       all fip

# Make sure edksetup.sh only will be called once
check-edk2:
	@if [ ! -f "$(EDK2_PATH)/Conf/target.txt" ]; then \
		cd $(EDK2_PATH); $(BASH) edksetup.sh; \
		make -C $(EDK2_PATH)/BaseTools clean; \
		make -C $(EDK2_PATH)/BaseTools;  \
	fi

edk2: check-edk2
	GCC49_AARCH64_PREFIX=$(AARCH64_NONE_CROSS_COMPILE) \
	     make -C $(EDK2_PATH) \
	     -f ArmPlatformPkg/Scripts/Makefile EDK2_ARCH=AARCH64 \
	     EDK2_DSC=ArmPlatformPkg/ArmVExpressPkg/ArmVExpress-FVP-AArch64.dsc \
	     EDK2_TOOLCHAIN=GCC49 EDK2_BUILD=RELEASE \
	     EDK2_MACROS="-n 6 -D ARM_FOUNDATION_FVP=1"

# FIXME: There's a magic sed taking place in the setup script today
linux-defconfig:
	make -C $(LINUX_PATH) ARCH=arm64 defconfig

linux: linux-defconfig
	make -C $(LINUX_PATH) \
		CROSS_COMPILE=$(AARCH64_NONE_CROSS_COMPILE) \
		LOCALVERSION= \
		ARCH=arm64 \
		-j`getconf _NPROCESSORS_ONLN`

optee-os:
	make -C $(OPTEE_OS_PATH) \
		CROSS_COMPILE=$(AARCH32_CROSS_COMPILE) \
		PLATFORM=vexpress \
		PLATFORM_FLAVOR=fvp \
		CFG_TEE_CORE_LOG_LEVEL=4 \
		DEBUG=0 \
		-j`getconf _NPROCESSORS_ONLN`

optee-client:
	make -C $(OPTEE_CLIENT_PATH) \
		CROSS_COMPILE=$(AARCH64_CROSS_COMPILE) \
		-j`getconf _NPROCESSORS_ONLN`

optee-linuxdriver: linux
	make -C $(LINUX_PATH) \
		V=0 \
		ARCH=arm64 \
		CROSS_COMPILE=$(AARCH64_CROSS_COMPILE) \
		LOCALVERSION= \
		M=$(OPTEE_LINUXDRIVER_PATH) modules

generate-dtb:
	$(LINUX_PATH)/scripts/dtc/dtc \
		-O dtb \
		-o $(FOUNDATION_PATH)/fdt.dtb \
		-b 0 \
		-i . $(OPTEE_LINUXDRIVER_PATH)/fdts/fvp-foundation-gicv2-psci.dts

.PHONY: filelist-tee
filelist-tee:
	@echo "# xtest / optee_test" > $(GEN_ROOTFS_FILELIST)
	@find $(OPTEE_TEST_OUT_PATH) -type f -name "xtest" | sed 's/\(.*\)/file \/bin\/xtest \1 755 0 0/g' >> $(GEN_ROOTFS_FILELIST)
	@echo "# TAs" >> $(GEN_ROOTFS_FILELIST)
	@echo "dir /lib/optee_armtz 755 0 0" >> $(GEN_ROOTFS_FILELIST)
	@find $(OPTEE_TEST_OUT_PATH) -name "*.ta" | \
		sed 's/\(.*\)\/\(.*\)/file \/lib\/optee_armtz\/\2 \1\/\2 444 0 0/g' >> $(GEN_ROOTFS_FILELIST)
	@echo "# Secure storage dig" >> $(GEN_ROOTFS_FILELIST)
	@echo "dir /data 755 0 0" >> $(GEN_ROOTFS_FILELIST)
	@echo "dir /data/tee 755 0 0" >> $(GEN_ROOTFS_FILELIST)
	@echo "# OP-TEE device" >> $(GEN_ROOTFS_FILELIST)
	@echo "dir /lib/modules 755 0 0" >> $(GEN_ROOTFS_FILELIST)
	@echo "dir /lib/modules/$(call KERNEL_VERSION) 755 0 0" >> $(GEN_ROOTFS_FILELIST)
	@echo "file /lib/modules/$(call KERNEL_VERSION)/optee.ko $(OPTEE_LINUXDRIVER_PATH)/core/optee.ko 755 0 0" >> $(GEN_ROOTFS_FILELIST)
	@echo "file /lib/modules/$(call KERNEL_VERSION)/optee_armtz.ko $(OPTEE_LINUXDRIVER_PATH)/armtz/optee_armtz.ko 755 0 0" >> $(GEN_ROOTFS_FILELIST)
	@echo "# OP-TEE Client" >> $(GEN_ROOTFS_FILELIST)
	@echo "file /bin/tee-supplicant $(OPTEE_CLIENT_PATH)/out/export/bin/tee-supplicant 755 0 0" >> $(GEN_ROOTFS_FILELIST)
	@echo "dir /lib/aarch64-linux-gnu 755 0 0" >> $(GEN_ROOTFS_FILELIST)
	@echo "file /lib/aarch64-linux-gnu/libteec.so.1.0 $(OPTEE_CLIENT_PATH)/out/export/lib/libteec.so.1.0 755 0 0" >> $(GEN_ROOTFS_FILELIST)
	@echo "slink /lib/aarch64-linux-gnu/libteec.so.1 libteec.so.1.0 755 0 0" >> $(GEN_ROOTFS_FILELIST)
	@echo "slink /lib/aarch64-linux-gnu/libteec.so libteec.so.1 755 0 0" >> $(GEN_ROOTFS_FILELIST)

gen_rootfs: filelist-tee
	cd $(GEN_ROOTFS_PATH); \
		CC_DIR=$(AARCH64_PATH) \
		PATH=${PATH}:$(LINUX_PATH)/usr \
		$(GEN_ROOTFS_PATH)/generate-cpio-rootfs.sh fvp-aarch64
	cat $(GEN_ROOTFS_PATH)/filelist-final.txt $(GEN_ROOTFS_PATH)/filelist-tee.txt > $(GEN_ROOTFS_PATH)/filelist.tmp
	cd $(GEN_ROOTFS_PATH); \
		$(LINUX_PATH)/usr/gen_init_cpio $(GEN_ROOTFS_PATH)/filelist.tmp | gzip > $(GEN_ROOTFS_PATH)/filesystem.cpio.gz

update_rootfs: filelist-tee
	cd $(GEN_ROOTFS_PATH); \
	        $(LINUX_PATH)/usr/gen_init_cpio $(GEN_ROOTFS_PATH)/filelist.tmp | gzip > $(GEN_ROOTFS_PATH)/filesystem.cpio.gz

check-xtest:
	@if [ ! -d "$(OPTEE_TEST_PATH)" ]; then \
		echo "optee_test is missing!"; \
		false; \
	fi

xtest: check-xtest optee-os optee-client
		make -C $(OPTEE_TEST_PATH) \
		-j`getconf _NPROCESSORS_ONLN` \
		CROSS_COMPILE_HOST=$(AARCH64_CROSS_COMPILE) \
		CROSS_COMPILE_TA=$(AARCH32_CROSS_COMPILE) \
		TA_DEV_KIT_DIR=$(OPTEE_OS_PATH)/out/arm-plat-vexpress/export-user_ta \
		O=$(OPTEE_TEST_OUT_PATH)

run: update_rootfs
	ln -sf $(LINUX_PATH)/arch/arm64/boot/Image $(FOUNDATION_PATH)
	ln -sf $(GEN_ROOTFS_PATH)/filesystem.cpio.gz $(FOUNDATION_PATH)
	cd $(FOUNDATION_PATH); \
	$(FOUNDATION_PATH)/models/Linux64_GCC-4.1/Foundation_Platform \
	--cores=4 \
	--no-secure-memory \
	--visualization \
	--gicv3 \
	--data="$(ARM_TF_PATH)/build/fvp/release/bl1.bin"@0x0 \
	--data="$(ARM_TF_PATH)/build/fvp/release/fip.bin"@0x8000000
