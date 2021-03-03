################################################
Standalone firmware and Linux kernel environment
################################################

.. contents::

This project is a helper project to be able to create a development environment
for QEMU consisting of Linux kernel, U-Boot, Buildroot, Grub2 and QEMU itself.

Installation
************
Prerequisites
=============
This setup has dependencies to various packages. The list of packages that we've
been able to identify is as below and needs to be installed on your system:

.. code-block:: bash

    $ sudo apt install \
        autoconf \
        autopoint \
        bc \
        bison \
        flex \
        gettext \
        git \
        libcap-dev \
        libcap-ng-dev \
        libfdt-dev \
        libglib2.0-dev \
        libguestfs-tools \
        libpixman-1-dev \
        libssl-dev \
        unzip \
        rsync \
        texlive \
        tftp \
        tftpd \
        wget \
        xinetd \
        zlib1g-dev


Get the source code
===================
Install ``repo`` by following the installation instructions 
`here <https://source.android.com/setup/build/downloading>`_. Once repo has been
configured, it's time to initialize the tree.

.. code-block:: bash

    $ mkdir -p <path-to-my-project-root>
    $ cd <path-to-my-project-root>
    $ repo init -u https://github.com/jbech-linaro/manifest.git -b dte

Next sync the actual tree

.. code-block:: bash

    $ repo sync -j4


U-Boot command sequences
========================
When running the ``run-netboot`` make command, you will boot up U-Boot and from
there you have different alternatives on how to continue. If you do not stop the
count down U-boot will attempt to load the ``./out/uEnv.txt`` file from tftp,
import its values, and run any defined ``uenvcmd``.  The
``./build/example-uEnv.txt`` will be copied to ``./out/uEnv.txt`` if that files
does not already exist. The example sets and displays a few variables and then
runs the ``netbootgrub`` script described below.

If you stop the U-boot count down you can run any U-Boot command.  Of note are
several predefined scripts.  These scripts allow you to boot the kernel
directly via individual files, boot into grub2, or boot fit-images. Theses
scripts are built into the U-boot default environment via the
``<project_path>/build/uboot-env.txt`` file.

Supported boot target / U-Boot commands are as below:

+-----------------+-------------------------------------------------------+
| U-Boot command  | Description                                           |
+=================+=======================================================+
| run netboot     | boot Linux kernel in U-boot uImage format             |
+-----------------+-------------------------------------------------------+
| run netbootgrub | boot Grub2                                            |
+-----------------+-------------------------------------------------------+
| run netbootfit  | boot Linux kernel using a fit-image                   |
+-----------------+-------------------------------------------------------+
| run netloadfit  | load a fit image into memory (helper for inspection)  |
+-----------------+-------------------------------------------------------+
| run fitconfig1  | boot Linux kernel (no checks)                         |
+-----------------+-------------------------------------------------------+
| run fitconfig2  | boot Linux kernel (hash verification)                 |
+-----------------+-------------------------------------------------------+
| run fitconfig3  | boot Linux kernel (RSA verification)                  |
+-----------------+-------------------------------------------------------+
| run fitconfig4  | boot Linux kernel (RSA verification of U-Boot config) |
+-----------------+-------------------------------------------------------+

Compile
=======
This has been tested on verified on various systems, but FAQ#1 and FAQ#2 might
affect you depending on the Linux distribution you're using. Please have a look
at those in case you get an build error.

.. code-block:: bash

    $ make -j2 toolchains
    $ make -j4

**Compiler flags**

+--------------------------+---------------------------------------------------------------------------------+---------------+
| Compiler flag            | Description                                                                     | Default value |
+==========================+=================================================================================+===============+
| ``ENVSTORE``             | enables persistent storage of U-Boot environment variables                      | y             |
+--------------------------+---------------------------------------------------------------------------------+---------------+
| ``GDB``                  | enables the GDB stub in QEMU                                                    | n             |
+--------------------------+---------------------------------------------------------------------------------+---------------+
| ``SIGN``                 | enables signature verification of FIT images                                    | n             |
+--------------------------+---------------------------------------------------------------------------------+---------------+
| ``USE_CUSTOM_UBOOT_ENV`` | use the U-Boot environment as defined in ``<project_path>/build/uboot-env.txt`` | y             |
+--------------------------+---------------------------------------------------------------------------------+---------------+
| ``VARIABLES``            | (experimental) build PK, KEK for use with authenticated variables               | n             |
+--------------------------+---------------------------------------------------------------------------------+---------------+

Run targets
===========

**Netboot using raw files**

This will load files directly from TFTP (must be configured, see further down)
into the correct memory location and then it will boot using ``bootm``. No
special build commands is required for this target.

.. code-block:: bash

    $ make run-netboot
    => run netboot

**Netboot using Grub2**

Similar to the netboot-target, but this will load grub2 instead of booting up
Linux kernel directly

.. code-block:: bash

    $ make run-netboot
    => run netbootgrub

Grub will present a menu with a count down and default choice.
Pressing any key will stop the count down and allow you to make a choice, edit
a given entry, or drop to a grub command prompt.

**Netboot using FIT image**

This will load a FIT image directly from TFTP (must be configured, see further
down) into memory. The FIT image consist of the kernel image, the rootfs
(Buildroot) and the DTB coming from QEMU. The DTB is in memory by default in
QEMU, but since we want to emulate a real flow, we dump the DTB to a file, then
use that when creating the FIT-image and then load it to the same address where
QEMU would have put it initially. When you have made changes, then you need to
update the FIT-image (i.e., re-run make). No special build commands is required
for this target.

Once the FIT-image has been updated you can boot up QEMU and then the below that
will load the FIT-image image and bootm the content of it.

.. code-block:: bash

    $ make run-netboot
    => run netbootfit

**Netboot using a signed FIT image**

Same as for the FIT image above, with the difference the you need to enable
signature support when building. If we'd run the ``netbootfit`` target, then the
outcome would be the same as above. Here we're interest in running a signed
kernel. So for that we do it two steps. First we load the FIT image into memory,
then we bootm the ``fitconfig3`` (which is signed kernel).

.. code-block:: bash

    $ make SIGN=y
    $ make run-netboot
    => run fitconfig3


**Boot Linux kernel directly**

If you just need to boot Linux kernel directly without using nor involving
U-Boot, then you can do that running the run target below. Note that in this
case there is no signature verification etc enabled.

.. code-block:: bash

    $ make run-kernel-initrd


**Boot Linux kernel directly (built-in rootfs)**

Same as the previous one, but here the rootfs has been built-in directly into
Linux kernel.

.. code-block:: bash

    $ make run-kernel


**Help**

There is a "help" target that prints a couple of command useful when doing thing
manually. I.e., lines that are more or less ready to be copy/pasted to various
prompts


TFTP
****
Setup the TFTP server
=====================

This project is configured to use the TFTP server built into QEMU.  Setting up
a TFTP server on your development machine is not required.

However, if you wish to use an external TFTP server you may.  The below
instructions outline using tftpd.  tftpd will conflict with tftpd-hpa, another
popular TFTP server.  The symlinks used by the project are not compatible with
tftp-hpa.  If you are using tftpd-hpa on your development machine it is
recommended that you use the built-in QEMU tftp server as already setup by this
project.

Credits to the author of `this <https://developer.ridgerun.com/wiki/index.php?title=Setting_Up_A_Tftp_Service>`_
guide.

.. code-block:: bash

    $ sudo apt install xinetd tftpd tftp
    $ sudo vim /etc/xinetd.d/tftp

and paste

.. code-block:: bash

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

Save the file and exit, then create the directory and fix permissions

.. code-block:: bash

    $ sudo mkdir /srv/tftp
    $ sudo chmod -R 777 /srv/tftp
    $ sudo chown -R nobody /srv/tftp

Start tftpd through xinetd

.. code-block:: bash

    $ sudo /etc/init.d/xinetd restart

Modify uboot-env.txt
====================
Edit the build/uboot-env.txt file to uncomment the serverip_static variable
setting and specify your machine's real IP address. (Not the loopback or
localhost address).

Rebuild the project
.. code-block:: bash

    $ make -j 4


Symlink the necessary files
===========================
.. code-block:: bash

Go to the TFTP server directory and symlink all files in ``<project_path>/out``
in one go. Do this **after** completing the first build!

.. code-block:: bash

    $ cd /srv/tftp
    $ ln -s <project_path>/out/* .


FIT image configuration
=======================
At ``<project_path>/build/fit`` you'll find the two files ``control-fdt.dts``
and ``fit.its``. The former is the dts-file where you state the name of the key,
the algorithms and key-size you are going to use. The ``fit.its`` file itself
contains the actual fit-image configuration, i.e., where we describe the
different images available and the different combinations that we can use.

Note! There are several hard-coded dependencies between the ``Makefile``,
``control-fdt.dts`` and ``fit.its``. Dependencies like addresses, key-size,
algorithms, key-names, relative paths etc. So whenever you're working with
fit-images, it's important to cross check that you've done changes in all three
files.

For debugging, the U-boot command ``iminfo`` is helpful. I.e. first load the
fit-image and then running ``iminfo`` gives useful information and checks the
status of the verification.

.. code-block:: bash

    => run netloadfit
    => iminfo
    ## Checking Image at 48000000 ...
    FIT image found
    ...
    ## Checking hash(es) for FIT Image at 48000000 ...
    Hash(es) for Image 0 (kernel-1):
    Hash(es) for Image 1 (kernel-2): crc32+ sha1+
    Hash(es) for Image 2 (kernel-3): sha1,rsa2048:private-
    Hash(es) for Image 3 (fdt-1): sha1+
    Hash(es) for Image 4 (ramdisk-1): sha1+

The address ``0x48000000`` is at memory address high enough to not clash with
the images to be loaded.


FAQ
***

.. _faq1:

1. Makefile:xyz: grub2-create-image
===================================

.. code-block:: bash

    make: *** [Makefile:183: grub2-create-image] Error 1
    libguestfs: error: /usr/bin/supermin exited with error status 1.
    To see full error messages you may need to enable debugging.
    Do:
      export LIBGUESTFS_DEBUG=1 LIBGUESTFS_TRACE=1
      and run the command again.  For further information, read:
      http://libguestfs.org/guestfs-faq.1.html#debugging-libguestfs
      You can also run 'libguestfs-test-tool' and post the *complete* output
      into a bug report or message to the libguestfs mailing list.
      make: *** [Makefile:183: grub2-create-image] Error 1
      make: *** Waiting for unfinished jobs....

The reason for that is because your ``/boot/vmlinuz-*`` files are only readable
by the root user. To work around this, you need to make them readable. Note that
after upgrading to a new kernel on your host, you'll have to redo this again
(and again).

.. code-block:: bash

    $ sudo chmod 644 /boot/vmlinuz-`uname -r`


.. _faq2:

2. libguestfs: warning: current user is not a member of the KVM group
=====================================================================

.. code-block:: bash

    libguestfs: warning: current user is not a member of the KVM group (group ID
    129). This user cannot access /dev/kvm, so libguestfs may run very slowly.
    It is recommended that you 'chmod 0666 /dev/kvm' or add the current user to
    the KVM group (you might need to log out and log in again).

You have to add your user id to the ``kvm`` group.

.. code-block:: bash

    $ sudo adduser `id -un` kvm
    $ sudo reboot


.. _faq3:

3. How do I log in to Buildroot?
================================
``login`` is ``root`` and password is not needed.

4. What are all the addresses in use?
=====================================
+-----------------+-----------------------+------------------------------------------------------------------------------+
| Address         | Component             | Comment                                                                      |
+=================+=======================+==============================================================================+
| ``0x4000.0000`` | DeviceTree DTB        | The address where DTB should be located (QEMU adds a DTB here automatically) |
+-----------------+-----------------------+------------------------------------------------------------------------------+
| ``0x4040.0000`` | Linux kernel or Grub2 | The address where Linux kernel or Grub2 should be located                    |
+-----------------+-----------------------+------------------------------------------------------------------------------+
| ``0x4400.0000`` | Root filesystem       | The address where the root filesystem should be located                      |
+-----------------+-----------------------+------------------------------------------------------------------------------+
| ``0x4800.0000`` | fit-image             | The address where to store the fit-image                                     |
+-----------------+-----------------------+------------------------------------------------------------------------------+

5. How do I modify the DTB?
===========================
This is still a To-Do, but something like this.

.. code-block:: bash

    $ make qemu-dump-dts
    $ vim out/qemu-aarch64.dts
    ... make changes and save
    re-create the DTB from the dts (using dtc and mkimage(?))
    tftp the dbt to ``0x40000000``
    bootm ...

    

// Joakim Bech
2021-02-22
