#!/bin/bash

get_rpi_kernel_version() {
    ls -1d /usr/src/linux-source-* | sed -e "s/.*linux-source-//"
}

rpi_kernel_version="$(get_rpi_kernel_version)"

create_rpi_model_boot_dir() {
    model="$1"
    kernel_name="$2"
    dtb_name="$3"
    has_pxe="$4"
    kernel_extension="$5"
    specialized_firmware_num="$6"

    mkdir "/boot/$model" && cd "/boot/$model"

    # u-boot files
    ln -s ../.common/${kernel_name} kernel
    ln -s ../.common/${dtb_name} dtb
    ln -s ../.common/start.uboot start.uboot

    # initrd
    kernel_version="${rpi_kernel_version}${kernel_extension}"
    #ln -s "../initrd.img-${kernel_version}" initrd

    # pxe boot files
    if [ "$has_pxe" -eq 1 ]
    then
        files="bootcode.bin overlays cmdline.txt config.txt ${kernel_name} ${dtb_name}"
        if [ -z "$specialized_firmware_num" ]
        then
            files="$files fixup.dat fixup_cd.dat fixup_db.dat fixup_x.dat \
                   start.elf start_cd.elf start_db.elf start_x.elf"
        else
            n="$specialized_firmware_num"
            files="$files fixup${n}.dat fixup${n}cd.dat fixup${n}db.dat fixup${n}x.dat \
                   start${n}.elf start${n}cd.elf start${n}db.elf start${n}x.elf"
        fi
        for f in $files
        do
            ln -s ../.common/${f} ${f}
        done
    fi
}

create_kernel_module_source_symlinks() {
    # kernel extensions:
    # "+" is 32-bit Arm6 (1B, Zero)
    # "-v7+" is 32-bit Arm7 (2B, 3B, 3A+, 3B+)
    # "-v7l+" is BCM2711 32-bit (4B)
    # "-v8+" is 64-bit Arm8 (3B, 3A+, later 2Bs, 3B+ or 4B) 
    # this walt image is only 32-bit, so no "-v8+"
    for extension in "+" "-v7+" "-v7l+"
    do
        ln -s /usr/src/linux-source-${rpi_kernel_version} \
            /lib/modules/${rpi_kernel_version}${extension}/build
    done
}

# update initramfs with ability to use nbfs
apt remove -y initramfs-tools initramfs-tools-core
dpkg -i /root/initramfs-tools*.deb
rm /root/initramfs-tools*.deb

# add symlinks useful in case of kernel module building
create_kernel_module_source_symlinks

# update kernel modules setup, generate initramfs
for subdir in $(cd /lib/modules/; ls -1)
do
    depmod $subdir
    update-initramfs -u -k $subdir
done

# add link to initramfs for qemu-arm vpn nodes
kernel_version=$(cat /boot/qemu-arm/kernel.release)
ln -s "../initrd.img-${kernel_version}" /boot/qemu-arm/initrd

# generate start.uboot and populate boot dirs for rpi models
cd /boot/.common/
./generate-start-uboot.sh
create_rpi_model_boot_dir rpi-b kernel.img bcm2708-rpi-b.dtb 0 "+"
create_rpi_model_boot_dir rpi-b-plus kernel.img bcm2708-rpi-b-plus.dtb 0 "+"
create_rpi_model_boot_dir rpi-2-b kernel7.img bcm2709-rpi-2-b.dtb 0 "-v7+"
create_rpi_model_boot_dir rpi-3-b kernel7.img bcm2710-rpi-3-b.dtb 1 "-v7+"
create_rpi_model_boot_dir rpi-3-b-plus kernel7.img bcm2710-rpi-3-b-plus.dtb 1 "-v7+"
create_rpi_model_boot_dir rpi-4-b kernel7l.img bcm2711-rpi-4-b.dtb 1 "-v7l+" 4

# tweak for faster bootup
systemctl disable systemd-timesyncd
systemctl disable apt-daily.timer
systemctl disable apt-daily-upgrade.timer
systemctl disable rpi-eeprom-update
