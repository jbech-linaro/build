BASH := $(shell which bash)
ROOT ?= ${HOME}/devel/optee
$(shell mkdir -p $(ROOT))

################################################################################
# Paths to git projects and various binaries
################################################################################
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

BIOS_QEMU_PATH			?= $(ROOT)/bios_qemu_tz_arm

QEMU_PATH			?= $(ROOT)/qemu

SOC_TERM_PATH			?= $(ROOT)/soc_term

################################################################################
# Targets
################################################################################
all: bios-qemu linux optee-os optee-client optee-linuxdriver qemu soc-term xtest

-include toolchain.mk

bios-qemu: linux update_rootfs optee-os
	make -C $(BIOS_QEMU_PATH) \
		CROSS_COMPILE=$(AARCH32_CROSS_COMPILE) \
		O=$(ROOT)/out/bios-qemu \
		BIOS_NSEC_BLOB=$(LINUX_PATH)/arch/arm/boot/zImage \
		BIOS_NSEC_ROOTFS=$(GEN_ROOTFS_PATH)/filesystem.cpio.gz \
		BIOS_SECURE_BLOB=$(OPTEE_OS_BIN) \
		PLATFORM_FLAVOR=virt

linux-defconfig:
	# Temporary fix until we have the driver integrated in the kernel
	if [ ! -f $(LINUX_PATH)/.config ]; then \
		sed -i '/config ARM$$/a select DMA_SHARED_BUFFER' $(LINUX_PATH)/arch/arm/Kconfig; \
	fi
	make -C $(LINUX_PATH) ARCH=arm vexpress_defconfig

linux: linux-defconfig
	make -C $(LINUX_PATH) \
		CROSS_COMPILE=$(AARCH32_CROSS_COMPILE) \
		LOCALVERSION= \
		ARCH=arm \
		-j`getconf _NPROCESSORS_ONLN`

optee-os:
	make -C $(OPTEE_OS_PATH) \
		CROSS_COMPILE=$(AARCH32_CROSS_COMPILE) \
		PLATFORM=vexpress \
		PLATFORM_FLAVOR=qemu_virt \
		CFG_TEE_CORE_LOG_LEVEL=4 \
		DEBUG=0 \
		-j`getconf _NPROCESSORS_ONLN`

optee-client:
	make -C $(OPTEE_CLIENT_PATH) \
		CROSS_COMPILE=$(AARCH32_CROSS_COMPILE) \
		-j`getconf _NPROCESSORS_ONLN`

optee-linuxdriver: linux
	make -C $(LINUX_PATH) \
		V=0 \
		ARCH=arm \
		CROSS_COMPILE=$(AARCH32_CROSS_COMPILE) \
		LOCALVERSION= \
		M=$(OPTEE_LINUXDRIVER_PATH) modules

qemu:
	cd $(QEMU_PATH); ./configure --target-list=arm-softmmu
	make -C $(QEMU_PATH) \
		-j`getconf _NPROCESSORS_ONLN`

soc-term:
	make -C $(SOC_TERM_PATH)

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
	@echo "dir /lib/arm-linux-gnueabihf 755 0 0" >> $(GEN_ROOTFS_FILELIST)
	@echo "file /lib/arm-linux-gnueabihf/libteec.so.1.0 $(OPTEE_CLIENT_PATH)/out/export/lib/libteec.so.1.0 755 0 0" >> $(GEN_ROOTFS_FILELIST)
	@echo "slink /lib/arm-linux-gnueabihf/libteec.so.1 libteec.so.1.0 755 0 0" >> $(GEN_ROOTFS_FILELIST)
	@echo "slink /lib/arm-linux-gnueabihf/libteec.so libteec.so.1 755 0 0" >> $(GEN_ROOTFS_FILELIST)

busybox:
	@if [ ! -d "$(GEN_ROOTFS_PATH)/build" ]; then \
		cd $(GEN_ROOTFS_PATH); \
			CC_DIR=$(AARCH32_PATH) \
			PATH=${PATH}:$(LINUX_PATH)/usr \
			$(GEN_ROOTFS_PATH)/generate-cpio-rootfs.sh vexpress; \
	fi

update_rootfs: busybox optee-client optee-linuxdriver xtest filelist-tee
	cat $(GEN_ROOTFS_PATH)/filelist-final.txt $(GEN_ROOTFS_PATH)/filelist-tee.txt > $(GEN_ROOTFS_PATH)/filelist.tmp
	cd $(GEN_ROOTFS_PATH); \
	        $(LINUX_PATH)/usr/gen_init_cpio $(GEN_ROOTFS_PATH)/filelist.tmp | gzip > $(GEN_ROOTFS_PATH)/filesystem.cpio.gz

xtest: optee-os optee-client
	@if [ -d "$(OPTEE_TEST_PATH)" ]; then \
		make -C $(OPTEE_TEST_PATH) \
		-j`getconf _NPROCESSORS_ONLN` \
		CROSS_COMPILE_HOST=$(AARCH32_CROSS_COMPILE) \
		CROSS_COMPILE_TA=$(AARCH32_CROSS_COMPILE) \
		TA_DEV_KIT_DIR=$(OPTEE_OS_PATH)/out/arm-plat-vexpress/export-user_ta \
		O=$(OPTEE_TEST_OUT_PATH); \
	fi

run: bios-qemu
	@echo "Run QEMU"
	@echo QEMU is now waiting to start the execution
	@echo Start execution with either a \'c\' followed by \<enter\> in the QEMU console or
	@echo attach a debugger and continue from there.
	@echo
	@echo To run xtest paste the following on the serial 0 prompt
	@echo modprobe optee_armtz
	@echo sleep 0.1
	@echo tee-supplicant\&
	@echo sleep 0.1
	@echo xtest
	@echo
	@echo To run a single test case replace the xtest command with for instance
	@echo xtest 2001
	@gnome-terminal -e "$(BASH) -c '$(SOC_TERM_PATH)/soc_term 54320; exec /bin/bash -i'" --title="Normal world"
	@gnome-terminal -e "$(BASH) -c '$(SOC_TERM_PATH)/soc_term 54321; exec /bin/bash -i'" --title="Secure world"
	@sleep 1
	$(QEMU_PATH)/arm-softmmu/qemu-system-arm \
		-nographic \
		-serial tcp:localhost:54320 -serial tcp:localhost:54321 \
		-s -S -machine virt -cpu cortex-a15 \
		-m 1057 \
		-bios $(ROOT)/out/bios-qemu/bios.bin

