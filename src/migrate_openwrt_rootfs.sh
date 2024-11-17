#!/usr/bin/env bash

set -Eeuo pipefail
trap - ERR

. /var/vm/openwrt_metadata.conf
. /run/helpers.sh

SQUASHFS_COMBINED=/storage/squashfs-combined-${OPENWRT_IMAGE_ID}.img
CPU_ARCH=$(arch)

# Migrate settings from old OpenWrt version to new one
if [ -f /storage/old_version ]; then
  OLD_SQUASHFS_COMBINED=`cat /storage/old_version`

  info "Migrate settings from $OLD_SQUASHFS_COMBINED to squashfs-combined-${OPENWRT_IMAGE_ID}.img."

  # Create config backup in previous image
  if [[ -z "${IS_U_OS_APP}" ]]; then
    if [[ $OLD_SQUASHFS_COMBINED == *"rootfs"* ]]; then
        warn "Using rootfs-<UUID>.img images is deprecated!"
        mount /storage/$OLD_SQUASHFS_COMBINED /mnt
        chroot /mnt/ mkdir -p /var/lock
        chroot /mnt /sbin/sysupgrade -k -b /tmp/openwrt_config.tar.gz
        mv /mnt/tmp/openwrt_config.tar.gz  /storage/config-`basename $OLD_SQUASHFS_COMBINED.img`.tar.gz
        umount /mnt
    else
        /run/mount_openwrt_squashfs_combined.sh /storage/$OLD_SQUASHFS_COMBINED $CPU_ARCH
        chroot /mnt/ mkdir -p /var/lock
        chroot /mnt /sbin/sysupgrade -k -b /tmp/openwrt_config.tar.gz
        mv /mnt/tmp/openwrt_config.tar.gz /storage/config-`basename $OLD_SQUASHFS_COMBINED.img`.tar.gz
        /run/mount_openwrt_squashfs_combined.sh -u
    fi

    # Put config backup to new squashfs-combined
    /run/mount_openwrt_squashfs_combined.sh $SQUASHFS_COMBINED $CPU_ARCH
    mkdir -p /mnt/root/backup
    cp /storage/config-`basename $OLD_SQUASHFS_COMBINED.img`.tar.gz /mnt/root/backup/config.tar.gz
    chroot /mnt/ mkdir -p /var/lock
    chroot /mnt /sbin/sysupgrade -r /root/backup/config.tar.gz
    /run/mount_openwrt_squashfs_combined.sh -u 
  else
    # Since Weidmueller u-OS doesn't support squashfs and f2fs we are using the OpenWrt image to do the settings migration
    # This is a workaround!
   
    # Make a copy from the original OpenWrt image
    cp /var/vm/squashfs-combined-${OPENWRT_VERSION}.img.gz /tmp/squashfs-combined-tmp.img.gz
    gzip -d /tmp/squashfs-combined-tmp.img.gz

    # Boot a temporary OpenWrt
    qemu-system-aarch64 -M virt -cpu host --enable-kvm -smp 2 -nographic -nodefaults -m 256 \
     -bios /usr/share/qemu/edk2-aarch64-code.fd \
     -blockdev driver=raw,node-name=hd0,cache.direct=on,file.driver=file,file.filename=/tmp/squashfs-combined-tmp.img \
     -device virtio-blk-pci,drive=hd0 \
     -blockdev driver=raw,node-name=hd1,cache.direct=on,file.driver=file,file.filename=/storage/$OLD_SQUASHFS_COMBINED \
     -device virtio-blk-pci,drive=hd1 \
     -blockdev driver=raw,node-name=hd2,cache.direct=on,file.driver=file,file.filename=$SQUASHFS_COMBINED \
     -device virtio-blk-pci,drive=hd2 \
     -device virtio-net,netdev=qlan0 -netdev user,id=qlan0,net=172.31.1.0/24,hostfwd=tcp::1022-172.31.1.1:22 \
     -device virtio-net,netdev=qwan0 -netdev user,id=qwan0 \
     & QEMU_PID=$!
    echo "QEMU started with PID $QEMU_PID"

    # Wait until OpenWrt has booted
    until ssh -o ConnectTimeout=10 -o StrictHostKeyChecking=accept-new root@localhost -p 1022 "cat /etc/banner"; do echo "Waiting for OpenWrt boot ..."; sleep 1; done
    ssh root@localhost -p 1022 "mkdir -p /tmp/squashfs_dir"
    ssh root@localhost -p 1022 "mkdir -p /tmp/userdata_dir"

    if [[ $OLD_SQUASHFS_COMBINED == *"rootfs"* ]]; then
        warn "Using rootfs-<UUID>.img images is deprecated!"
        ssh root@localhost -p 1022 "mount /dev/vdb /mnt"
        ssh root@localhost -p 1022 "chroot /mnt/ mkdir -p /var/lock"
        ssh root@localhost -p 1022 "chroot /mnt /sbin/sysupgrade -k -b /tmp/openwrt_config.tar.gz"
        ssh root@localhost -p 1022 "cp /mnt/tmp/openwrt_config.tar.gz /tmp"
        ssh root@localhost -p 1022 "umount /mnt"
    else
        FILESYSTEM_OFFSETS=$(/run/mount_openwrt_squashfs_combined.sh -o /storage/$OLD_SQUASHFS_COMBINED $CPU_ARCH)
        J2FS_OFFSET=$(echo $FILESYSTEM_OFFSETS | cut -d',' -f2)
        ssh root@localhost -p 1022 "mount /dev/vdb2 /tmp/squashfs_dir"
        ssh root@localhost -p 1022 "losetup -o $J2FS_OFFSET /dev/loop1 /dev/vdb"
        ssh root@localhost -p 1022 "mount /dev/loop1 /tmp/userdata_dir"
        ssh root@localhost -p 1022 "mount -t overlay -o lowerdir=/tmp/squashfs_dir,upperdir=/tmp/userdata_dir/upper,workdir=/tmp/userdata_dir/work overlay /mnt"
        ssh root@localhost -p 1022 "mount -o bind /tmp/userdata_dir /mnt/overlay/"
        ssh root@localhost -p 1022 "mount -o bind /tmp/squashfs_dir /mnt/rom/"
        ssh root@localhost -p 1022 "mount -o bind /dev /mnt/dev"
        ssh root@localhost -p 1022 "chroot /mnt/ mkdir -p /var/lock"
        ssh root@localhost -p 1022 "chroot /mnt /sbin/sysupgrade -k -b /tmp/openwrt_config.tar.gz"
        ssh root@localhost -p 1022 "cp /mnt/tmp/openwrt_config.tar.gz /tmp"
        ssh root@localhost -p 1022 "umount /mnt/overlay"
        ssh root@localhost -p 1022 "umount /mnt/rom"
        ssh root@localhost -p 1022 "umount /mnt/dev"
        ssh root@localhost -p 1022 "umount /mnt"
        ssh root@localhost -p 1022 "umount /tmp/userdata_dir"
        ssh root@localhost -p 1022 "umount /tmp/squashfs_dir"
        ssh root@localhost -p 1022 "losetup -d /dev/loop1"
    fi

    # Put config backup to new squashfs-combined
    FILESYSTEM_OFFSETS=$(/run/mount_openwrt_squashfs_combined.sh -o $SQUASHFS_COMBINED $CPU_ARCH)
    J2FS_OFFSET=$(echo $FILESYSTEM_OFFSETS | cut -d',' -f2)
    ssh root@localhost -p 1022 "mount /dev/vdc2 /tmp/squashfs_dir"
    ssh root@localhost -p 1022 "losetup -o $J2FS_OFFSET /dev/loop1 /dev/vdc"
    ssh root@localhost -p 1022 "mount /dev/loop1 /tmp/userdata_dir"
    ssh root@localhost -p 1022 "mount -t overlay -o lowerdir=/tmp/squashfs_dir,upperdir=/tmp/userdata_dir/upper,workdir=/tmp/userdata_dir/work overlay /mnt"
    ssh root@localhost -p 1022 "mount -o bind /tmp/userdata_dir /mnt/overlay/"
    ssh root@localhost -p 1022 "mount -o bind /tmp/squashfs_dir /mnt/rom/"
    ssh root@localhost -p 1022 "mount -o bind /dev /mnt/dev"
    ssh root@localhost -p 1022 "chroot /mnt/ mkdir -p /var/lock"
    ssh root@localhost -p 1022 "cp /tmp/openwrt_config.tar.gz /mnt/tmp"
    ssh root@localhost -p 1022 "chroot /mnt /sbin/sysupgrade -r /tmp/openwrt_config.tar.gz"

    # Stop VM
    ssh root@localhost -p 1022 'sync; halt' 
    while kill -0 $QEMU_PID 2>/dev/null; do echo "Waiting for qemu exit ..."; sleep 1; done;

    # Delete temporary OpenWrt image
    rm /tmp/squashfs-combined-tmp.img
  fi

  # Finally remove old squashfs-combined and old files
  rm /storage/$OLD_SQUASHFS_COMBINED
  rm /storage/old_version
  if [ -f storage/config-`basename $OLD_SQUASHFS_COMBINED.img`.tar.gz ]; then
    rm /storage/config-`basename $OLD_SQUASHFS_COMBINED.img`.tar.gz
  fi
else
  info "squashfs-combined-${OPENWRT_IMAGE_ID}.img is up to date. Nothing to do."
fi