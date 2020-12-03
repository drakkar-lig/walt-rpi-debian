#!/bin/busybox sh

cd /boot/.common/

# activate for VPN nodes
ln -sf start-nbfs.ipxe start.ipxe

# activate for raspberry pi nodes (SD or no-SD boot modes)
# -> not activated for now (boot procedure is currently not based
#    on initramfs)
#ln -sf start-nbfs.uboot start.uboot
#ln -sf cmdline-nbfs.txt cmdline.txt
