#!/bin/bash
eval "$(docker run waltplatform/dev-master env)"
THIS_DIR=$(cd $(dirname $0); pwd)
DOCKER_CACHE_PRESERVE_DIR=$THIS_DIR/.docker_cache
TMP_DIR=$(mktemp -d)

# ensure cross-architecture execution is set up
enable-cross-arch

cd $TMP_DIR

mkdir -p files/etc/apt files/etc/walt files/etc/default \
        files/root files/bin files/media/sdcard
touch files/root/.hushlogin

cat > files/etc/apt/sources.list << EOF
deb $DEBIAN_RPI_REPO_URL $DEBIAN_RPI_REPO_VERSION $DEBIAN_RPI_REPO_SECTIONS
EOF

cat > files/etc/fstab << EOF
proc        /proc       proc    nodev,noexec,nosuid 0 0
/dev/mmcblk0p1  /media/sdcard   vfat    user,noauto         0 0
EOF

# ntp configuration
# Note: %(server_ip)s will be updated by the server when the
# image is deployed, as indicated in image.spec below.
cat > files/etc/ntp.conf << EOF
driftfile /var/lib/ntp/ntp.drift

statistics loopstats peerstats clockstats
filegen loopstats file loopstats type day enable
filegen peerstats file peerstats type day enable
filegen clockstats file clockstats type day enable

server %(server_ip)s

restrict -4 default kod notrap nomodify nopeer noquery
restrict -6 default kod notrap nomodify nopeer noquery

restrict 127.0.0.1
restrict ::1
EOF

cat > files/etc/default/ptpd << EOF
# /etc/default/ptpd

# Set to "yes" to actually start ptpd automatically
START_DAEMON=no

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

cat > files/bin/enable-ptp.sh << EOF
#!/bin/sh
sed -i -e 's/=no/=yes/' /etc/default/ptpd  # enable ptp
/usr/sbin/update-rc.d ntp disable          # disable ntp
EOF
chmod +x files/bin/enable-ptp.sh

cat > files/etc/walt/image.spec << EOF
{
    # optional features implemented
    # -----------------------------
    "features": {
        "ptp": "/bin/enable-ptp.sh"
    },

    # files that need to be updated by the server
    # when the image is deployed
    # -------------------------------------------
    "templates": [
        "/etc/ntp.conf"
    ]
}
EOF

docker-preserve-cache files $DOCKER_CACHE_PRESERVE_DIR

ADDITIONAL_PACKAGES=$(cat << EOF | tr '\n' ' '
ssh sudo module-init-tools usbutils
python-pip udev lldpd ntp vim texinfo iputils-ping
python-serial ntpdate ifupdown lockfile-progs
avahi-daemon libnss-mdns cron ptpd busybox-static
netcat dosfstools
EOF
)

cat > Dockerfile << EOF
FROM $DOCKER_DEBIAN_RPI_BASE_IMAGE
MAINTAINER $DOCKER_IMAGE_MAINTAINER

# resume deboostrap process
RUN ln -sf /bin/true /bin/mount && \
    /sbin/cdebootstrap-foreign && \
    apt-get clean

# install packages
RUN gpg --keyserver pgpkeys.mit.edu --recv-key $DEBIAN_ARCHIVE_GPG_KEY && \
    gpg -a --export $DEBIAN_ARCHIVE_GPG_KEY | apt-key add - && \
    apt-get update && \
    apt-get -y --no-install-recommends install $ADDITIONAL_PACKAGES && \
    apt-get clean

# install python packages
RUN pip install --upgrade pip walt-node	# walt-node 0.9, walt-common 0.9
# the following is the same as running 'systemctl enable walt-node'
# on a system that is really running
RUN ln -s /etc/systemd/system/walt-node.service \
	/etc/systemd/system/multi-user.target.wants/walt-node.service

# add various files
ADD files /

# update kernel modules setup
RUN for subdir in \$(cd /lib/modules/; ls -1); do depmod \$subdir; done

# set an entrypoint (handy when debugging)
ENTRYPOINT /bin/bash
EOF
docker build -t "$DOCKER_DEBIAN_RPI_IMAGE" .
result=$?

rm -rf $TMP_DIR

exit $result


