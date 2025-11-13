#!/bin/bash
# ======================================================================
# Assignment 3 Part 2: ARM 32-bit kernel and initramfs build script
# Compatible with CU ECEN AELD Autograder (ARMv7)
# ======================================================================

set -euo pipefail

# -----------------------------
# OUTDIR handling
# -----------------------------
OUTDIR="${1:-/tmp/aeld}"
mkdir -p "$OUTDIR"
OUTDIR="$(cd "$OUTDIR" && pwd)"
echo "OUTDIR = $OUTDIR"

# -----------------------------
# Toolchain detection (ARM32)
# -----------------------------
if command -v arm-linux-gnueabi-gcc >/dev/null 2>&1; then
    CROSS="arm-linux-gnueabi-"
else
    echo "❌ ERROR: ARM32 toolchain 'arm-linux-gnueabi-gcc' not found."
    echo "Install with: sudo apt install gcc-arm-linux-gnueabi"
    exit 1
fi

ARCH="arm"
echo "Using CROSS=${CROSS}  ARCH=${ARCH}"

# -----------------------------
# Kernel preparation
# -----------------------------
KERNEL_REPO="https://git.kernel.org/pub/scm/linux/kernel/git/stable/linux.git"
KERNEL_TAG="v5.15.163"
KERNEL_DIR="${OUTDIR}/linux-stable"

if [ ! -f "${OUTDIR}/Image" ]; then
    echo "=== Cloning Linux kernel ${KERNEL_TAG} ==="
    if [ ! -d "${KERNEL_DIR}" ]; then
        git clone --depth 1 --branch "${KERNEL_TAG}" "${KERNEL_REPO}" "${KERNEL_DIR}"
    fi

    pushd "${KERNEL_DIR}"

    echo "=== Building ARM kernel (multi_v7_defconfig) ==="
    make mrproper
    make ARCH=${ARCH} CROSS_COMPILE=${CROSS} multi_v7_defconfig

    make -j$(nproc) ARCH=${ARCH} CROSS_COMPILE=${CROSS} zImage

    # copy kernel image (zImage)
    cp arch/arm/boot/zImage "${OUTDIR}/Image"

    popd
else
    echo "Using cached kernel Image"
fi

# -----------------------------
# Root filesystem layout
# -----------------------------
STAGING="${OUTDIR}/rootfs"
echo "Creating rootfs staging at ${STAGING}"

rm -rf "${STAGING}"
mkdir -p "${STAGING}"

mkdir -p "${STAGING}"/{bin,sbin,dev,etc,proc,sys,usr,usr/bin,usr/sbin,lib,lib64,tmp,home}

# -----------------------------
# BusyBox build (static)
# -----------------------------
BUSYBOX_DIR="${OUTDIR}/busybox"
BUSYBOX_TAG="1_33_1"

if [ ! -d "${BUSYBOX_DIR}" ]; then
    echo "=== Cloning BusyBox ==="
    git clone https://github.com/mirror/busybox.git "${BUSYBOX_DIR}"
fi

pushd "${BUSYBOX_DIR}"
git checkout "${BUSYBOX_TAG}" || true
make distclean
make defconfig

# Force static binary
sed -i 's/# CONFIG_STATIC.*/CONFIG_STATIC=y/' .config
sed -i 's/CONFIG_STATIC=.*/CONFIG_STATIC=y/' .config

echo "=== Building BusyBox static ==="
make -j$(nproc) ARCH=${ARCH} CROSS_COMPILE=${CROSS}
make CONFIG_PREFIX="${STAGING}" ARCH=${ARCH} CROSS_COMPILE=${CROSS} install
popd

# -----------------------------
# Device nodes required at boot
# -----------------------------
echo "Creating device nodes..."

sudo mknod -m 600 "${STAGING}/dev/console" c 5 1 || true
sudo mknod -m 666 "${STAGING}/dev/null" c 1 3 || true

# -----------------------------
# Copy finder-app files to /home
# -----------------------------
APP_DIR="$(cd "$(dirname "$0")" && pwd)"

echo "Copying finder files from ${APP_DIR}"

mkdir -p "${STAGING}/home/conf"

cp -v "${APP_DIR}/finder.sh" "${STAGING}/home/"
cp -v "${APP_DIR}/finder-test.sh" "${STAGING}/home/"
cp -v "${APP_DIR}/autorun-qemu.sh" "${STAGING}/home/" || true
cp -v "${APP_DIR}/conf/"* "${STAGING}/home/conf/"

# Fix shebangs
for f in "${STAGING}/home/"*.sh; do
    sed -i '1s|^#!.*|#!/bin/sh|' "$f"
    chmod +x "$f"
done

# -----------------------------
# Compile writer (static if possible)
# -----------------------------
WRITER_SRC="${APP_DIR}/writer.c"

if [ -f "${WRITER_SRC}" ]; then
    echo "Compiling writer..."
    set +e
    ${CROSS}gcc -static -O2 -Wall -o "${STAGING}/home/writer" "${WRITER_SRC}"
    RC=$?
    set -e
    if [ ${RC} -ne 0 ]; then
        echo "Static build failed, using dynamic"
        ${CROSS}gcc -O2 -Wall -o "${STAGING}/home/writer" "${WRITER_SRC}"
    fi
    chmod +x "${STAGING}/home/writer"
else
    echo "writer.c NOT FOUND in finder-app!"
fi

# -----------------------------
# Create init script
# -----------------------------
cat > "${STAGING}/init" <<'EOF'
#!/bin/sh
mount -t proc none /proc
mount -t sysfs none /sys
mount -t devtmpfs devtmpfs /dev || true

echo "AELD Assignment 3 Boot Successful"
cd /home
exec /bin/sh
EOF

chmod +x "${STAGING}/init"

# -----------------------------
# Set ownership to root
# -----------------------------
sudo chown -R root:root "${STAGING}"
sudo chmod -R a+rX "${STAGING}"

# -----------------------------
# Create initramfs (cpio.gz)
# -----------------------------
echo "=== Creating initramfs ==="
pushd "${STAGING}"
find . | cpio -H newc -ov --owner root:root > "${OUTDIR}/initramfs.cpio"
gzip -f "${OUTDIR}/initramfs.cpio"
popd

echo "==============================================="
echo " Build DONE"
echo " Kernel:    ${OUTDIR}/Image"
echo " Initramfs: ${OUTDIR}/initramfs.cpio.gz"
echo "==============================================="

