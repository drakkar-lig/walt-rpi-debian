#!/bin/bash

model="$1"
kernel_name="$2"
dtb_name="$3"
has_pxe="$4"
specialized_firmware_num="$5"

mkdir "/boot/$model" && cd "/boot/$model"

# u-boot files
ln -s ../.common/${kernel_name} kernel
ln -s ../.common/${dtb_name} dtb
ln -s ../.common/start.uboot start.uboot

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
