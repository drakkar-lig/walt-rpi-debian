#!/bin/bash
set -e
# Just execute this script to generate rpi.uboot script.
if [ "$(which mkimage)" = "" ]
then
    echo "Error: u-boot's mkimage tool is needed (cf. u-boot-tools package). ABORTED."
    exit
fi

SCRIPT=$(mktemp)
cat $0 | sed '0,/SCRIPT_START$/d' > $SCRIPT
mkimage -A arm -O linux -T script -C none -n start-uboot.scr -d $SCRIPT start.uboot
echo "start.uboot was generated in the current directory."
rm $SCRIPT
exit

######################## SCRIPT_START
setenv walt_init "/bin/walt-init"

# Some bootargs are normally given by the firmware when it runs the linux kernel.
# But in our case the firmware calls u-boot, and we would like u-boot to read them
# in order to pass them to the kernel. But reading these parameters is apparently
# not implemented in u-boot, so we hardcode them here.

setenv bootargs "console=ttyAMA0,115200"    # default, overriden below for some models

if test "$node_model" = "rpi-3-b"
then
    setenv bootargs "8250.nr_uarts=1 bcm2708_fb.fbwidth=1824 bcm2708_fb.fbheight=984\
                     bcm2708_fb.fbswap=1 dma.dmachans=0x7f35 bcm2709.boardrev=0xa02082\
                     bcm2709.serial=0xd49980ca bcm2709.uart_clock=48000000\
                     vc_mem.mem_base=0x3ec00000 vc_mem.mem_size=0x40000000\
                     console=ttyS0,115200 kgdboc=ttyS0,115200 console=tty1"
fi

if test "$node_model" = "rpi-3-b-plus"
then
    setenv bootargs "8250.nr_uarts=1 bcm2708_fb.fbwidth=1824 bcm2708_fb.fbheight=984\
                     bcm2708_fb.fbswap=1 vc_mem.mem_base=0x3ec00000 vc_mem.mem_size=0x40000000\
                     console=ttyS0,115200 console=tty1"
fi

# retrieve the dtb (device-tree-blob) and kernel
tftp ${fdt_addr_r} ${serverip}:dtb || reset
tftp ${kernel_addr_r} ${serverip}:kernel || reset

# compute kernel command line args
setenv nfs_root "/var/lib/walt/nodes/%s/fs"
setenv nfs_bootargs "root=/dev/nfs nfsroot=${nfs_root},nfsvers=3,acregmax=5"
setenv rpi_bootargs "smsc95xx.macaddr=${ethaddr}"
setenv other_bootargs "init=${walt_init} ip=dhcp panic=15"
setenv bootargs "$bootargs $nfs_bootargs $rpi_bootargs $other_bootargs"

# boot
echo 'Booting kernel...'
# second argument is for the ramdisk ("-" means none)
bootz ${kernel_addr_r} - ${fdt_addr_r} || reset
