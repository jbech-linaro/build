#! /bin/bash
# SPDX-License-Identifier: BSD-2-Clause
#
# Copyright (c) 2020, Roland Nagy <rnagy@xmimx.tk>

TARGETDIR="$1"
VIRTFS_AUTOMOUNT="$2"
VIRTFS_MOUNTPOINT="$3"
PSS_AUTOMOUNT="$4"

if [[ -z $TARGET_DIR ]]; then
    echo "TARGET_DIR missing"
    exit 1
fi

if [[ -z $VIRTFS_AUTOMOUNT ]]; then
    echo "VIRTFS_AUTOMOUNT missing"
    exit 1
fi

if [[ -z $VIRTFS_MOUNTPOINT ]]; then
    echo "VIRTFS_MOUNTPOINT missing"
    exit 1
fi

if [[ -z $PSS_AUTOMOUNT ]]; then
    echo "PSS_AUTOMOUNT missing"
    exit 1
fi


if [[ $VIRTFS_AUTOMOUNT == "y" ]]; then
    grep host "$TARGETDIR"/etc/fstab > /dev/null || \
    echo "host $VIRTFS_MOUNTPOINT 9p trans=virtio,version=9p2000.L,msize=65536,rw 0 0" >> "$TARGETDIR"/etc/fstab
    echo "[+] shared directory mount added to fstab"
fi

if [[ $PSS_AUTOMOUNT == "y" ]]; then
    mkdir -p "$TARGETDIR"/data/tee
    grep secure "$TARGETDIR"/etc/fstab > /dev/null || \
    echo "secure /data/tee 9p trans=virtio,version=9p2000.L,msize=65536,rw 0 0" >> "$TARGET_DIR"/etc/fstab
    echo "[+] persistent secure storage mount added to fstab"
fi

echo "alias ll='ls -al'" >> "$TARGET_DIR"/etc/profile
echo "alias li='locki debug -i'" >> "$TARGET_DIR"/etc/profile
echo "alias lr='locki debug -r'" >> "$TARGET_DIR"/etc/profile
echo "alias lu='locki debug -u'" >> "$TARGET_DIR"/etc/profile
echo "alias lk='locki debug -k'" >> "$TARGET_DIR"/etc/profile
echo "alias au='locki user -u user -p password -s 123 -f f'" >> "$TARGET_DIR"/etc/profile
echo "alias am='locki measure -u user -p password -r 1 -d abc'" >> "$TARGET_DIR"/etc/profile
echo "alias ak='locki key -u user -p password -r 1 -h 1'" >> "$TARGET_DIR"/etc/profile
echo "alias ka='killall -9 locki'" >> "$TARGET_DIR"/etc/profile

echo "alias all='mkdir -p /host && mount -t 9p -o trans=virtio host /host && cd /lib/optee_armtz && ln -sf /host/locki/locki/ta/f13982ac-0ef8-46a6-b12c-ea79154c30e2.ta f13982ac-0ef8-46a6-b12c-ea79154c30e2.ta && cd /usr/bin && ln -sf /host/locki/locki/host/locki locki && cd /usr/lib && ln -sf /host/locki/locki/lib/liblocki.so liblocki.so && cd /usr/bin && ln -sf /host/locki/locki/test/locki_test locki_test'" >> "$TARGET_DIR"/etc/profile
