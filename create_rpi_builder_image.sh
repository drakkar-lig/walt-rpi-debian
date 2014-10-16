#!/bin/bash
eval "$(docker run waltplatform/dev-master env)"

docker build -t "$DOCKER_DEBIAN_RPI_BUILDER_IMAGE" - << EOF
FROM $DOCKER_DEBIAN_BASE_IMAGE
MAINTAINER $DOCKER_IMAGE_MAINTAINER

RUN apt-get install -y debootstrap debian-archive-keyring qemu-user-static
#RUN wget $DEBIAN_RPI_REPO_KEY -O - | apt-key add -
#RUN apt-get update
RUN debootstrap --no-check-gpg --arch=armhf --foreign --variant=minbase \
        --include $DEBIAN_RPI_ADDITIONAL_PACKAGES                       \
        $DEBIAN_RPI_REPO_VERSION "$RPI_FS_PATH" $DEBIAN_RPI_REPO_URL
RUN cp /usr/bin/qemu-arm-static $RPI_FS_PATH/usr/bin/qemu-arm-static
EOF

