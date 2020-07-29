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
# They are passed using the "/chosen" node of the device-tree.
# In our case the firmware calls u-boot, so we have to read them now in order to
# pass them again to the kernel.

echo 'Analysing bootargs given by firmware...'
# tell u-boot to look at the given device-tree
fdt addr $fdt_addr
# read "/chosen" node, property "bootargs", and store its value in variable "given_bootargs"
fdt get value given_bootargs /chosen bootargs
# but there is a little more to deal with.
# if cmdline.txt is missing or empty on the SD card, the firmware will set some "default"
# boot arguments.
# in this case, we have to remove some of them:
# * root=, rootfstype=, rootwait are not set correctly for walt context
# * kgdboc="..."  may make the kernel bootup fail (and hang!) in some cases
#   (support for kgdb may just be missing in the kernel)
setenv bootargs ""
for arg in "${given_bootargs}"
do
    setexpr rootprefix sub "(root).*" "root" "${arg}"
    if test "$rootprefix" != "root"
    then
        setexpr kgdbprefix sub "(kgdboc).*" "kgdboc" "${arg}"
        if test "$kgdbprefix" != "kgdboc"
        then
            # OK, we can keep this bootarg given by the firmware
            setenv bootargs "${bootargs} ${arg}"
        fi
    fi
done

# retrieve the dtb (device-tree-blob) and kernel
tftp ${fdt_addr_r} ${serverip}:dtb || reset
tftp ${kernel_addr_r} ${serverip}:kernel || reset

# compute kernel command line args
setenv nfs_root "/var/lib/walt/nodes/%s/fs"
setenv nfs_bootargs "root=/dev/nfs nfsroot=${nfs_root},nfsvers=3,actimeo=300,proto=tcp"
setenv other_bootargs "init=${walt_init} ip=dhcp panic=15 net.ifnames=0 biosdevname=0"
setenv bootargs "$bootargs $nfs_bootargs $other_bootargs"

# boot
echo 'Booting kernel...'
# second argument is for the ramdisk ("-" means none)
bootz ${kernel_addr_r} - ${fdt_addr_r} || reset
