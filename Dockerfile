FROM debian:stretch as builder
MAINTAINER Etienne Duble <etienne.duble@imag.fr>

# RPI_FIRMWARE_REPO files include a pre-compiled kernel.
# However, we will also deal with RPI_KERNEL_REPO to generate
# the kernel headers directory.
# Of course those two must match the same kernel version.
# Also note that we will use svn instead of git, in order
# to avoid cloning the whole history.
ENV RPI_FIRMWARE_REPO="https://github.com/raspberrypi/firmware/tags/1.20190215"
ENV RPI_KERNEL_REPO="https://github.com/raspberrypi/linux/tags/raspberrypi-kernel_1.20190215-1"
# RPI_KERNEL_VERSION must match version of modules, see subdir 'modules' of firmware repo
ENV RPI_KERNEL_VERSION="4.14.98"
ENV RPI_DEBIAN_VERSION="stretch"
ENV RPI_DEBIAN_MIRROR_URL="http://mirrordirector.raspbian.org/raspbian"
ENV RPI_DEBIAN_SECTIONS="main contrib non-free rpi"

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
    libpixman-1-dev && \
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
    mkdir extra && cp /tmp/extra/Module*.symvers extra && \
    ln -s /usr/src/linux-source-${RPI_KERNEL_VERSION} \
            ../../../lib/modules/${RPI_KERNEL_VERSION}-v7+/build && \
    ln -s /usr/src/linux-source-${RPI_KERNEL_VERSION} \
            ../../../lib/modules/${RPI_KERNEL_VERSION}+/build
ADD Module.symvers.README /rpi_fs/usr/src/linux-source-${RPI_KERNEL_VERSION}/

# download and compile patched qemu
# (we have to install walt software within the target filesystem
#  binfmt_misc may not be available here, so we need a specific qemu-aarch64
#  patched for added option '-execve')
WORKDIR /root
RUN git clone https://github.com/drakkar-lig/qemu-execve.git && \
    cd qemu-execve && \
    git checkout fa9ecbd5523ab967e5d8a2d99afc2b5ee9f538e8 && \
    ./configure --target-list=arm-linux-user --static && \
    make -j

# chroot customization image
# **************************
FROM scratch as chroot_image
MAINTAINER Etienne Duble <etienne.duble@imag.fr>
LABEL walt.node.models=rpi-b,rpi-b-plus,rpi-2-b,rpi-3-b,rpi-3-b-plus
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
        avahi-daemon libnss-mdns cron ptpd busybox-static netcat dosfstools \
        u-boot-tools && \
    apt-get clean

# add various files
ADD overlay /

# generate start.uboot and populate boot dirs
RUN cd /boot/.common/ && ./generate-start-uboot.sh && \
    /create_model_boot_dir.sh rpi-b kernel.img bcm2708-rpi-b.dtb 0 && \
    /create_model_boot_dir.sh rpi-b-plus kernel.img bcm2708-rpi-b-plus.dtb 0 && \
    /create_model_boot_dir.sh rpi-2-b kernel7.img bcm2709-rpi-2-b.dtb 0 && \
    /create_model_boot_dir.sh rpi-3-b kernel7.img bcm2710-rpi-3-b.dtb 1 && \
    /create_model_boot_dir.sh rpi-3-b-plus kernel7.img bcm2710-rpi-3-b-plus.dtb 1

# update kernel modules setup
RUN for subdir in $(cd /lib/modules/; ls -1); do depmod $subdir; done

# cleanup
RUN rm /usr/local/bin/qemu-arm /create_model_boot_dir.sh
SHELL ["/bin/sh", "-c"]

# set an entrypoint (handy when debugging)
ENTRYPOINT /bin/bash
