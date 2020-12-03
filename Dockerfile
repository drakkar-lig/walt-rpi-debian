FROM debian:stretch as builder
MAINTAINER Etienne Duble <etienne.duble@imag.fr>

# RPI_FIRMWARE_REPO files include a pre-compiled kernel.
# However, we will also deal with RPI_KERNEL_REPO to generate
# the kernel headers directory.
# Of course those two must match the same kernel version.
# Also note that we will use svn instead of git, in order
# to avoid cloning the whole history.
ENV RPI_FIRMWARE_REPO="https://github.com/raspberrypi/firmware/tags/1.20200723"
ENV RPI_KERNEL_REPO="https://github.com/raspberrypi/linux/tags/raspberrypi-kernel_1.20200723-1"
# RPI_KERNEL_VERSION must match version of modules, see subdir 'modules' of firmware repo
ENV RPI_KERNEL_VERSION="5.4.51"
ENV RPI_VIRT_KERNEL_VERSION="v5.4"
ENV RPI_DEBIAN_VERSION="buster"
ENV RPI_DEBIAN_MIRROR_URL="http://mirrordirector.raspbian.org/raspbian"
ENV RPI_DEBIAN_SECTIONS="main contrib non-free rpi"
ENV INITRAMFS_TOOLS_REPO="https://gricad-gitlab.univ-grenoble-alpes.fr/dublee/initramfs-tools"

# setup package management
RUN echo deb http://deb.debian.org/debian stretch-backports main >> \
            /etc/apt/sources.list.d/backports.list && \
    echo 'debconf debconf/frontend select Noninteractive' | debconf-set-selections && \
    dpkg --add-architecture i386

# install packages
RUN apt-get update && apt-get upgrade -y && apt-get install -y \
    vim net-tools procps subversion make gcc g++ libncurses5-dev bzip2 \
    wget cpio python unzip bc kpartx dosfstools debootstrap debian-archive-keyring \
    qemu-user-static:i386 git flex bison pkg-config zlib1g-dev libglib2.0-dev \
    libpixman-1-dev gcc-arm-linux-gnueabi libssl-dev kmod \
    dpkg-dev debhelper bash-completion shellcheck rdfind && \
    apt-get clean

# populate target os filesystem
RUN debootstrap --no-check-gpg --arch=armhf --foreign --variant=minbase \
    --include raspbian-archive-keyring,apt-utils \
	$RPI_DEBIAN_VERSION "/rpi_fs" $RPI_DEBIAN_MIRROR_URL
RUN rm /rpi_fs/etc/hostname
RUN cp /usr/bin/qemu-arm-static /rpi_fs/usr/bin/qemu-arm-static
RUN echo deb $RPI_DEBIAN_MIRROR_URL $RPI_DEBIAN_VERSION $RPI_DEBIAN_SECTIONS \
        > "/rpi_fs/etc/apt/sources.list.saved" && \
    echo deb http://archive.raspberrypi.org/debian/ $RPI_DEBIAN_VERSION main \
        >> "/rpi_fs/etc/apt/sources.list.saved"

# download kernel binary, dtb and modules
RUN cd /tmp && svn co -q $RPI_FIRMWARE_REPO/boot && \
    svn co -q $RPI_FIRMWARE_REPO/extra && \
    rm -rf boot/.svn extra/.svn && \
    mkdir -p /rpi_fs/boot && \
    cp -r boot /rpi_fs/boot/.common
RUN cd /rpi_fs/lib && svn co -q $RPI_FIRMWARE_REPO/modules && \
    rm -rf modules/.svn
RUN cd /rpi_fs && mkdir -p usr/src && cd usr/src && \
    svn co -q $RPI_KERNEL_REPO linux-source-${RPI_KERNEL_VERSION} && \
    cd linux-source-${RPI_KERNEL_VERSION} && rm -rf .svn && \
    mkdir extra && cp /tmp/extra/Module*.symvers extra
ADD Module.symvers.README /rpi_fs/usr/src/linux-source-${RPI_KERNEL_VERSION}/

# download and compile patched qemu
# (we have to install walt software within the target filesystem
#  binfmt_misc may not be available here, so we need a specific qemu-arm
#  patched for added option '-execve')
WORKDIR /root
RUN git clone https://github.com/drakkar-lig/qemu-execve.git && \
    cd qemu-execve && \
    git checkout fa9ecbd5523ab967e5d8a2d99afc2b5ee9f538e8 && \
    ./configure --target-list=arm-linux-user --static && \
    make -j

# download and build a linux kernel compatible with qemu arm 'virt' machine
RUN svn co -q https://github.com/torvalds/linux/tags/${RPI_VIRT_KERNEL_VERSION} linux
WORKDIR /root/linux
ENV ARCH=arm
ENV CROSS_COMPILE=arm-linux-gnueabi-
ADD linux.config .config
RUN make olddefconfig && make -j
RUN make modules_install INSTALL_MOD_PATH=/rpi_fs
RUN mkdir -p /rpi_fs/boot/qemu-arm && \
    cp arch/arm/boot/zImage /rpi_fs/boot/qemu-arm/kernel
RUN cp include/config/kernel.release /rpi_fs/boot/qemu-arm/

# download and build modified initramfs-tools package (mainly to allow nbfs boot)
WORKDIR /root
RUN git clone -b nbfs $INITRAMFS_TOOLS_REPO
RUN cd initramfs-tools && dpkg-buildpackage --no-sign
RUN mv initramfs-tools*.deb /rpi_fs/root

# deduplicate
RUN rdfind -makehardlinks true /rpi_fs

# chroot customization image
# **************************
FROM scratch as chroot_image
MAINTAINER Etienne Duble <etienne.duble@imag.fr>
LABEL walt.node.models=rpi-b,rpi-b-plus,rpi-2-b,rpi-3-b,rpi-3-b-plus,rpi-4-b,qemu-arm
LABEL walt.server.minversion=4
WORKDIR /
COPY --from=builder /rpi_fs /
COPY --from=builder /root/qemu-execve/arm-linux-user/qemu-arm /usr/local/bin/
SHELL ["/usr/local/bin/qemu-arm", "-execve", "/bin/sh", "-c"]

# resume deboostrap process
RUN ln -sf /bin/true /bin/mount && \
    /debootstrap/debootstrap --second-stage && \
    cp /etc/apt/sources.list.saved /etc/apt/sources.list && \
    apt-get clean

# register Raspberry Pi Archive Signing Key
ADD 82B129927FA3303E.pub /tmp/
RUN apt-key add - < /tmp/82B129927FA3303E.pub && rm /tmp/82B129927FA3303E.pub

# install packages
RUN apt-get update && \
    apt-get -y --no-install-recommends install \
        init ssh sudo kmod usbutils python-pip udev lldpd vim texinfo \
        iputils-ping python-serial ntpdate ifupdown lockfile-progs \
        avahi-daemon libnss-mdns cron ptpd netcat dosfstools \
        u-boot-tools libraspberrypi-bin rpi-eeprom initramfs-tools && \
    apt-get clean

# install an older static version of busybox for compatibility with
# node init scripts distributed with older walt server version
# (if installing busybox-static package instead, we would have
# to set LABEL walt.server.minversion to 5)
COPY --from=waltplatform/rpi-stretch /bin/busybox /bin

# add various files
ADD overlay /

# run customization script, then clean up
RUN /customize.sh && \
    rm /usr/local/bin/qemu-arm /customize.sh
SHELL ["/bin/sh", "-c"]

# set an entrypoint (handy when debugging)
ENTRYPOINT /bin/bash
