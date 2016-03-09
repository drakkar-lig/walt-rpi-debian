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
# Note: __SERVER_IP__ will have to be updated when the 
# rpi filesystem is installed on the server
# (it depends on the local WalT server configuration).
cat > files/etc/ntp.conf << EOF
driftfile /var/lib/ntp/ntp.drift

statistics loopstats peerstats clockstats
filegen loopstats file loopstats type day enable
filegen peerstats file peerstats type day enable
filegen clockstats file clockstats type day enable

server __SERVER_IP__

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
    }
}
EOF

docker-preserve-cache files $DOCKER_CACHE_PRESERVE_DIR

ADDITIONAL_PACKAGES=$(cat << EOF | tr '\n' ' '
ssh sudo module-init-tools usbutils
python-pip udev lldpd ntp vim texinfo iputils-ping
python-serial ntpdate ifupdown lockfile-progs
avahi-daemon libnss-mdns cron ptpd
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
RUN pip install walt-node	# 0.6
# the following is the same as running 'systemctl enable walt-node'
# on a system that is really running
RUN ln -s /etc/systemd/system/walt-node.service \
	/etc/systemd/system/multi-user.target.wants/walt-node.service

# add various files
ADD files /

# update kernel modules setup
RUN depmod \$(cd /lib/modules/; ls -1)

# set an entrypoint (handy when debugging)
ENTRYPOINT /bin/bash
EOF
docker build -t "$DOCKER_DEBIAN_RPI_IMAGE" .
result=$?

rm -rf $TMP_DIR

exit $result


