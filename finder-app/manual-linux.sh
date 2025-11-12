#!/bin/bash
# -----------------------------------------------------------------------------
# Assignment 3 Part 2 - Manual Kernel + RootFS Build Script
# Author: Siddhove
# -----------------------------------------------------------------------------
# This script builds the Linux kernel and root filesystem manually.
# It will:
#  - Detect correct cross-compiler prefix
#  - Build Linux kernel (minimal config)
#  - Build BusyBox
#  - Assemble rootfs with writer, finder scripts, and configs
#  - Produce Image + initramfs.cpio.gz in outdir
# -----------------------------------------------------------------------------

set -e
START_TIME=$(date +%s)

# ---------- Step 1: Parse arguments ----------
OUTDIR=${1:-/tmp/aeld}
echo "=========================================="
echo " Using output directory: ${OUTDIR}"
echo "=========================================="

mkdir -p "${OUTDIR}"
if [ ! -d "${OUTDIR}" ]; then
    echo "❌ ERROR: Unable to create ${OUTDIR}"
    exit 1
fi

# ---------- Step 2: Detect cross compiler ----------
if command -v aarch64-none-linux-gnu-gcc &> /dev/null; then
    CROSS_COMPILE=aarch64-none-linux-gnu-
elif command -v aarch64-linux-gnu-gcc &> /dev/null; then
    CROSS_COMPILE=aarch64-linux-gnu-
else
    echo "❌ ERROR: No valid aarch64 cross-compiler found!"
    exit 1
fi
ARCH=arm64
echo "✅ Using cross compiler prefix: ${CROSS_COMPILE}"
${CROSS_COMPILE}gcc --version | head -n 1

# ---------- Step 3: Build Linux kernel ----------
cd "${OUTDIR}"
if [ ! -d "${OUTDIR}/linux-stable" ]; then
    echo "🌐 Cloning Linux kernel..."
    git clone --depth 1 --branch v5.15.163 https://git.kernel.org/pub/scm/linux/kernel/git/stable/linux.git linux-stable
fi

cd linux-stable
echo "📦 Checking out kernel version v5.15.163"
git checkout v5.15.163

echo "⚙️ Building kernel (minimal configuration)..."
make ARCH=${ARCH} CROSS_COMPILE=${CROSS_COMPILE} defconfig

# Disable unnecessary modules/drivers
sed -i 's/^CONFIG_MODULES=y/# CONFIG_MODULES is not set/' .config || true
scripts/config --disable CONFIG_MODULES || true
scripts/config --disable CONFIG_SOUND || true
scripts/config --disable CONFIG_DRM || true
scripts/config --disable CONFIG_GPU || true

BUILD_START=$(date +%s)
make ARCH=${ARCH} CROSS_COMPILE=${CROSS_COMPILE} -j2 all
BUILD_END=$(date +%s)
cp arch/arm64/boot/Image ${OUTDIR}/

echo "✅ Kernel build complete in $((BUILD_END - BUILD_START)) seconds."

# ---------- Step 4: Create rootfs structure ----------
cd "${OUTDIR}"
echo "📁 Creating root filesystem structure..."
STAGING="${OUTDIR}/rootfs"
rm -rf "${STAGING}"
mkdir -p "${STAGING}"

cd "${STAGING}"
mkdir -p bin dev etc home lib proc sbin sys tmp usr var
mkdir -p usr/bin usr/sbin var/log

# ---------- Step 5: Build BusyBox ----------
cd "${OUTDIR}"
if [ ! -d "${OUTDIR}/busybox" ]; then
    echo "🌐 Cloning BusyBox..."
    git clone https://busybox.net/git/busybox.git
fi

cd busybox
git checkout 1_33_1
make distclean
make defconfig
echo "🔧 Building BusyBox..."
make ARCH=${ARCH} CROSS_COMPILE=${CROSS_COMPILE} -j2
make CONFIG_PREFIX=${STAGING} install
echo "✅ BusyBox installed into rootfs."

# ---------- Step 6: Library dependencies ----------
cd "${STAGING}"
echo "📚 Copying library dependencies..."
SYSROOT=$(${CROSS_COMPILE}gcc -print-sysroot)
cp -a ${SYSROOT}/lib/* lib/ 2>/dev/null || true
cp -a ${SYSROOT}/lib64/* lib/ 2>/dev/null || true

# ---------- Step 7: Copy finder-app files ----------
cd "${OUTDIR}"
echo "📄 Copying finder apps and scripts..."
mkdir -p ${STAGING}/home/finder-app

cp -r ~/assignment-3-siddjove/finder-app/finder.sh ${STAGING}/home/finder-app/
cp -r ~/assignment-3-siddjove/finder-app/finder-test.sh ${STAGING}/home/finder-app/
cp -r ~/assignment-3-siddjove/finder-app/conf ${STAGING}/home/finder-app/
cp -r ~/assignment-3-siddjove/finder-app/autorun-qemu.sh ${STAGING}/home/finder-app/ || true

# Cross-compile writer
echo "🧱 Building writer app..."
${CROSS_COMPILE}gcc -static -O2 -Wall -o ${STAGING}/home/finder-app/writer ~/assignment-3-siddjove/finder-app/writer.c
echo "✅ Writer built successfully."

# ---------- Step 8: Create init script ----------
cd "${STAGING}"
cat << 'EOF' > init
#!/bin/sh
echo "Init process starting..."
mount -t proc none /proc
mount -t sysfs none /sys
mount -t devtmpfs none /dev
echo "Running finder-test.sh..."
cd /home/finder-app
./finder-test.sh
poweroff -f
EOF

chmod +x init
echo "✅ Init script ready."

# ---------- Step 9: Create initramfs ----------
cd "${STAGING}"
echo "📦 Creating initramfs..."
find . | cpio -H newc -ov --owner root:root > ${OUTDIR}/initramfs.cpio
gzip -f ${OUTDIR}/initramfs.cpio

END_TIME=$(date +%s)
TOTAL_TIME=$((END_TIME - START_TIME))

echo "-------------------------------------------"
echo "✅ Build complete!"
echo "Kernel Image: ${OUTDIR}/Image"
echo "Initramfs:    ${OUTDIR}/initramfs.cpio.gz"
echo "Total build time: ${TOTAL_TIME} seconds"
echo "-------------------------------------------"

