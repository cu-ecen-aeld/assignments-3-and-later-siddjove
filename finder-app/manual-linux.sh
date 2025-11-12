#!/usr/bin/env bash
# Assignment 3 part 2 - manual kernel + rootfs build
# Robust script for local dev and Github Actions autograder
set -euo pipefail
IFS=$'\n\t'

START_TIME=$(date +%s)

# ---------- Settings ----------
OUTDIR="${1:-/tmp/aeld}"
KERNEL_TAG="v5.15.163"
BUSYBOX_VERSION="1_33_1"
MAKE_JOBS=2

echo "=========================================="
echo " Using output directory: ${OUTDIR}"
echo "=========================================="

mkdir -p "${OUTDIR}"
if [ ! -d "${OUTDIR}" ]; then
    echo "❌ ERROR: Unable to create ${OUTDIR}"
    exit 1
fi

# ---------- Cross compiler detection ----------
CROSS_COMPILE=""
PREFS=( "aarch64-none-linux-gnu-" "aarch64-linux-gnu-" "arm-linux-gnueabihf-" )

for p in "${PREFS[@]}"; do
    if command -v "${p}gcc" >/dev/null 2>&1; then
        CROSS_COMPILE="${p}"
        break
    fi
done

if [ -z "${CROSS_COMPILE}" ]; then
    echo "❌ ERROR: No aarch64 cross-compiler (aarch64-*-gcc) found on PATH."
    echo "Install toolchain (for example: gcc-aarch64-linux-gnu) and ensure it's on PATH."
    exit 1
fi

ARCH="arm64"
echo "✅ Using cross compiler prefix: ${CROSS_COMPILE}"
"${CROSS_COMPILE}gcc" --version | head -n1 || true

# ---------- Helper: repo root detection ----------
REPO_ROOT="$(git rev-parse --show-toplevel 2>/dev/null || true)"
if [ -z "$REPO_ROOT" ]; then
    # fallback used by autograder environment
    REPO_ROOT="/__w/assignments-3-and-later-siddjove/assignments-3-and-later-siddjove"
fi
echo "Repo root: ${REPO_ROOT}"

# ---------- Build Linux kernel ----------
cd "${OUTDIR}"

if [ ! -d "${OUTDIR}/linux-stable" ]; then
    echo "🌐 Cloning Linux kernel..."
    git clone --depth 1 --branch "${KERNEL_TAG}" https://git.kernel.org/pub/scm/linux/kernel/git/stable/linux.git linux-stable || {
        echo "❌ Failed to clone kernel repo"
        exit 1
    }
fi

cd linux-stable
echo "📦 Checking out kernel version ${KERNEL_TAG}"
git fetch --tags origin || true
git checkout "${KERNEL_TAG}" || true

echo "⚙️ Generating defconfig..."
make ARCH="${ARCH}" CROSS_COMPILE="${CROSS_COMPILE}" defconfig

# Try to slim down config where possible (best-effort; scripts/config may not exist in older trees)
if [ -x scripts/config ]; then
    echo "🧰 Disabling some big subsystems to speed up build..."
    scripts/config --disable CONFIG_MODULES || true
    scripts/config --disable CONFIG_DEBUG_INFO || true
    scripts/config --disable CONFIG_KALLSYMS || true
fi

echo "🔨 Building kernel (Image)..."
BUILD_START=$(date +%s)
make ARCH="${ARCH}" CROSS_COMPILE="${CROSS_COMPILE}" -j"${MAKE_JOBS}" Image || {
    echo "❌ Kernel build failed"
    exit 1
}
BUILD_END=$(date +%s)
cp -f arch/arm64/boot/Image "${OUTDIR}/Image"
echo "✅ Kernel build complete in $((BUILD_END - BUILD_START))s; saved to ${OUTDIR}/Image"

# ---------- Prepare rootfs staging ----------
STAGING="${OUTDIR}/rootfs"
echo "📁 Creating rootfs staging at ${STAGING}"
rm -rf "${STAGING}"
mkdir -p "${STAGING}"
cd "${STAGING}"

# minimal directories
mkdir -p bin dev etc home/lib home/bin proc sbin sys tmp usr/bin usr/sbin var/log

# ---------- BusyBox ----------
cd "${OUTDIR}"
if [ ! -d "${OUTDIR}/busybox" ]; then
    echo "🌐 Obtaining BusyBox source..."
    # try official mirror first; fallback to tarball
    if git clone https://busybox.net/git/busybox.git busybox 2>/dev/null; then
        :
    else
        echo "⚠️ git clone busybox failed; trying HTTPS mirror..."
        if git clone https://github.com/mirror/busybox.git busybox 2>/dev/null; then
            :
        else
            echo "⚠️ mirror clone failed; trying tarball download..."
            BB_TARBALL="busybox-${BUSYBOX_VERSION}.tar.bz2"
            if command -v wget >/dev/null 2>&1; then
                wget -q "https://busybox.net/downloads/${BB_TARBALL}" || true
            fi
            if [ -f "${BB_TARBALL}" ]; then
                tar xjf "${BB_TARBALL}"
                mv "busybox-${BUSYBOX_VERSION}" busybox
            else
                echo "❌ Could not fetch BusyBox source automatically. Please ensure network access or provide busybox in ${OUTDIR}/busybox"
                exit 1
            fi
        fi
    fi
else
    echo "📁 Using existing BusyBox in ${OUTDIR}/busybox"
fi

cd busybox
# check out requested tag if exists (best-effort)
if git rev-parse --verify "origin/${BUSYBOX_VERSION}" >/dev/null 2>&1; then
    git checkout -f "${BUSYBOX_VERSION}" || true
fi

make distclean >/dev/null 2>&1 || true
make defconfig
echo "🔧 Building BusyBox..."
make ARCH="${ARCH}" CROSS_COMPILE="${CROSS_COMPILE}" -j"${MAKE_JOBS}" || {
    echo "❌ BusyBox build failed"
    exit 1
}
echo "📥 Installing BusyBox into staging..."
make CONFIG_PREFIX="${STAGING}" install || {
    echo "❌ BusyBox install failed"
    exit 1
}
echo "✅ BusyBox installed into rootfs."

# ---------- Copy runtime libraries from toolchain sysroot ----------
SYSROOT="$(${CROSS_COMPILE}gcc -print-sysroot)"
echo "📚 Copying runtime libs from sysroot: ${SYSROOT}"
if [ -d "${SYSROOT}/lib" ]; then
    mkdir -p "${STAGING}/lib"
    cp -a "${SYSROOT}/lib/"* "${STAGING}/lib/" 2>/dev/null || true
fi
if [ -d "${SYSROOT}/lib64" ]; then
    mkdir -p "${STAGING}/lib"
    cp -a "${SYSROOT}/lib64/"* "${STAGING}/lib/" 2>/dev/null || true
fi

# copy dynamic linker if present
if [ -f "${SYSROOT}/lib/ld-linux-aarch64.so.1" ]; then
    cp -a "${SYSROOT}/lib/ld-linux-aarch64.so.1" "${STAGING}/lib/" 2>/dev/null || true
fi

# ---------- Copy finder-app files ----------
cd "${OUTDIR}"
echo "📄 Copying finder-app files into rootfs..."

APP_DIR="${REPO_ROOT}/finder-app"

# fail if not present
if [ ! -d "${APP_DIR}" ]; then
    echo "❌ finder-app directory not found at ${APP_DIR}"
    exit 1
fi

# ensure destination
mkdir -p "${STAGING}/home/finder-app"
mkdir -p "${STAGING}/home/finder-app/conf"

# finder.sh
if [ -f "${APP_DIR}/finder.sh" ]; then
    cp -f "${APP_DIR}/finder.sh" "${STAGING}/home/finder-app/"
else
    echo "❌ finder.sh not found in ${APP_DIR}"
    exit 1
fi

# finder-test.sh
if [ -f "${APP_DIR}/finder-test.sh" ]; then
    cp -f "${APP_DIR}/finder-test.sh" "${STAGING}/home/finder-app/"
else
    echo "❌ finder-test.sh not found in ${APP_DIR}"
    exit 1
fi

# conf files (assignment.txt and username.txt expected)
if [ -d "${APP_DIR}/conf" ]; then
    cp -r "${APP_DIR}/conf/"* "${STAGING}/home/finder-app/conf/" || {
        echo "❌ copying conf files failed"
        exit 1
    }
else
    echo "❌ conf directory missing in ${APP_DIR}"
    exit 1
fi

# writer: prefer a prebuilt binary in repo, otherwise compile writer.c
if [ -f "${APP_DIR}/writer" ]; then
    cp -f "${APP_DIR}/writer" "${STAGING}/home/finder-app/writer"
elif [ -f "${APP_DIR}/writer.c" ]; then
    echo "🛠️  Building writer from source (cross compile)..."
    "${CROSS_COMPILE}gcc" -static -O2 -Wall -o "${STAGING}/home/finder-app/writer" "${APP_DIR}/writer.c" || {
        echo "❌ cross-build of writer failed"
        exit 1
    }
else
    echo "❌ writer or writer.c not found in ${APP_DIR}"
    exit 1
fi

# autorun-qemu.sh (optional)
if [ -f "${APP_DIR}/autorun-qemu.sh" ]; then
    cp -f "${APP_DIR}/autorun-qemu.sh" "${STAGING}/home/finder-app/autorun-qemu.sh"
fi

# ensure scripts are executable
chmod +x "${STAGING}/home/finder-app/"*.sh || true
chmod +x "${STAGING}/home/finder-app/writer" || true

echo "✅ Finder-app files copied."

# ---------- Create a simple init script ----------
cat > "${STAGING}/init" <<'INIT_EOF'
#!/bin/sh
# simple init for initramfs
echo "Init process starting..."
mount -t proc none /proc || true
mount -t sysfs none /sys || true
mount -t devtmpfs none /dev || true
# move to finder app and run tests
cd /home/finder-app || exit 1
# ensure busybox sh is used
export PATH=/bin:/sbin:/usr/bin:/usr/sbin
./finder-test.sh || true
poweroff -f || exit 0
INIT_EOF

chmod +x "${STAGING}/init"

# ---------- Build initramfs.cpio.gz ----------
cd "${STAGING}"
echo "📦 Generating initramfs.cpio.gz..."
# ensure owners are root
find . -print0 | cpio --null -ov --format=newc --owner root:root > "${OUTDIR}/initramfs.cpio"
gzip -f "${OUTDIR}/initramfs.cpio"

END_TIME=$(date +%s)
TOTAL_TIME=$((END_TIME - START_TIME))

echo "-------------------------------------------"
echo "✅ Build complete!"
echo " Kernel Image: ${OUTDIR}/Image"
echo " Initramfs:    ${OUTDIR}/initramfs.cpio.gz"
echo " Total time:   ${TOTAL_TIME}s"
echo "-------------------------------------------"

