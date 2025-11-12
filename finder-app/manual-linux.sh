#!/bin/bash
# -----------------------------------------------------------------------------
# Assignment 3 Part 2 - Manual Linux + RootFS Build
# Author: Siddhove
# -----------------------------------------------------------------------------
# Builds kernel, busybox, writer, and root filesystem for QEMU ARM64.
# -----------------------------------------------------------------------------

set -e
set -u

# ---------------------- Setup Output Directory -------------------------------
OUTDIR=${1:-/tmp/aeld}
KERNEL_REPO=https://git.kernel.org/pub/scm/linux/kernel/git/stable/linux.git
KERNEL_VERSION=v5.15.163
BUSYBOX_REPO=https://git.busybox.net/busybox
BUSYBOX_VERSION=1_33_1
FINDER_APP_DIR=$(realpath "$(dirname "$0")")

ARCH=arm64
# Detect available cross-compiler prefix
if command -v aarch64-none-linux-gnu-gcc &> /dev/null; then
    CROSS_COMPILE=aarch64-none-linux-gnu-
elif command -v aarch64-linux-gnu-gcc &> /dev/null; then
    CROSS_COMPILE=aarch64-linux-gnu-
else
    echo "Error: No aarch64 cross-compiler found!"
    exit 1
fi

ARCH=arm64


echo "Using output directory: ${OUTDIR}"
mkdir -p ${OUTDIR}

# ---------------------- Build Kernel ----------------------------------------
cd ${OUTDIR}
if [ ! -d "${OUTDIR}/linux-stable" ]; then
    echo "Cloning Linux kernel..."
    git clone ${KERNEL_REPO} linux-stable --depth 1 --branch ${KERNEL_VERSION}
fi

cd linux-stable
echo "Checking out kernel version ${KERNEL_VERSION}"
git checkout ${KERNEL_VERSION}

echo "Building kernel..."
make ARCH=${ARCH} CROSS_COMPILE=${CROSS_COMPILE} defconfig
make -j$(nproc) ARCH=${ARCH} CROSS_COMPILE=${CROSS_COMPILE} all
cp arch/${ARCH}/boot/Image ${OUTDIR}/

# ---------------------- Build BusyBox ---------------------------------------
cd ${OUTDIR}
if [ ! -d "${OUTDIR}/busybox" ]; then
    echo "Cloning BusyBox..."
    git clone ${BUSYBOX_REPO}
fi

cd busybox
git checkout ${BUSYBOX_VERSION}
echo "Building BusyBox..."
make distclean
make defconfig
make ARCH=${ARCH} CROSS_COMPILE=${CROSS_COMPILE} -j$(nproc)
make CONFIG_PREFIX=${OUTDIR}/rootfs ARCH=${ARCH} CROSS_COMPILE=${CROSS_COMPILE} install

# ---------------------- Create Root Filesystem ------------------------------
echo "Creating root filesystem..."
cd ${OUTDIR}
mkdir -p ${OUTDIR}/rootfs
cd ${OUTDIR}/rootfs
mkdir -p bin dev etc home lib lib64 proc sbin sys tmp usr var
mkdir -p usr/bin usr/sbin

# Copy busybox output (should already be installed)
echo "Library dependencies..."
cd ${OUTDIR}/rootfs
${CROSS_COMPILE}readelf -a bin/busybox | grep "program interpreter" || true
${CROSS_COMPILE}readelf -a bin/busybox | grep "Shared library" || true

# ---------------------- Copy App Files --------------------------------------
echo "Copying finder apps and scripts..."
cd ${OUTDIR}/rootfs/home
sudo mkdir -p finder-app

sudo cp -r ${FINDER_APP_DIR}/finder.sh finder-app/
sudo cp -r ${FINDER_APP_DIR}/finder-test.sh finder-app/
sudo cp -r ${FINDER_APP_DIR}/conf finder-app/
sudo cp -r ${FINDER_APP_DIR}/writer finder-app/
sudo cp -r ${FINDER_APP_DIR}/autorun-qemu.sh finder-app/

sudo chmod -R 755 finder-app
sudo chown -R root:root finder-app

# ---------------------- Device Nodes ----------------------------------------
echo "Creating device nodes..."
cd ${OUTDIR}/rootfs
sudo mknod -m 666 dev/null c 1 3 || true
sudo mknod -m 622 dev/console c 5 1 || true
sudo chown -R root:root *

# ---------------------- Create Initramfs ------------------------------------
echo "Creating initramfs..."
cd ${OUTDIR}/rootfs
find . | cpio -H newc -ov --owner root:root > ${OUTDIR}/initramfs.cpio
gzip -f ${OUTDIR}/initramfs.cpio

echo "Build complete!"
echo "Kernel Image: ${OUTDIR}/Image"
echo "Initramfs:    ${OUTDIR}/initramfs.cpio.gz"

