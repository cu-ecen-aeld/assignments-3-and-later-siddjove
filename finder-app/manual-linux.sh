#!/bin/bash
set -e

OUTDIR=${1:-/tmp/aeld}
ARCH=arm64

echo "=========================================="
echo "  AELD Assignment 3 - Manual Linux Build"
echo "  Output dir: $OUTDIR"
echo "=========================================="

mkdir -p "$OUTDIR"
cd "$OUTDIR"

# -------------------------------
# 1️⃣ Detect cross compiler
# -------------------------------
if command -v aarch64-linux-gnu-gcc &>/dev/null; then
    CROSS=aarch64-linux-gnu-
elif command -v aarch64-none-linux-gnu-gcc &>/dev/null; then
    CROSS=aarch64-none-linux-gnu-
else
    echo "❌ ERROR: No aarch64 compiler found!"
    exit 1
fi

echo "Using cross compiler: $CROSS"

# -------------------------------
# 2️⃣ Kernel (cached)
# -------------------------------
if [ ! -f "$OUTDIR/Image" ]; then
    echo "🌐 Cloning Linux kernel..."
    git clone --depth 1 --branch v5.15.163 \
        https://git.kernel.org/pub/scm/linux/kernel/git/stable/linux.git linux-stable

    cd linux-stable
    make ARCH=$ARCH CROSS_COMPILE=$CROSS defconfig
    make -j$(nproc) ARCH=$ARCH CROSS_COMPILE=$CROSS Image

    cp arch/arm64/boot/Image "$OUTDIR/Image"
    cd "$OUTDIR"
else
    echo "🧩 Using cached kernel Image"
fi

# -------------------------------
# 3️⃣ Build BusyBox static (cached)
# -------------------------------
if [ ! -f "$OUTDIR/busybox/busybox" ]; then
    echo "🌐 Cloning BusyBox..."
    git clone https://github.com/mirror/busybox.git busybox
    cd busybox

    git checkout 1_33_1
    make distclean
    make defconfig

    # Force static busybox (so no glibc copied!)
    sed -i 's/# CONFIG_STATIC is not set/CONFIG_STATIC=y/' .config
    sed -i 's/# CONFIG_STATIC_LIBGCC is not set/CONFIG_STATIC_LIBGCC=y/' .config

    echo "⚙️ Building BusyBox static..."
    make -j$(nproc) ARCH=$ARCH CROSS_COMPILE=$CROSS
    cd "$OUTDIR"
else
    echo "🧩 Using cached BusyBox build"
fi

# -------------------------------
# 4️⃣ Create minimal rootfs
# -------------------------------
ROOTFS="$OUTDIR/rootfs"
rm -rf "$ROOTFS"
mkdir -p "$ROOTFS"

mkdir -p "$ROOTFS"/{bin,sbin,etc,proc,sys,dev,home,finder-app,tmp}
mkdir -p "$ROOTFS/home/finder-app/conf"

# Install BusyBox
cd "$OUTDIR/busybox"
make CONFIG_PREFIX="$ROOTFS" install

# -------------------------------
# 5️⃣ Copy finder-app files
# -------------------------------
APPDIR=~/assignment-3-siddjove/finder-app

cp "$APPDIR/finder.sh"       "$ROOTFS/home/finder-app/"
cp "$APPDIR/finder-test.sh"  "$ROOTFS/home/finder-app/"
cp "$APPDIR/writer"          "$ROOTFS/home/finder-app/"
cp "$APPDIR/conf/"*          "$ROOTFS/home/finder-app/conf/"

echo "📂 Finder-app files copied."

# -------------------------------
# 6️⃣ Create /init script
# -------------------------------
cat << 'EOF' > "$ROOTFS/init"
#!/bin/sh
mount -t proc none /proc
mount -t sysfs none /sys
mount -t devtmpfs none /dev

echo "Init starting..."

cd /home/finder-app
./finder-test.sh

poweroff -f
EOF

chmod +x "$ROOTFS/init"

# -------------------------------
# 7️⃣ Build initramfs
# -------------------------------
cd "$ROOTFS"
find . -print0 | cpio --null -ov --format=newc | gzip -9 > "$OUTDIR/initramfs.cpio.gz"

echo "=========================================="
echo "  ✔️ DONE"
echo "  Kernel:    $OUTDIR/Image"
echo "  Initramfs: $OUTDIR/initramfs.cpio.gz"
echo "=========================================="

