#!/bin/bash
set -e
set -u

OUTDIR=${1:-/tmp/aeld}
KERNEL_REPO=https://git.kernel.org/pub/scm/linux/kernel/git/stable/linux.git
KERNEL_VERSION=v5.15.163
BUSYBOX_VERSION=1_33_1
CROSS_COMPILE=aarch64-linux-gnu-

echo "Using output directory: ${OUTDIR}"

# Create the output directory if it doesn’t exist
mkdir -p ${OUTDIR}

# Step 1: Clone Linux kernel if not already present
cd ${OUTDIR}
if [ ! -d "${OUTDIR}/linux-stable" ]; then
    echo "Cloning Linux kernel source..."
    git clone --depth 1 --branch ${KERNEL_VERSION} ${KERNEL_REPO} linux-stable
fi

# Step 2: Build the kernel
cd ${OUTDIR}/linux-stable
echo "Checking out version ${KERNEL_VERSION}"
git checkout ${KERNEL_VERSION}

echo "Starting kernel build..."
make ARCH=arm64 CROSS_COMPILE=${CROSS_COMPILE} defconfig
make -j$(nproc) ARCH=arm64 CROSS_COMPILE=${CROSS_COMPILE} all
make -j$(nproc) ARCH=arm64 CROSS_COMPILE=${CROSS_COMPILE} modules
make -j$(nproc) ARCH=arm64 CROSS_COMPILE=${CROSS_COMPILE} dtbs

# Copy the kernel image
cp ${OUTDIR}/linux-stable/arch/arm64/boot/Image ${OUTDIR}/
echo "Kernel build complete! Kernel image copied to ${OUTDIR}"

