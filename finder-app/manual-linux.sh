#!/bin/bash
# Script outline to install and build kernel.
# Author: Siddhant Jajoo.  (Modified & fixed)

set -e
set -u

OUTDIR=/tmp/aeld
KERNEL_REPO=git://git.kernel.org/pub/scm/linux/kernel/git/stable/linux-stable.git
KERNEL_VERSION=v5.15.163
BUSYBOX_VERSION=1_33_1
FINDER_APP_DIR=$(realpath $(dirname $0))
ARCH=arm64
CROSS_COMPILE=aarch64-linux-gnu-
SYSROOT=$(${CROSS_COMPILE}gcc -print-sysroot)





if [ $# -lt 1 ]
then
    echo "Using default directory ${OUTDIR} for output"
else
    OUTDIR=$1
    echo "Using passed directory ${OUTDIR} for output"
fi

mkdir -p ${OUTDIR}
cd "${OUTDIR}"

########## KERNEL BUILD ##########
if [ ! -d "${OUTDIR}/linux-stable" ]; then
    echo "CLONING LINUX ${KERNEL_VERSION}"
    git clone ${KERNEL_REPO} --depth 1 --single-branch --branch ${KERNEL_VERSION}
fi

if [ ! -e ${OUTDIR}/linux-stable/arch/${ARCH}/boot/Image ]; then
    cd linux-stable
    echo "Checking out version ${KERNEL_VERSION}"
    git checkout ${KERNEL_VERSION}

    make ARCH=${ARCH} CROSS_COMPILE=${CROSS_COMPILE} mrproper
    make ARCH=${ARCH} CROSS_COMPILE=${CROSS_COMPILE} defconfig
    make -j$(nproc) ARCH=${ARCH} CROSS_COMPILE=${CROSS_COMPILE} all
    make -j$(nproc) ARCH=${ARCH} CROSS_COMPILE=${CROSS_COMPILE} modules
    make -j$(nproc) ARCH=${ARCH} CROSS_COMPILE=${CROSS_COMPILE} dtbs
fi

echo "Copying kernel Image..."
cp ${OUTDIR}/linux-stable/arch/${ARCH}/boot/Image ${OUTDIR}/

########## ROOT FS ##########
echo "Creating root filesystem..."
cd "${OUTDIR}"

if [ -d rootfs ]; then
    echo "Deleting rootfs and recreating"
    sudo rm -rf rootfs
fi

mkdir -p rootfs/{bin,sbin,etc,proc,sys,usr/{bin,sbin},lib,dev,home,tmp,var}

########## BUSYBOX ##########
cd "${OUTDIR}"

BUSYBOX_TARBALL_VERSION=$(echo ${BUSYBOX_VERSION} | tr '_' '.')

if [ ! -d busybox ]; then
    echo "Downloading BusyBox ${BUSYBOX_TARBALL_VERSION}..."
    wget https://busybox.net/downloads/busybox-${BUSYBOX_TARBALL_VERSION}.tar.bz2
    tar -xjf busybox-${BUSYBOX_TARBALL_VERSION}.tar.bz2
    mv busybox-${BUSYBOX_TARBALL_VERSION} busybox
    cd busybox
    make distclean
    make ARCH=${ARCH} CROSS_COMPILE=${CROSS_COMPILE} defconfig
else
    cd busybox
fi


make -j$(nproc) ARCH=${ARCH} CROSS_COMPILE=${CROSS_COMPILE}
make ARCH=${ARCH} CROSS_COMPILE=${CROSS_COMPILE} CONFIG_PREFIX=${OUTDIR}/rootfs install

echo "Library dependencies:"
${CROSS_COMPILE}readelf -a ${OUTDIR}/rootfs/bin/busybox | grep "interpreter"
${CROSS_COMPILE}readelf -a ${OUTDIR}/rootfs/bin/busybox | grep "Shared library"

########## COPY LIBRARIES SAFELY ##########
cd "${OUTDIR}/rootfs"

INTERPRETER=$(${CROSS_COMPILE}readelf -a bin/busybox | grep "Requesting program interpreter" | awk -F':' '{print $2}' | tr -d '[] ')
LIBS=$(${CROSS_COMPILE}readelf -a bin/busybox | grep "Shared library" | awk -F':' '{print $2}' | tr -d '[] ')

echo "Copying interpreter: $INTERPRETER"
cp -v "$SYSROOT$INTERPRETER" lib/

mkdir -p lib/aarch64-linux-gnu/

echo "Copying shared libs..."
set +e  # prevent script crash if find fails
for lib in $LIBS; do
    FOUND=$(find "$SYSROOT" -type f -name "$lib" | head -n 1)
    if [ -n "$FOUND" ]; then
        cp -v "$FOUND" lib/aarch64-linux-gnu/
    else
        echo "WARNING: Could not find library $lib"
    fi
done
set -e

########## DEVICE NODES ##########
sudo mknod -m 666 dev/null c 1 3
sudo mknod -m 600 dev/console c 5 1

########## WRITER UTILITY ##########
cd "$FINDER_APP_DIR"
make clean
make CROSS_COMPILE=${CROSS_COMPILE}
cp writer ${OUTDIR}/rootfs/home/

########## COPY APPLICATION FILES ##########
cp finder.sh ${OUTDIR}/rootfs/home/
cp finder-test.sh ${OUTDIR}/rootfs/home/
cp conf/username.txt ${OUTDIR}/rootfs/home/
cp conf/assignment.txt ${OUTDIR}/rootfs/home/
cp autorun-qemu.sh ${OUTDIR}/rootfs/home/

sudo chown -R root:root ${OUTDIR}/rootfs

########## INITRAMFS ##########
cd ${OUTDIR}/rootfs
echo "Creating initramfs..."
find . | cpio -H newc -ov --owner root:root > ${OUTDIR}/initramfs.cpio
gzip -f ${OUTDIR}/initramfs.cpio

echo "Done."

