BASH := $(shell which bash)
ROOT ?= ${HOME}/devel/optee
$(shell mkdir -p $(ROOT))

################################################################################
# Paths to git projects and various binaries
################################################################################
ARM_TF_PATH			?= $(ROOT)/arm-trusted-firmware

EDK2_PATH 			?= $(ROOT)/edk2
EDK2_BIN 			?= $(EDK2_PATH)/Build/HiKey/RELEASE_GCC49/FV/BL33_AP_UEFI.fd

LINUX_PATH 			?= $(ROOT)/linux
define KERNEL_VERSION
$(shell cd $(LINUX_PATH) && make kernelversion)
endef
LINUX_CONFIG_ADDLIST		?= $(LINUX_PATH)/kernel.config

OPTEE_OS_PATH 			?= $(ROOT)/optee_os
OPTEE_OS_BIN 			?= $(OPTEE_OS_PATH)/out/arm-plat-hikey/core/tee.bin

OPTEE_CLIENT_PATH 		?= $(ROOT)/optee_client
OPTEE_CLIENT_EXPORT             ?= $(OPTEE_CLIENT_PATH)/out/export
OPTEE_LINUXDRIVER_PATH 		?= $(ROOT)/optee_linuxdriver

OPTEE_TEST_PATH 		?= $(ROOT)/optee_test
OPTEE_TEST_OUT_PATH 		?= $(ROOT)/out/optee_test

GEN_ROOTFS_PATH 		?= $(ROOT)/gen_rootfs
GEN_ROOTFS_FILELIST 		?= $(GEN_ROOTFS_PATH)/filelist-tee.txt

MCUIMAGE_BIN			?=$(ROOT)/out/mcuimage.bin
STRACE_PATH			?=$(ROOT)/strace
USBNETSH_PATH			?=$(ROOT)/out/usbnet.sh
LLOADER_PATH			?=$(ROOT)/l-loader

################################################################################
# Targets
################################################################################
all: mcuimage arm-tf edk2 linux optee-os optee-client optee-linuxdriver xtest strace update_rootfs boot-img lloader

clean: arm-tf-clean edk2-clean linux-clean optee-os-clean optee-client-clean optee-linuxdriver-clean xtest-clean strace-clean update_rootfs_clean boot-img-clean lloader-clean

cleaner: clean mcuimage-cleaner linux-cleaner strace-cleaner busybox-cleaner

-include toolchain.mk

mcuimage:
	@if [ ! -f "$(MCUIMAGE_BIN)" ]; then \
		curl https://builds.96boards.org/releases/hikey/linaro/binaries/15.05/mcuimage.bin -o $(MCUIMAGE_BIN); \
	fi

mcuimage-cleaner:
	rm -f $(MCUIMAGE_BIN)

arm-tf: mcuimage optee-os edk2
	CFLAGS="-O0 -gdwarf-2" \
	CROSS_COMPILE=$(AARCH64_NONE_CROSS_COMPILE) \
	BL32=$(OPTEE_OS_BIN) \
	BL33=$(EDK2_BIN) \
	NEED_BL30=yes \
	BL30=$(MCUIMAGE_BIN) \
	make -C $(ARM_TF_PATH) \
	       -j`getconf _NPROCESSORS_ONLN` \
	       DEBUG=0 \
	       PLAT=hikey \
	       SPD=opteed \
	       all fip

arm-tf-clean:
	CFLAGS="-O0 -gdwarf-2" \
        CROSS_COMPILE=$(AARCH64_NONE_CROSS_COMPILE) \
        BL32=$(OPTEE_OS_BIN) \
        BL33=$(EDK2_BIN) \
        NEED_BL30=yes \
        BL30=$(MCUIMAGE_BIN) \
        make -C $(ARM_TF_PATH) \
               -j`getconf _NPROCESSORS_ONLN` \
               DEBUG=0 \
               PLAT=hikey \
               SPD=opteed \
               clean

# Make sure edksetup.sh only will be called once
check-edk2:
	@if [ ! -f "$(EDK2_PATH)/Conf/target.txt" ]; then \
		cd $(EDK2_PATH); $(BASH) edksetup.sh; \
		make -C $(EDK2_PATH)/BaseTools clean; \
		make -C $(EDK2_PATH)/BaseTools; \
	fi

check-edk2-clean:
	cd $(EDK2_PATH); $(BASH) edksetup.sh; \
	make -C $(EDK2_PATH)/BaseTools clean;

edk2: check-edk2
	@if [ ! -f "$(EDK2_BIN)" ]; then \
		cd $(EDK2_PATH); \
		GCC49_AARCH64_PREFIX=$(AARCH64_NONE_CROSS_COMPILE) \
		make -C $(EDK2_PATH) \
			-f HisiPkg/HiKeyPkg/Makefile EDK2_ARCH=AARCH64 \
			EDK2_DSC=HisiPkg/HiKeyPkg/HiKey.dsc \
			EDK2_TOOLCHAIN=GCC49 EDK2_BUILD=RELEASE; \
	fi

edk2-clean: check-edk2-clean
	cd $(EDK2_PATH); \
	GCC49_AARCH64_PREFIX=$(AARCH64_NONE_CROSS_COMPILE) \
        make -C $(EDK2_PATH) \
        	-f HisiPkg/HiKeyPkg/Makefile EDK2_ARCH=AARCH64 \
        	EDK2_DSC=HisiPkg/HiKeyPkg/HiKey.dsc \
        	EDK2_TOOLCHAIN=GCC49 EDK2_BUILD=RELEASE clean

linux-defconfig:
	@if [ ! -f "$(LINUX_PATH)/.config" ]; then \
		echo "# This file is merged with the kernel's default configuration" > $(LINUX_CONFIG_ADDLIST); \
		echo "# Disabling BTRFS gets rid of the RAID6 performance tests at boot time." >> $(LINUX_CONFIG_ADDLIST); \
		echo "# This shaves off a few seconds." >> $(LINUX_CONFIG_ADDLIST); \
		echo "CONFIG_USB_NET_DM9601=y" >> $(LINUX_CONFIG_ADDLIST); \
		echo "# CONFIG_BTRFS_FS is not set" >> $(LINUX_CONFIG_ADDLIST); \
		cd $(LINUX_PATH); \
		ARCH=arm64 scripts/kconfig/merge_config.sh \
    			arch/arm64/configs/defconfig kernel.config; \
	fi

linux-defconfig-clean:
	@if [ -f "$(LINUX_PATH)/.config" ]; then \
		rm $(LINUX_PATH)/.config; \
	fi
	@if [ -f "$(LINUX_CONFIG_ADDLIST)" ]; then \
		rm $(LINUX_CONFIG_ADDLIST); \
	fi

linux-gen_init_cpio: linux-defconfig
	make -C $(LINUX_PATH)/usr ARCH=arm64 gen_init_cpio

linux: linux-defconfig
	make -C $(LINUX_PATH) \
		CROSS_COMPILE=$(AARCH64_NONE_CROSS_COMPILE) \
		LOCALVERSION= \
		ARCH=arm64 \
		-j`getconf _NPROCESSORS_ONLN` \
		Image modules dtbs

linux-clean: linux-defconfig-clean
	make -C $(LINUX_PATH) \
                CROSS_COMPILE=$(AARCH64_NONE_CROSS_COMPILE) \
                ARCH=arm64 \
                -j`getconf _NPROCESSORS_ONLN` \
                clean

linux-cleaner:
	make -C $(LINUX_PATH) \
                CROSS_COMPILE=$(AARCH64_NONE_CROSS_COMPILE) \
                LOCALVERSION= \
                ARCH=arm64 \
                -j`getconf _NPROCESSORS_ONLN` \
                mrproper

optee-os:
	make -C $(OPTEE_OS_PATH) \
		CROSS_COMPILE=$(AARCH32_CROSS_COMPILE) \
		CROSS_COMPILE_core=$(AARCH64_CROSS_COMPILE) \
		CFG_ARM64_core=y \
		PLATFORM=hikey \
		CFG_TEE_CORE_LOG_LEVEL=2 \
		DEBUG=0 \
		-j`getconf _NPROCESSORS_ONLN`

optee-os-clean:
	make -C $(OPTEE_OS_PATH) \
                CROSS_COMPILE=$(AARCH32_CROSS_COMPILE) \
                CROSS_COMPILE_core=$(AARCH64_CROSS_COMPILE) \
                CFG_ARM64_core=y \
                PLATFORM=hikey \
                CFG_TEE_CORE_LOG_LEVEL=2 \
                DEBUG=0 \
                -j`getconf _NPROCESSORS_ONLN` \
		clean

optee-client:
	make -C $(OPTEE_CLIENT_PATH) \
		CROSS_COMPILE=$(AARCH64_CROSS_COMPILE) \
		-j`getconf _NPROCESSORS_ONLN`

optee-client-clean:
	make -C $(OPTEE_CLIENT_PATH) \
		CROSS_COMPILE=$(AARCH64_CROSS_COMPILE) \
		-j`getconf _NPROCESSORS_ONLN` \
		clean

optee-linuxdriver: linux
	make -C $(LINUX_PATH) \
		V=0 \
		ARCH=arm64 \
		CROSS_COMPILE=$(AARCH64_CROSS_COMPILE) \
		LOCALVERSION= \
		M=$(OPTEE_LINUXDRIVER_PATH) modules

optee-linuxdriver-clean:
	make -C $(LINUX_PATH) \
                V=0 \
                ARCH=arm64 \
                CROSS_COMPILE=$(AARCH64_CROSS_COMPILE) \
                LOCALVERSION= \
                M=$(OPTEE_LINUXDRIVER_PATH) clean

xtest: optee-os optee-client
	@if [ -d "$(OPTEE_TEST_PATH)" ]; then \
		make -C $(OPTEE_TEST_PATH) \
		-j`getconf _NPROCESSORS_ONLN` \
		CROSS_COMPILE_HOST=$(AARCH64_CROSS_COMPILE) \
		CROSS_COMPILE_TA=$(AARCH32_CROSS_COMPILE) \
		TA_DEV_KIT_DIR=$(OPTEE_OS_PATH)/out/arm-plat-hikey/export-user_ta \
		O=$(OPTEE_TEST_OUT_PATH); \
	fi

xtest-clean:
	@if [ -d "$(OPTEE_TEST_PATH)" ]; then \
		rm -rf $(OPTEE_TEST_OUT_PATH); \
	fi

strace:
	@if [ ! -f $(STRACE_PATH)/strace ]; then \
		cd $(STRACE_PATH); \
		./bootstrap; \
		./configure --host=aarch64-linux-gnu CC=$(AARCH64_CROSS_COMPILE)gcc LD=$(AARCH64_CROSS_COMPILE)ld; \
		CC=$(AARCH64_CROSS_COMPILE)gcc LD=$(AARCH64_CROSS_COMPILE)ld \
			make -C $(STRACE_PATH); \
	fi

strace-clean:
	@if [ -f $(STRACE_PATH)/strace ]; then \
		CC=$(AARCH64_CROSS_COMPILE)gcc LD=$(AARCH64_CROSS_COMPILE)ld \
			make -C $(STRACE_PATH) clean; \
	fi

strace-cleaner:
	rm -f $(STRACE_PATH)/Makefile $(STRACE_PATH)/configure

filelist-tee: xtest
	@if [ ! -f "$(USBNETSH_PATH)" ]; then \
		echo "#!/bin/sh" > $(USBNETSH_PATH); \
		echo "#" >> $(USBNETSH_PATH); \
		echo "# Script to bring eth0 up and start DHCP client" >> $(USBNETSH_PATH); \
		echo "# Run it after plugging a USB ethernet adapter, for instance" >> $(USBNETSH_PATH); \
		echo "" >> $(USBNETSH_PATH); \
		echo "ip link set eth0 up" >> $(USBNETSH_PATH); \
		echo "udhcpc -i eth0 -s /etc/udhcp/simple.script" >> $(USBNETSH_PATH); \
	fi

	@echo "# Files to add to filesystem.cpio.gz" > $(GEN_ROOTFS_FILELIST)
	@echo "# Syntax: same as gen_rootfs/filelist.txt" >> $(GEN_ROOTFS_FILELIST)
	@echo "" >> $(GEN_ROOTFS_FILELIST)

	@echo "# Script called by udhcpc (DHCP client) to update the network configuration" >> $(GEN_ROOTFS_FILELIST)
	@echo "dir /etc/udhcp 755 0 0" >> $(GEN_ROOTFS_FILELIST)
	@echo "file /etc/udhcp/simple.script $(GEN_ROOTFS_PATH)/busybox/examples/udhcp/simple.script 755 0 0" >> $(GEN_ROOTFS_FILELIST)
	@echo "" >> $(GEN_ROOTFS_FILELIST)

	@echo "# Run this manually after plugging a USB to ethernet adapter" >> $(GEN_ROOTFS_FILELIST)
	@echo "file /usbnet.sh $(USBNETSH_PATH) 755 0 0" >> $(GEN_ROOTFS_FILELIST)
	@echo "" >> $(GEN_ROOTFS_FILELIST)

	@echo "# xtest / optee_test" >> $(GEN_ROOTFS_FILELIST)
	@find $(OPTEE_TEST_OUT_PATH) -type f -name "xtest" | sed 's/\(.*\)/file \/bin\/xtest \1 755 0 0/g' >> $(GEN_ROOTFS_FILELIST)
	@echo "" >> $(GEN_ROOTFS_FILELIST)

	@echo "# TAs" >> $(GEN_ROOTFS_FILELIST)
	@echo "dir /lib/optee_armtz 755 0 0" >> $(GEN_ROOTFS_FILELIST)
	@find $(OPTEE_TEST_OUT_PATH) -name "*.ta" | \
		sed 's/\(.*\)\/\(.*\)/file \/lib\/optee_armtz\/\2 \1\/\2 444 0 0/g' >> $(GEN_ROOTFS_FILELIST)
	@echo "" >> $(GEN_ROOTFS_FILELIST)

	@echo "# Secure storage dig" >> $(GEN_ROOTFS_FILELIST)
	@echo "dir /data 755 0 0" >> $(GEN_ROOTFS_FILELIST)
	@echo "dir /data/tee 755 0 0" >> $(GEN_ROOTFS_FILELIST)
	@echo "" >> $(GEN_ROOTFS_FILELIST)

	@echo "# OP-TEE device" >> $(GEN_ROOTFS_FILELIST)
	@echo "dir /lib/modules 755 0 0" >> $(GEN_ROOTFS_FILELIST)
	@echo "dir /lib/modules/$(call KERNEL_VERSION) 755 0 0" >> $(GEN_ROOTFS_FILELIST)
	@echo "file /lib/modules/$(call KERNEL_VERSION)/optee.ko $(OPTEE_LINUXDRIVER_PATH)/core/optee.ko 755 0 0" >> $(GEN_ROOTFS_FILELIST)
	@echo "file /lib/modules/$(call KERNEL_VERSION)/optee_armtz.ko $(OPTEE_LINUXDRIVER_PATH)/armtz/optee_armtz.ko 755 0 0" >> $(GEN_ROOTFS_FILELIST)
	@echo "" >> $(GEN_ROOTFS_FILELIST)

	@echo "# OP-TEE Client" >> $(GEN_ROOTFS_FILELIST)
	@echo "file /bin/tee-supplicant $(OPTEE_CLIENT_EXPORT)/bin/tee-supplicant 755 0 0" >> $(GEN_ROOTFS_FILELIST)
	@echo "dir /lib/aarch64-linux-gnu 755 0 0" >> $(GEN_ROOTFS_FILELIST)
	@echo "file /lib/aarch64-linux-gnu/libteec.so.1.0 $(OPTEE_CLIENT_EXPORT)/lib/libteec.so.1.0 755 0 0" >> $(GEN_ROOTFS_FILELIST)
	@echo "slink /lib/aarch64-linux-gnu/libteec.so.1 libteec.so.1.0 755 0 0" >> $(GEN_ROOTFS_FILELIST)
	@echo "slink /lib/aarch64-linux-gnu/libteec.so libteec.so.1 755 0 0" >> $(GEN_ROOTFS_FILELIST)
	@echo "" >> $(GEN_ROOTFS_FILELIST)

	@echo "# strace tool" >> $(GEN_ROOTFS_FILELIST)
	@echo "file /bin/strace $(STRACE_PATH)/strace 755 0 0" >> $(GEN_ROOTFS_FILELIST)

busybox:
	@if [ ! -d "$(GEN_ROOTFS_PATH)/build" ]; then \
		cd $(GEN_ROOTFS_PATH); \
		CC_DIR=$(AARCH64_PATH) \
		PATH=${PATH}:$(LINUX_PATH)/usr \
		$(GEN_ROOTFS_PATH)/generate-cpio-rootfs.sh hikey nocpio; \
	fi

busybox-cleaner:
	rm -rf $(GEN_ROOTFS_PATH)/busybox

update_rootfs: busybox optee-client optee-linuxdriver filelist-tee linux-gen_init_cpio strace
	cat $(GEN_ROOTFS_PATH)/filelist-final.txt | sed '/fbtest/d' > $(GEN_ROOTFS_PATH)/temp.txt
	mv $(GEN_ROOTFS_PATH)/temp.txt $(GEN_ROOTFS_PATH)/filelist-final.txt
	cat $(GEN_ROOTFS_PATH)/filelist-final.txt $(GEN_ROOTFS_PATH)/filelist-tee.txt > $(GEN_ROOTFS_PATH)/filelist.tmp
	cd $(GEN_ROOTFS_PATH); \
	        $(LINUX_PATH)/usr/gen_init_cpio $(GEN_ROOTFS_PATH)/filelist.tmp | gzip > $(GEN_ROOTFS_PATH)/filesystem.cpio.gz

update_rootfs_clean:
	cd $(GEN_ROOTFS_PATH); \
	rm -f $(GEN_ROOTFS_PATH)/filesystem.cpio.gz $(GEN_ROOTFS_PATH)/filelist.tmp $(GEN_ROOTFS_PATH)/filelist-final.txt; \
	if [ -f "$(USBNETSH_PATH)" ]; then rm $(USBNETSH_PATH); fi;

boot-img: linux update_rootfs
	sudo -p "[sudo] Password:" true
	if [ -d mntdir ] ; then sudo rm -rf mntdir ; fi
	mkdir -p mntdir
	dd if=/dev/zero of=boot-fat.uefi.img bs=512 count=131072 status=none
	sudo mkfs.fat -n "BOOT IMG" boot-fat.uefi.img >/dev/null
	sudo mount -o loop,rw,sync boot-fat.uefi.img mntdir
	sudo cp $(LINUX_PATH)/arch/arm64/boot/Image $(LINUX_PATH)/arch/arm64/boot/dts/hi6220-hikey.dtb mntdir/
	sudo cp $(GEN_ROOTFS_PATH)/filesystem.cpio.gz mntdir/initrd.img
	sudo cp $(EDK2_PATH)/Build/HiKey/RELEASE_GCC49/AARCH64/AndroidFastbootApp.efi mntdir/fastboot.efi
	sudo umount mntdir
	sudo rm -rf mntdir
	mv boot-fat.uefi.img $(ROOT)/out

boot-img-clean:
	rm -f $(ROOT)/out/boot-fat.uefi.img

lloader: arm-tf
	ln -s $(ARM_TF_PATH)/build/hikey/release/bl1.bin $(LLOADER_PATH)/bl1.bin;
	make -C $(LLOADER_PATH);

lloader-clean:
	if [ -f "$(LLOADER_PATH)/bl1.bin" ]; then \
		unlink $(LLOADER_PATH)/bl1.bin; \
	fi
	make -C $(LLOADER_PATH) clean;
	if [ -f "$(LLOADER_PATH)/ptable.img" ]; then \
		rm -f $(LLOADER_PATH)/ptable.img; \
		rm -f $(LLOADER_PATH)/prm_ptable.img; \
		rm -f $(LLOADER_PATH)/sec_ptable.img; \
	fi
