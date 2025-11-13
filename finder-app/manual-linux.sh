#!/usr/bin/env bash
# manual-linux.sh - build kernel + busybox rootfs + initramfs for assignment3
# Usage: ./manual-linux.sh [outdir]
# Output: $OUTDIR/Image and $OUTDIR/initramfs.cpio.gz
set -euo pipefail

# ---------- arguments ----------
OUTDIR="${1:-/tmp/aeld}"
KERNEL_TAG="v5.15.163"
BUSYBOX_VERSION="1_33_1"    # BusyBox branch/tag style
BUSYBOX_TARBALL="busybox-1.33.1.tar.bz2"
BUSYBOX_URL="https://busybox.net/downloads/${BUSYBOX_TARBALL}"

echo "=========================================="
echo " 🚀 Manual Linux build"
echo " Using output directory: ${OUTDIR}"
echo " Kernel tag: ${KERNEL_TAG}"
echo " BusyBox: ${BUSYBOX_VERSION}"
echo "=========================================="

mkdir -p "${OUTDIR}"
OUTDIR="$(cd "${OUTDIR}" && pwd -P)"

# ---------- helper: detect repo root ----------
REPO_ROOT="$(git rev-parse --show-toplevel 2>/dev/null || true)"
if [ -z "${REPO_ROOT}" ]; then
  # fallback used in CI/autograder: assume current working dir is repo root
  REPO_ROOT="$(pwd -P)"
fi
echo "Detected repo root: ${REPO_ROOT}"

# ---------- detect cross compiler ----------
CROSS_PREFIX=""
if command -v aarch64-none-linux-gnu-gcc >/dev/null 2>&1; then
  CROSS_PREFIX="aarch64-none-linux-gnu-"
elif command -v aarch64-linux-gnu-gcc >/dev/null 2>&1; then
  CROSS_PREFIX="aarch64-linux-gnu-"
else
  CROSS_PREFIX=""
fi

if [ -n "${CROSS_PREFIX}" ]; then
  echo "Using cross-compiler prefix: '${CROSS_PREFIX}'"
else
  echo "No aarch64 cross compiler found - BusyBox will be built natively (useful for local testing only)."
fi

# ---------- Step A: Build kernel Image if missing ----------
KERNEL_DIR="${OUTDIR}/linux-stable"
KERNEL_IMAGE="${OUTDIR}/Image"
if [ ! -f "${KERNEL_IMAGE}" ]; then
  echo "🌐 Preparing kernel sources..."
  if [ ! -d "${KERNEL_DIR}" ]; then
    git clone --depth 1 --branch "${KERNEL_TAG}" \
      https://git.kernel.org/pub/scm/linux/kernel/git/stable/linux.git "${KERNEL_DIR}" \
      || { echo "❗ git clone kernel failed — make sure network works"; exit 1; }
  fi

  cd "${KERNEL_DIR}"
  echo "Checking out ${KERNEL_TAG}"
  git fetch --depth 1 origin "${KERNEL_TAG}" >/dev/null 2>&1 || true
  git checkout "${KERNEL_TAG}" >/dev/null 2>&1 || true

  echo "⚙ Creating default config..."
  if [ -n "${CROSS_PREFIX}" ]; then
    make ARCH=arm64 CROSS_COMPILE=${CROSS_PREFIX} defconfig
  else
    make ARCH=arm64 defconfig
  fi

  echo "🔨 Building kernel Image (this may be slow)..."
  if [ -n "${CROSS_PREFIX}" ]; then
    make ARCH=arm64 CROSS_COMPILE=${CROSS_PREFIX} -j"$(nproc)"
  else
    make ARCH=arm64 -j"$(nproc)"
  fi

  if [ -f "${KERNEL_DIR}/arch/arm64/boot/Image" ]; then
    cp "${KERNEL_DIR}/arch/arm64/boot/Image" "${KERNEL_IMAGE}"
    echo "✅ Kernel Image created at ${KERNEL_IMAGE}"
  else
    echo "❌ Kernel build did not produce Image at expected location"
    exit 1
  fi
else
  echo "🧩 Cached kernel Image found at ${KERNEL_IMAGE}"
fi

# ---------- Step B: Prepare staging rootfs ----------
ROOTFS="${OUTDIR}/rootfs"
echo "📁 Preparing staging rootfs at ${ROOTFS}"
rm -rf "${ROOTFS}"
mkdir -p "${ROOTFS}"
cd "${ROOTFS}"
mkdir -p bin sbin dev etc proc sys tmp root mnt home var run usr/bin usr/sbin lib lib64

# ---------- Step C: BusyBox build & install (static) ----------
BUSYBOX_SRC_DIR="${OUTDIR}/busybox-${BUSYBOX_VERSION}"
if [ ! -d "${BUSYBOX_SRC_DIR}" ]; then
  echo "🌐 Obtaining BusyBox sources..."
  mkdir -p "${OUTDIR}/busybox-src"
  cd "${OUTDIR}/busybox-src"
  # try download tarball
  if command -v curl >/dev/null 2>&1; then
    if curl -fLo "${BUSYBOX_TARBALL}" "${BUSYBOX_URL}"; then
      tar xjf "${BUSYBOX_TARBALL}"
      # extracted folder name expected busybox-1.33.1
      if [ -d "busybox-1.33.1" ]; then
        mv "busybox-1.33.1" "${BUSYBOX_SRC_DIR}"
      fi
    else
      echo "⚠️ BusyBox tarball download failed; trying git mirror..."
    fi
  fi

  # fallback: try git mirror
  if [ ! -d "${BUSYBOX_SRC_DIR}" ]; then
    if command -v git >/dev/null 2>&1; then
      BUSYBOX_MIRROR="https://github.com/mirror/busybox.git"
      git clone --depth 1 --branch "${BUSYBOX_VERSION}" "${BUSYBOX_MIRROR}" "${BUSYBOX_SRC_DIR}" || true
    fi
  fi
fi

if [ ! -d "${BUSYBOX_SRC_DIR}" ]; then
  echo "❌ BusyBox sources not available at ${BUSYBOX_SRC_DIR}"
  exit 1
fi

cd "${BUSYBOX_SRC_DIR}"
make distclean >/dev/null 2>&1 || true
make defconfig

# Ensure static build and disable bulky features (safe edits)
# set CONFIG_STATIC=y (defconfig may have it commented out)
if ! grep -q "^CONFIG_STATIC=y" .config 2>/dev/null; then
  sed -i 's/# CONFIG_STATIC is not set/CONFIG_STATIC=y/' .config || true
fi
# disable PAM, SELINUX, UTMP/WTMP, IPV6 if present
sed -i 's/^CONFIG_PAM=.*/# CONFIG_PAM is not set/' .config || true
sed -i 's/^CONFIG_SELINUX=.*/# CONFIG_SELINUX is not set/' .config || true
sed -i 's/^CONFIG_FEATURE_UTMP=.*/# CONFIG_FEATURE_UTMP is not set/' .config || true
sed -i 's/^CONFIG_FEATURE_WTMP=.*/# CONFIG_FEATURE_WTMP is not set/' .config || true
sed -i 's/^CONFIG_FEATURE_LAST_SUPPORTED=.*/# CONFIG_FEATURE_LAST_SUPPORTED is not set/' .config || true
sed -i 's/^CONFIG_FEATURE_IPV6=.*/# CONFIG_FEATURE_IPV6 is not set/' .config || true

echo "🔧 Building BusyBox (static). This may take a bit..."
if [ -n "${CROSS_PREFIX}" ]; then
  make ARCH=arm64 CROSS_COMPILE=${CROSS_PREFIX} -j"$(nproc)"
  make ARCH=arm64 CROSS_COMPILE=${CROSS_PREFIX} CONFIG_PREFIX="${ROOTFS}" install
else
  make -j"$(nproc)"
  make CONFIG_PREFIX="${ROOTFS}" install
fi

echo "✔ BusyBox installed into rootfs"

# ---------- Step D: copy library dependencies (only if cross-compiled and needed) ----------
if [ -n "${CROSS_PREFIX}" ]; then
  if command -v "${CROSS_PREFIX}gcc" >/dev/null 2>&1; then
    SYSROOT="$(${CROSS_PREFIX}gcc -print-sysroot 2>/dev/null || true)"
    if [ -n "${SYSROOT}" ] && [ -d "${SYSROOT}" ]; then
      echo "📚 Copying library dependencies from sysroot ${SYSROOT}"
      mkdir -p "${ROOTFS}/lib"
      cp -a "${SYSROOT}/lib"/* "${ROOTFS}/lib/" 2>/dev/null || true
      cp -a "${SYSROOT}/lib64"/* "${ROOTFS}/lib/" 2>/dev/null || true
    fi
  fi
fi

# ---------- Step E: Copy finder-app files into staging ----------
APPDIR="${REPO_ROOT}/finder-app"
if [ ! -d "${APPDIR}" ]; then
  echo "❌ Could not locate finder-app directory (${APPDIR})"
  exit 1
fi

echo "📄 Copying finder-app files from ${APPDIR}..."
mkdir -p "${ROOTFS}/home/finder-app"
mkdir -p "${ROOTFS}/home/finder-app/conf"

# copy scripts and writer binary (writer must be present and executable in repo)
if [ -f "${APPDIR}/finder.sh" ]; then
  cp -a "${APPDIR}/finder.sh" "${ROOTFS}/home/finder-app/"
else
  echo "❌ Missing ${APPDIR}/finder.sh"
  exit 1
fi

if [ -f "${APPDIR}/finder-test.sh" ]; then
  cp -a "${APPDIR}/finder-test.sh" "${ROOTFS}/home/finder-app/"
else
  echo "❌ Missing ${APPDIR}/finder-test.sh"
  exit 1
fi

# writer (if source present, cross compile it into staging; else copy binary)
if [ -f "${APPDIR}/writer" ]; then
  echo "Copying existing writer binary"
  cp -a "${APPDIR}/writer" "${ROOTFS}/home/finder-app/"
elif [ -f "${APPDIR}/writer.c" ]; then
  echo "Cross-compiling writer.c into staging"
  if [ -n "${CROSS_PREFIX}" ]; then
    ${CROSS_PREFIX}gcc -static -O2 -Wall -o "${ROOTFS}/home/finder-app/writer" "${APPDIR}/writer.c"
  else
    gcc -static -O2 -Wall -o "${ROOTFS}/home/finder-app/writer" "${APPDIR}/writer.c"
  fi
else
  echo "❌ Missing writer (binary or writer.c) in ${APPDIR}"
  exit 1
fi

# copy conf files
if compgen -G "${APPDIR}/conf/*" >/dev/null; then
  cp -a "${APPDIR}/conf/"* "${ROOTFS}/home/finder-app/conf/" || { echo "❌ Failed to copy conf files"; exit 1; }
else
  echo "❌ No conf files in ${APPDIR}/conf/"
  exit 1
fi

# Make scripts executable inside staging
chmod +x "${ROOTFS}/home/finder-app/"* || true
echo "📂 Finder-app files copied."

# ---------- Step F: create init (busybox will provide /bin/sh) ----------
cat > "${ROOTFS}/init" <<'EOF'
#!/bin/sh
# simple init for assignment
mount -t proc none /proc 2>/dev/null || true
mount -t sysfs none /sys 2>/dev/null || true
mount -t devtmpfs none /dev 2>/dev/null || true

echo "Init starting..."
cd /home/finder-app || exec /bin/sh
# ensure scripts are executable
chmod +x ./finder.sh ./finder-test.sh ./writer 2>/dev/null || true

# Run the test script. finder-test.sh is written to succeed without 'make' present.
./finder-test.sh || true

# If finder-test.sh didn't poweroff, force
echo "Init finished, powering off..."
poweroff -f || halt -f || reboot -f || true
EOF

chmod +x "${ROOTFS}/init" || true

# ---------- Step G: Build initramfs (set owner inside cpio to root:root) ----------
echo "📦 Creating initramfs (root-owned files inside archive)..."
cd "${ROOTFS}"
# Use --owner so files in archive are root-owned regardless of host permissions
find . -print0 | cpio --null -ov --format=newc --owner root:root 2>/dev/null | gzip -9 > "${OUTDIR}/initramfs.cpio.gz"
sync

echo "=========================================="
echo "  ✔️ Build complete"
echo "  Kernel:    ${OUTDIR}/Image"
echo "  Initramfs: ${OUTDIR}/initramfs.cpio.gz"
echo "=========================================="

# quick sanity checks
if [ ! -f "${OUTDIR}/Image" ] || [ ! -f "${OUTDIR}/initramfs.cpio.gz" ]; then
  echo "❌ Build failed to produce required files"
  exit 1
fi

exit 0

