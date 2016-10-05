#!/bin/bash
eval "$(docker run waltplatform/dev-master env)"
THIS_DIR=$(cd $(dirname $0); pwd)
TMP_DIR=$(mktemp -d)
RPI_FS_PATH="/rpi_fs"

cd $TMP_DIR

num_threads=$(nproc)

RPI_FIRMWARE_REPO="https://github.com/raspberrypi/firmware/tags/1.20160921"

BOOT_COPIES=$(echo -n "\
kernel.img              rpi-b/kernel
bcm2708-rpi-b.dtb       rpi-b/dtb
bcm2708-rpi-b-plus.dtb  rpi-b-plus/dtb
kernel7.img             rpi-2-b/kernel
bcm2709-rpi-2-b.dtb     rpi-2-b/dtb
bcm2710-rpi-3-b.dtb     rpi-3-b/dtb
" | while read f g
    do
        echo cp $f $RPI_FS_PATH/$g \&\& \\
    done
    echo -n true
)

BOOT_SYMLINKS=$(echo -n "\
../rpi-b/kernel            rpi-b-plus/kernel
../rpi-2-b/kernel          rpi-3-b/kernel
" | while read f g
    do
        echo ln -s $f $RPI_FS_PATH/$g \&\& \\
    done
    echo -n true
)

cat > Dockerfile << EOF
FROM $DOCKER_RPI_BUILDER_IMAGE
MAINTAINER $DOCKER_IMAGE_MAINTAINER

RUN cdebootstrap --allow-unauthenticated --arch=armhf --foreign -f minimal \
	$DEBIAN_RPI_REPO_VERSION "$RPI_FS_PATH" $DEBIAN_RPI_REPO_URL
RUN cp /usr/bin/qemu-arm-static $RPI_FS_PATH/usr/bin/qemu-arm-static

# download kernel binary, dtb and modules
RUN cd $RPI_FS_PATH && mkdir -p $ALL_RPI_TYPES
RUN cd /tmp && svn co -q $RPI_FIRMWARE_REPO/boot && cd boot && \
    $BOOT_COPIES && \
    $BOOT_SYMLINKS
RUN cd $RPI_FS_PATH/lib && svn co -q $RPI_FIRMWARE_REPO/modules && \
    rm -rf modules/.svn
WORKDIR $RPI_FS_PATH
EOF

docker build -t "$DOCKER_DEBIAN_RPI_BUILDER_IMAGE" .
result=$?

cd $THIS_DIR
rm -rf $TMP_DIR

exit $result

