#!/bin/bash
eval "$(docker run waltplatform/dev-master env)"
THIS_DIR=$(cd $(dirname $0); pwd)
DOCKER_CACHE_PRESERVE_DIR=$THIS_DIR/.docker_cache
TMP_DIR=$(mktemp -d)

# ensure cross-architecture execution is set up
enable-cross-arch

cd $TMP_DIR

cat > sources.list << EOF
deb $DEBIAN_RPI_REPO_URL $DEBIAN_RPI_REPO_VERSION $DEBIAN_RPI_REPO_SECTIONS
EOF
docker-preserve-cache sources.list $DOCKER_CACHE_PRESERVE_DIR

cat > fstab << EOF
proc        /proc       proc    nodev,noexec,nosuid 0 0
/dev/mmcblk0p1  /media/sdcard   vfat    user,noauto         0 0
EOF
docker-preserve-cache fstab $DOCKER_CACHE_PRESERVE_DIR

# ntp configuration
# Note: __SERVER_IP__ will have to be updated when the 
# rpi filesystem is installed on the server
# (it depends on the local WalT server configuration).
cat > ntp.conf << EOF
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
docker-preserve-cache ntp.conf $DOCKER_CACHE_PRESERVE_DIR

ADDITIONAL_PACKAGES=$(cat << EOF | tr '\n' ' '
ssh sudo module-init-tools usbutils
python-pip udev lldpd ntp vim texinfo iputils-ping
python-serial ntpdate ifupdown lockfile-progs
EOF
)

cat > Dockerfile << EOF
FROM $DOCKER_DEBIAN_RPI_BASE_IMAGE
MAINTAINER $DOCKER_IMAGE_MAINTAINER

# resume deboostrap process
RUN ln -sf /bin/true /bin/mount
RUN /sbin/cdebootstrap-foreign && apt-get clean

# update apt sources
ADD sources.list /etc/apt/sources.list

# install backported (more recent) packages
RUN gpg --keyserver pgpkeys.mit.edu --recv-key $DEBIAN_ARCHIVE_GPG_KEY
RUN gpg -a --export $DEBIAN_ARCHIVE_GPG_KEY | apt-key add -

# install packages
RUN apt-get update && \
    apt-get -y --no-install-recommends install $ADDITIONAL_PACKAGES && \
    apt-get clean

# install python packages
RUN pip install walt-node	# 0.4-5
# the following is the same as running 'systemctl enable walt-node'
# on a system that is really running
RUN ln -s /etc/systemd/system/walt-node.service \
	/etc/systemd/system/multi-user.target.wants/walt-node.service

# update kernel modules setup
RUN depmod \$(cd /lib/modules/; ls -1)

# fstab settings
RUN mkdir -p /media/sdcard
ADD fstab /etc/fstab

# ntp configuration
ADD ntp.conf /etc/ntp.conf

# add pi user
# Note: /home/pi/.ssh/authorized_keys must be updated
# when the rpi filesystem is installed on the server
RUN groupadd $RPI_USER
RUN useradd -g $RPI_USER -G sudo $RPI_USER
RUN echo "$RPI_USER:$RPI_USER_PASSWORD" | chpasswd
RUN mkdir -p /home/$RPI_USER/.ssh/
RUN touch /home/$RPI_USER/.hushlogin
RUN chown -R $RPI_USER:$RPI_USER /home/$RPI_USER

# clean up
RUN apt-get clean
EOF
docker build -t "$DOCKER_DEBIAN_RPI_IMAGE" .
result=$?

rm -rf $TMP_DIR

exit $result


