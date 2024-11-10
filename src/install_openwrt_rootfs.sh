#!/usr/bin/env bash

set -Eeuo pipefail
trap - ERR

. /var/vm/openwrt_metadata.conf
. /run/helpers.sh

# Check if squashfs-combined is in volume
FILE=/storage/squashfs-combined-${OPENWRT_IMAGE_ID}.img
if [ -f "$FILE" ]; then
    info "$FILE exists. Nothing to do."
else 
    info "$FILE does not exist. Copying squashfs-combined-${OPENWRT_VERSION}.img to storage ..."
    cp /var/vm/squashfs-combined-${OPENWRT_VERSION}.img.gz /storage/squashfs-combined-${OPENWRT_IMAGE_ID}.img.gz
    gzip -d /storage/squashfs-combined-${OPENWRT_IMAGE_ID}.img.gz
    
    # info "Inject some additional files into the image"
    # mount /storage/squashfs-combined-${OPENWRT_IMAGE_ID}.img /mnt
    # # mount -o offset=$((512*262656)) /storage/disk.img /mnt # combined image ext4 partition starts at offset 262656
    
    # chmod +x /var/vm/openwrt_additional/usr/bin/*
    # cp /var/vm/openwrt_additional/usr/bin/* /mnt/usr/bin/

    # mv /mnt/etc/rc.local /mnt/etc/rc.local.orig
    # cp /var/vm/openwrt_additional/etc/rc.local /mnt/etc/rc.local
    # chmod +x /mnt/etc/rc.local

    # # Add some additional default configurations. Only if we have a fresh container because /storage/current_version is not existing then
    # if [ ! -f /storage/current_version ]; then
    #   chmod +x /var/vm/openwrt_additional/etc/uci-defaults/*
    #   cp /var/vm/openwrt_additional/etc/uci-defaults/* /mnt/etc/uci-defaults/
    # fi

    # info "Install additional IPKs into the image"
    # mkdir /mnt/var/offline_packages
    # cp /var/vm/packages/*.ipk /mnt/var/offline_packages/
    # chroot /mnt/ mkdir -p /var/lock
    # chroot /mnt/ sh -c 'cd /var/offline_packages/ && opkg install *.ipk'
    # rm -rf /mnt/var/offline_packages/
    # rm -rf /mnt/var/lock

    # umount /mnt

    if [ -f "/storage/current_version" ]; then
      mv /storage/current_version /storage/old_version
    fi

    touch /storage/current_version
    echo "squashfs-combined-${OPENWRT_IMAGE_ID}.img" > /storage/current_version
fi
