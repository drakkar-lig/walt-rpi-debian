#!/bin/bash
eval "$(docker run waltplatform/dev-master env)"
THIS_DIR=$(cd $(dirname $0); pwd)
TMP_DIR=$(mktemp -d)
RPI_FS_PATH="/rpi_fs"

cd $TMP_DIR

num_threads=$(nproc)
DEBIAN_VERSION="stretch"

# RPI_FIRMWARE_REPO files include a pre-compiled kernel.
# However, we will also deal with RPI_KERNEL_REPO to generate
# the kernel headers directory.
# Of course those two must match the same kernel version.
# Also note that we will use svn instead of git, in order
# to avoid cloning the whole history.
RPI_FIRMWARE_REPO="https://github.com/raspberrypi/firmware/tags/1.20190215"
RPI_KERNEL_REPO="https://github.com/raspberrypi/linux/tags/raspberrypi-kernel_1.20190215-1"
RPI_KERNEL_VERSION="4.14.98" # match version of modules, see subdir 'modules' of firmware repo
RPI_DEBIAN_VERSION="$DEBIAN_VERSION"
RPI_DEBIAN_MIRROR_URL="http://mirrordirector.raspbian.org/raspbian"
RPI_DEBIAN_SECTIONS="main contrib non-free rpi"

PACKAGES=$(cat << EOF | tr "\n" " "
vim net-tools procps
subversion make gcc g++ libncurses5-dev bzip2 wget cpio python
unzip bc kpartx dosfstools debootstrap debian-archive-keyring
qemu-user-static:i386 git flex bison
EOF
)

cp -p $THIS_DIR/Module.symvers.README .

cat > Dockerfile << EOF
FROM debian:$DEBIAN_VERSION
MAINTAINER Etienne Duble <etienne.duble@imag.fr>

# setup package management
RUN echo deb http://deb.debian.org/debian ${DEBIAN_VERSION}-backports main >> \
            /etc/apt/sources.list.d/backports.list && \
    echo 'debconf debconf/frontend select Noninteractive' | debconf-set-selections && \
    dpkg --add-architecture i386

# install packages
RUN apt-get update && apt-get upgrade -y && apt-get install -y $PACKAGES && \
    apt-get clean

# populate target os filesystem
RUN debootstrap --no-check-gpg --arch=armhf --foreign --variant=minbase \
    --include raspbian-archive-keyring,apt-utils \
	$RPI_DEBIAN_VERSION "$RPI_FS_PATH" $RPI_DEBIAN_MIRROR_URL
RUN rm $RPI_FS_PATH/etc/hostname
RUN cp /usr/bin/qemu-arm-static $RPI_FS_PATH/usr/bin/qemu-arm-static
RUN echo deb $RPI_DEBIAN_MIRROR_URL $RPI_DEBIAN_VERSION $RPI_DEBIAN_SECTIONS \
        > "$RPI_FS_PATH/etc/apt/sources.list.saved" && \
    echo deb http://archive.raspberrypi.org/debian/ $RPI_DEBIAN_VERSION main \
        >> "$RPI_FS_PATH/etc/apt/sources.list.saved"

# download kernel binary, dtb and modules
RUN cd /tmp && svn co -q $RPI_FIRMWARE_REPO/boot && \
    svn co -q $RPI_FIRMWARE_REPO/extra && \
    rm -rf boot/.svn extra/.svn && \
    mkdir -p $RPI_FS_PATH/boot && \
    cp -r boot $RPI_FS_PATH/boot/.common
RUN cd $RPI_FS_PATH/lib && svn co -q $RPI_FIRMWARE_REPO/modules && \
    rm -rf modules/.svn
RUN cd $RPI_FS_PATH && mkdir -p usr/src && cd usr/src && \
    svn co -q $RPI_KERNEL_REPO linux-source-${RPI_KERNEL_VERSION} && \
    cd linux-source-${RPI_KERNEL_VERSION} && rm -rf .svn && \
    mkdir extra && cp /tmp/extra/Module*.symvers extra && \
    ln -s /usr/src/linux-source-${RPI_KERNEL_VERSION} \
            ../../../lib/modules/${RPI_KERNEL_VERSION}-v7+/build && \
    ln -s /usr/src/linux-source-${RPI_KERNEL_VERSION} \
            ../../../lib/modules/${RPI_KERNEL_VERSION}+/build
ADD Module.symvers.README $RPI_FS_PATH/usr/src/linux-source-${RPI_KERNEL_VERSION}/
WORKDIR $RPI_FS_PATH
EOF

docker build -t "waltplatform/rpi-debian-builder" .
result=$?

cd $THIS_DIR
rm -rf $TMP_DIR

exit $result

