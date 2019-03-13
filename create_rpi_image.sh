#!/bin/bash
eval "$(docker run waltplatform/dev-master env)"
THIS_DIR=$(cd $(dirname $0); pwd)
DOCKER_CACHE_PRESERVE_DIR=$THIS_DIR/.docker_cache
TMP_DIR=$(mktemp -d)

# ensure cross-architecture execution is set up
enable-cross-arch

cd $TMP_DIR

mkdir -p files/etc/apt files/etc/walt files/etc/default \
        files/root files/bin files/media/sdcard \
        files/boot/.common
touch files/root/.hushlogin

cat > files/etc/fstab << EOF
proc        /proc       proc    nodev,noexec,nosuid 0 0
/dev/mmcblk0p1  /media/sdcard   vfat    user,noauto         0 0
EOF

cat > files/etc/default/ptpd << EOF
# /etc/default/ptpd

# Set to "yes" to start ptpd automatically
START_DAEMON=yes

# Add command line options for ptpd
PTPD_OPTS="-c /etc/ptpd.conf"
EOF

cat > files/etc/ptpd.conf << EOF
ptpengine:interface=eth0
ptpengine:preset=slaveonly
global:cpuaffinity_cpucore=0
global:ignore_lock=Y
global:log_file=/var/log/ptpd.log
global:log_status=y
ptpengine:domain=42
ptpengine:ip_dscp=46
ptpengine:ip_mode=hybrid
ptpengine:log_delayreq_interval=3
EOF

cat > files/bin/blink << EOF
#!/bin/sh
if [ "\$1" = "1" ]
then
    led_module="heartbeat"
else
    led_module="mmc0"
fi
echo \$led_module > /sys/class/leds/led0/trigger
EOF
chmod +x files/bin/blink

cat > files/root/.bashrc << FILE_EOF
# see https://superuser.com/questions/175799/does-bash-have-a-hook-that-is-run-before-executing-a-command
preexec_invoke_exec () {
    [ -n "\$COMP_LINE" ] && return  # do nothing if completing
    [ "\$BASH_COMMAND" = "\$PROMPT_COMMAND" ] && return # don't cause a preexec for \$PROMPT_COMMAND
    local this_command=\$(HISTTIMEFORMAT= history 1 | sed -e "s/^[ ]*[0-9]*[ ]*//");
    echo "RUN \$this_command" >> /etc/walt/Dockerfile
}

auto_build_dockerfile() {
    if [ ! -f /.dockerenv ]
    then    # not in a container
        return
    fi
    if [ ! -f /etc/walt/Dockerfile ]
    then
        mkdir -p /etc/walt
        cat > /etc/walt/Dockerfile << EOF
# Commands run in walt image shell are saved here.
# For easier image maintenance, you can retrieve
# and edit this file to use it as a Dockerfile.
EOF
    fi
    trap 'preexec_invoke_exec' DEBUG
}

auto_build_dockerfile
FILE_EOF

cp -p $THIS_DIR/walt-clone-sdcard files/bin/
cp -p $THIS_DIR/generate-start-uboot.sh \
      $THIS_DIR/config.txt $THIS_DIR/cmdline.txt \
      files/boot/.common/

docker-preserve-cache files $DOCKER_CACHE_PRESERVE_DIR

cp -p $THIS_DIR/82B129927FA3303E.pub .

ADDITIONAL_PACKAGES=$(cat << EOF | tr '\n' ' '
init ssh sudo kmod usbutils
python-pip udev lldpd vim texinfo iputils-ping
python-serial ntpdate ifupdown lockfile-progs
avahi-daemon libnss-mdns cron ptpd busybox-static
netcat dosfstools u-boot-tools
EOF
)

create_model_boot_dir() {
    model="$1"
    kernel_name="$2"
    dtb_name="$3"
    has_pxe="$4"

    cat << EOF
mkdir "/boot/$model" && cd "/boot/$model"   && \\
EOF
    # u-boot files
    cat << EOF
ln -s ../.common/${kernel_name} kernel      && \
ln -s ../.common/${dtb_name} dtb            && \
ln -s ../.common/start.uboot start.uboot    && \\
EOF
    # pxe boot files
    if [ "$has_pxe" -eq 1 ]
    then
        for f in bootcode.bin \
                 fixup.dat fixup_cd.dat fixup_db.dat fixup_x.dat \
                 overlays \
                 start.elf start_cd.elf start_db.elf start_x.elf \
                 cmdline.txt config.txt ${kernel_name} ${dtb_name}
        do
            echo "ln -s ../.common/${f} ${f}  && \\"
        done
    fi
}

cat > Dockerfile << EOF
FROM $DOCKER_DEBIAN_RPI_BASE_IMAGE
MAINTAINER $DOCKER_IMAGE_MAINTAINER
LABEL walt.node.models=rpi-b,rpi-b-plus,rpi-2-b,rpi-3-b,rpi-3-b-plus

# resume deboostrap process
RUN ln -sf /bin/true /bin/mount && \
    /debootstrap/debootstrap --second-stage && \
    cp /etc/apt/sources.list.saved /etc/apt/sources.list && \
    apt-get clean

# register Raspberry Pi Archive Signing Key
ADD 82B129927FA3303E.pub /tmp/
RUN apt-key add - < /tmp/82B129927FA3303E.pub && rm /tmp/82B129927FA3303E.pub

# install packages
RUN    apt-get update && \
    apt-get -y --no-install-recommends install $ADDITIONAL_PACKAGES && \
    apt-get clean

# add various files
ADD files /

# generate start.uboot and populate boot dirs
RUN cd /boot/.common/ && ./generate-start-uboot.sh && \
    $(create_model_boot_dir rpi-b kernel.img bcm2708-rpi-b.dtb 0)
    $(create_model_boot_dir rpi-b-plus kernel.img bcm2708-rpi-b-plus.dtb 0)
    $(create_model_boot_dir rpi-2-b kernel7.img bcm2709-rpi-2-b.dtb 0)
    $(create_model_boot_dir rpi-3-b kernel7.img bcm2710-rpi-3-b.dtb 1)
    $(create_model_boot_dir rpi-3-b-plus kernel7.img bcm2710-rpi-3-b-plus.dtb 1)
    true

# update kernel modules setup
RUN for subdir in \$(cd /lib/modules/; ls -1); do depmod \$subdir; done

# set an entrypoint (handy when debugging)
ENTRYPOINT /bin/bash
EOF
docker build -t "waltplatform/rpi-stretch" .
result=$?

rm -rf $TMP_DIR

exit $result


