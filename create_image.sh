#!/usr/bin/env bash

IMAGENAME=imx8mqevk.img
IMAGESIZE=128M

BOOT_IMG_PATH=/media/boot
ROOTFS_PATH=/media/rootfs

# Create a 7G image
truncate -s $IMAGESIZE $IMAGENAME

# Create a partition table
echo -ne "16384 64M 7\n147456 + 83\n" | sudo sfdisk $IMAGENAME

echo "If nothing seems to happen, then it's waiting for sudo password ..."
sleep 2

# Mount up the partitions at /dev/mapper/loop0pX
sudo kpartx -av $IMAGENAME

# Format the discs to FAT (U-boot, kernel) and EXT4 (rootfs)
sudo mkfs.vfat /dev/mapper/loop0p1
sudo mkfs.ext4 /dev/mapper/loop0p2 

# Put kernel in the boot partition
sudo mkdir -p $BOOT_IMG_PATH
sudo mount /dev/mapper/loop0p1 $BOOT_IMG_PATH
sudo cp ../linux/arch/arm64/boot/Image $BOOT_IMG_PATH
sudo cp ../linux/arch/arm64/boot/dts/freescale/imx8mq-evk.dtb $BOOT_IMG_PATH/fsl-imx8mq-evk.dtb
sudo umount $BOOT_IMG_PATH

# Put rootfs at the root fs partition
sudo mkdir -p $ROOTFS_PATH
sudo mount /dev/mapper/loop0p2 $ROOTFS_PATH
sudo tar -xf ../buildroot/output/images/rootfs.tar -C $ROOTFS_PATH
sudo umount $ROOTFS_PATH

# Unmount the loop mounted partitions
sudo kpartx -dv $IMAGENAME

# Put the bootloader into the image
sudo dd if=../imx-mkimage/iMX8M/flash.bin of=$IMAGENAME bs=1k seek=33 conv=fsync,notrunc
