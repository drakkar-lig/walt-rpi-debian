#!/bin/bash

model="$1"
kernel_name="$2"
dtb_name="$3"
has_pxe="$4"

mkdir "/boot/$model" && cd "/boot/$model"

# u-boot files
ln -s ../.common/${kernel_name} kernel
ln -s ../.common/${dtb_name} dtb
ln -s ../.common/start.uboot start.uboot

# pxe boot files
if [ "$has_pxe" -eq 1 ]
then
    for f in bootcode.bin \
             fixup.dat fixup_cd.dat fixup_db.dat fixup_x.dat \
             overlays \
             start.elf start_cd.elf start_db.elf start_x.elf \
             cmdline.txt config.txt ${kernel_name} ${dtb_name}
    do
        ln -s ../.common/${f} ${f}
    done
fi
