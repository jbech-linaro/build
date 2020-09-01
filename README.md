This git-project is a helper project to be able to build U-Boot, TF-A, Linux
kernel etc as standalone components for iMX8MQ-evk boards. I.e., with this you
don't have to use Yocto etc.

# Prerequisites
```
$ apt install coreutils device-tree-compiler dosfstools e2fsprogs fdisk git \
              kpartx pv sudo util-linux wget
```

# Setup
Sync the git's needed using
[repo](https://source.android.com/setup/build/downloading). Following the link
for installation instructions.

```
$ repo init -u https://github.com/jbech-linaro/manifest.git -b imx8mqevk
```

Get the toolchain (GCC, only 64bit is used, but you'll get a 32bit GCC as well).
```
$ make -j2 toolchains
```

# Compile
This will compile all components, i.e., TF-A, U-Boot, Linux kernel, imx-mkimage.
```
$ make
```

# Flash
There are several ways to flash a device, it depends what you want to flash and
what method you prefer.

Be **super-careful** about the name you use for all `dd` commands. Since if you
use the wrong name you can accidentally wipe another hard drive on your local
computer.

## Create and write a complete image
This will create a complete image ready to flash to a SD-card using `dd`. The
script will require `sudo` access. Note that, you must run a normal `make` once
to compile all the binaries used before being able to run the command below.

```
$ make flash-image
```
This will create an image file called `imx8mqevk.img` that contains the
bootloader (U-boot, put at offset 33), a boot disk (Linux kernel and DTB) and
the rootfs disk. During creation it will map and mount the partitions to
`/media/boot` and `/media/rootfs` on your local machine. So, if you have those
in use already for other purposes, then you need to update the `create_image.sh`
to use other unused paths.

When the image has been created, insert your SD-card into your computer. Via
`sudo dmesg` or `lsblk` you should be able to figure out what device name it
got. I.e., something with `/dev/sdX` or `/dev/mmcblk[n]`. Use that device as
part of the `... of=<device>` in the command below. There we're using
`/dev/sdj`. Note when flashing the complete image you should use the device name
and not device name + partition number. I.e., `/dev/sdj` is correct, `/dev/sdj1`
is incorrect. The `make flash-image` will give an example also.

```
$ sudo dd if=build/imx8mqevk.img | pv | sudo dd of=/dev/sdj bs=1M conv=fsync
```

Note! If you need more space for the rootfs, simply change the size in the
`create_image.sh` script.

## Flash bootloader only
This flash directly to the SD-card. So after inserting the SD-card into your
computer, run:
```
$ make flash-bootloader
```
Type the last row (a `dd` command) to flash the bootloader to your device.

# TFTP
## Setup the tftp server
Credits to the author of [this](https://developer.ridgerun.com/wiki/index.php?title=Setting_Up_A_Tftp_Service)
guide.
```
sudo apt install xinetd tftpd tftp
```

```
$ sudo vim /etc/xinetd.d/tftp
```
and paste

```
service tftp
{
    protocol        = udp
    port            = 69
    socket_type     = dgram
    wait            = yes
    user            = nobody
    server          = /usr/sbin/in.tftpd
    server_args     = /srv/tftp
    disable         = no
}
```
Save the file and exit.

Create the directory
```
$ sudo mkdir /srv/tftp
$ sudo chmod -R 777 /srv/tftp
$ sudo chown -R nobody /srv/tftp
```

Start tftpd through xinetd

```
sudo /etc/init.d/xinetd restart
```

## Symlink kernel and dtb
```
$ cd /srv/tftp
$ ln -s <project_path>/imx8mqevk/linux/arch/arm64/boot/Image .
$ ln -s <project_path>/imx8mqevk/linux/arch/arm64/boot/dts/freescale/imx8mq-evk.dtb fsl-imx8mq-evk.dtb
```

## Boot up
Make sure you have an SD-card with at least the bootloader on it (minimum
`compile` and `flash bootloader only`). Plug in the Ethernet cable to the
IMX8MQ device, then turn on the device and halt U-Boot when it is counting
down, then run:
```
u-boot=> run netboot
```

# NFS

## Setup the NFS server
```
$ sudo apt install nfs-kernel-server
```

## Create a rootfs locally
A simple way is to take a Buildroot rootfs and put it locally, something like:
```
$ mkdir -p /srv/nfs/imx
$ buildroot/output/images/
$ tar xvf <project_path>/imx8mqevk/buildroot/output/images/rootfs.tar -C /srv/nfs/imx
```

## Edit exports
```
$ sudo vim /etc/exports
```
and paste
```
/srv/nfs/imx 192.168.1.0/24(rw,sync,no_root_squash,no_subtree_check)
```
then restart
```
$ sudo exportfs -a
$ sudo systemctl restart nfs-kernel-server
```

## Configure U-boot
This only has to be done once! Boot up the device and halt U-Boot when it's
counting down (use the ip-address from your local computer running the tftp
server)
```
u-boot=> setenv serverip 192.168.1.110
u-boot=> setenv nfsroot /srv/nfs/imx
```

## Boot the device
```
u-boot=> run netboot
```


// Joakim Bech
Last updated: 2020-09-01

