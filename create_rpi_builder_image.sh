#!/bin/bash
eval "$(docker run waltplatform/dev-master env)"
THIS_DIR=$(cd $(dirname $0); pwd)
TMP_DIR=$(mktemp -d)

cd $TMP_DIR
cp -a $THIS_DIR/walt_bcmrpi_linux.config .

num_threads=$(nproc)

cat > Dockerfile << EOF
FROM $DOCKER_DEBIAN_BASE_IMAGE
MAINTAINER $DOCKER_IMAGE_MAINTAINER

RUN apt-get update && apt-get install -y debootstrap debian-archive-keyring qemu-user-static git make gcc bc
#RUN wget $DEBIAN_RPI_REPO_KEY -O - | apt-key add -
#RUN apt-get update
RUN debootstrap --no-check-gpg --arch=armhf --foreign --variant=minbase \
        --include $DEBIAN_RPI_ADDITIONAL_PACKAGES                       \
        $DEBIAN_RPI_REPO_VERSION "$RPI_FS_PATH" $DEBIAN_RPI_REPO_URL
RUN cp /usr/bin/qemu-arm-static $RPI_FS_PATH/usr/bin/qemu-arm-static

# toolchain
RUN mkdir /tmp/tools
RUN git clone git://github.com/raspberrypi/tools.git -- /tmp/tools
ENV PATH /tmp/tools/arm-bcm2708/gcc-linaro-arm-linux-gnueabihf-raspbian-x64/bin:\$PATH
ENV CCPREFIX /tmp/tools/arm-bcm2708/gcc-linaro-arm-linux-gnueabihf-raspbian-x64/bin/arm-linux-gnueabihf-

# kernel
RUN mkdir /tmp/kernel
WORKDIR /tmp/kernel
RUN git init
RUN git remote add origin $DEBIAN_RPI_KERNEL_REPO
RUN git fetch origin $DEBIAN_RPI_KERNEL_BRANCH_NAME
RUN git remote add ovl $DEBIAN_RPI_KERNEL_OVERLAYFS_REPO
RUN git fetch ovl $DEBIAN_RPI_KERNEL_OVERLAYFS_BRANCH_NAME
RUN git checkout $DEBIAN_RPI_KERNEL_COMMIT
# create a local working branch from there, and go inside
RUN git branch working && git checkout working
# make git happy
RUN git config --global user.email "rpi-builder@liglab.fr"
RUN git config --global user.name "WalT RPi image builder"
# merge the patches of overlayfs branch
RUN git merge -m 'merged overlayfs' "ovl/$DEBIAN_RPI_KERNEL_OVERLAYFS_BRANCH_NAME" 
# prepare kernel config
RUN make mrproper
ADD walt_bcmrpi_linux.config /tmp/kernel/.config
RUN printf 'CONFIG_CROSS_COMPILE="%s"' \$CCPREFIX >> /tmp/kernel/.config && \
    echo >> /tmp/kernel/.config
RUN make      ARCH=arm olddefconfig
RUN make -j $num_threads ARCH=arm && \
    make -j $num_threads ARCH=arm modules && \
    make -j $num_threads ARCH=arm INSTALL_MOD_PATH=$RPI_FS_PATH modules_install && \
    cp arch/arm/boot/zImage $RPI_FS_PATH #&& \
#    rm -rf /tmp/kernel
WORKDIR $RPI_FS_PATH
RUN ln -s zImage kernel
EOF

docker build -t "$DOCKER_DEBIAN_RPI_BUILDER_IMAGE" .
result=$?

cd $THIS_DIR
rm -rf $TMP_DIR

exit $result

#DEBIAN_RPI_KERNEL_REPO="git://github.com/raspberrypi/linux.git"
#DEBIAN_RPI_KERNEL_BRANCH_NAME="rpi-3.18.y"
#DEBIAN_RPI_KERNEL_COMMIT="d64fa8121fca9883d6fb14ca06d2abf66496195e"
## update local branches from remotes
#git fetch "${K_REMOTE_NAME}" "${K_BRANCH_NAME}"
#git checkout "${K_BRANCH_NAME}"
#git pull "${K_REMOTE_NAME}" "${K_BRANCH_NAME}"
#git fetch "${K_OVERLAYFS_REMOTE_NAME}" "${K_OVERLAYFS_BRANCH_NAME}"
#git checkout "${K_OVERLAYFS_BRANCH_NAME}"
#git pull "${K_OVERLAYFS_REMOTE_NAME}" "${K_OVERLAYFS_BRANCH_NAME}"
#	
## go to the commit we want on the rpi-linux branch
#git checkout "${K_VERSION}"
#
## remove any previous working branch if any
#if [ $(git branch | grep -w working | wc -l) -gt 0 ] 
#then
#	git branch -D working
#fi
#
## create a local working branch from there, and go inside
#git branch working
#git checkout working
#
## merge the patches of overlayfs branch
#git merge -m 'merged overlayfs' "${K_OVERLAYFS_BRANCH_NAME}" 
#
#if [[ "${KERNEL}" == "kernel:true" ]] && ! [[ -e "${K_CUR_UIMAGE_PATH}" ]]
#then
#  msg2stdout "cross compile kernel for arm"
#  make mrproper
#  if ! [[ -e ".config" ]]
#  then
#    msg2stdout "create a new config based on ${K_SAVED_CONFIG}"
#    cat "${K_SAVED_CONFIG}" > .config
#  fi
#  make ${K_CC}
#  sudo cp arch/arm/boot/zImage "${FS_KERNEL_PATH}"
#fi
#
#
#if [[ "${MODULES}" == "modules:true" ]] && ! [[ -e "${K_CUR_MODULES_PATH}" ]]
#then
#    msg2stdout "cross compile kernel modules for arm"
#    [[ -e "${K_CUR_MODULES_PATH}" ]] && sudo rm -r "${K_CUR_MODULES_PATH}"
#    sudo mkdir "${K_CUR_MODULES_PATH}"
#    sudo make ${K_CC} modules
#    sudo make ${K_CC} INSTALL_MOD_PATH="${K_CUR_MODULES_PATH}" modules_install
#fi
#
#
#
#revert_rpi_tools_version "${RPI_TOOLS_PATH_INIT_VERSION}"
#
#
#msg2stdout "revert to init dir path"
#cd "${CK_CUR_DIR}"
