#!/bin/bash
# Assignment 3 Part 2 – Manual Kernel + RootFS Build
# Clean, static, simple, correct working version
# Author: Siddjove 

set -e
set -u

########################
# Variables
########################
OUTDIR=${1:-/tmp/aeld}
KERNEL_VERSION=linux-5.15.y
KERNEL_REPO=https://github.com/gregkh/linux.git


ARCH=arm64
CROSS_COMPILE=aarch64-linux-gnu-
FINDER_APP_DIR=$(realpath $(dirname $0))

echo "Using OUTDIR = ${OUTDIR}"
mkdir -p "${OUTDIR}"

cd "${OUTDIR}"

########################
# Clone Kernel Repo (stable, fast)
########################
if [ ! -d linux-stable ]; then
    echo "Cloning Linux STABLE kernel (GregKH mirror)..."
    git clone --depth 1 --branch linux-5.15.y https://github.com/gregkh/linux.git linux-stable
fi

########################
# Build Minimal Kernel (NON-INTERACTIVE)
########################
if [ ! -e linux-stable/arch/${ARCH}/boot/Image ]; then
    cd linux-stable

    # always start clean
    make mrproper

    # generate ARM64 default config
    make ARCH=${ARCH} CROSS_COMPILE=${CROSS_COMPILE} defconfig

    # DO NOT modify .config → removes interactive oldconfig prompts

    # build only the Image (no modules, no extras)
    make -j$(nproc) ARCH=${ARCH} CROSS_COMPILE=${CROSS_COMPILE} Image
    make -j$(nproc) ARCH=${ARCH} CROSS_COMPILE=${CROSS_COMPILE} dtbs
fi

echo "Copying kernel Image..."

if [ -f "${OUTDIR}/linux-stable/arch/${ARCH}/boot/Image" ]; then
    cp "${OUTDIR}/linux-stable/arch/${ARCH}/boot/Image" "${OUTDIR}/"
elif [ -f "${OUTDIR}/linux-stable/arch/${ARCH}/boot/Image.gz" ]; then
    echo "Kernel built Image.gz — using that as Image"
    cp "${OUTDIR}/linux-stable/arch/${ARCH}/boot/Image.gz" "${OUTDIR}/Image"
else
    echo "ERROR: No kernel Image or Image.gz found!"
    exit 1
fi



########################
# Create RootFS Staging Area
########################
cd "${OUTDIR}"

echo "Creating clean rootfs..."
sudo rm -rf rootfs || true
mkdir -p rootfs/{bin,sbin,etc,proc,sys,usr/{bin,sbin},dev,home,tmp,var}

########################
# Build Minimal BusyBox (works with latest repo)
########################

cd "${OUTDIR}"

if [ ! -d busybox ]; then
    echo "Cloning BusyBox (official repo)..."
    git clone --depth 1 https://git.busybox.net/busybox busybox
fi

cd busybox

make distclean
make defconfig

# Force static build
sed -i 's/# CONFIG_STATIC is not set/CONFIG_STATIC=y/' .config

# Disable heavy networking features
disable_list="
CONFIG_WGET
CONFIG_TELNET
CONFIG_TELNETD
CONFIG_PING
CONFIG_IP
CONFIG_ROUTE
CONFIG_NSLOOKUP
CONFIG_NTPD
CONFIG_TFTP
CONFIG_WHOIS
CONFIG_TRACEROUTE
CONFIG_UDHCPC
CONFIG_UDHCPD
CONFIG_TC
CONFIG_TC_STANDALONE
CONFIG_FEATURE_TC_INGRESS
"
for opt in $disable_list; do
    sed -i "s/$opt=y/# $opt is not set/" .config
done

# IMPORTANT: regenerate dependencies + auto-answer NEW options
yes "" | make oldconfig

# Build BusyBox
make -j$(nproc) ARCH=${ARCH} CROSS_COMPILE=${CROSS_COMPILE}

# Install
make CONFIG_PREFIX="${OUTDIR}/rootfs" ARCH=${ARCH} CROSS_COMPILE=${CROSS_COMPILE} install

########################
# Create Device Nodes
########################
cd "${OUTDIR}/rootfs"
sudo mknod -m 666 dev/null c 1 3
sudo mknod -m 600 dev/console c 5 1

########################
# Build Writer (static)
########################
cd "$FINDER_APP_DIR"
make clean
make CROSS_COMPILE=${CROSS_COMPILE}

cp writer "${OUTDIR}/rootfs/home/"

########################
# Copy Finder Scripts
########################
cp finder.sh "${OUTDIR}/rootfs/home/"
cp finder-test.sh "${OUTDIR}/rootfs/home/"
cp autorun-qemu.sh "${OUTDIR}/rootfs/home/"

mkdir -p "${OUTDIR}/rootfs/home/conf/"
cp conf/assignment.txt "${OUTDIR}/rootfs/home/conf/"
cp conf/username.txt "${OUTDIR}/rootfs/home/conf/"

# Modify finder-test.sh path
sed -i 's|\.\./conf/assignment.txt|conf/assignment.txt|' "${OUTDIR}/rootfs/home/finder-test.sh"

########################
# Create SIMPLE init script
########################
cat << 'EOF' > "${OUTDIR}/rootfs/init"
#!/bin/sh
mount -t proc none /proc
mount -t sysfs none /sys
exec /bin/sh
EOF

chmod +x "${OUTDIR}/rootfs/init"

########################
# Build initramfs
########################
cd "${OUTDIR}/rootfs"
echo "Creating initramfs..."
find . | cpio -H newc -ov --owner root:root > "${OUTDIR}/initramfs.cpio"
gzip -f "${OUTDIR}/initramfs.cpio"

echo "Done. Kernel and initramfs ready."

########################################
# Copy Image + initramfs for autograder
########################################

echo "Installing kernel & initramfs for autograder..."

mkdir -p /tmp/aesd-autograder

cp "${OUTDIR}/Image" /tmp/aesd-autograder/Image
cp "${OUTDIR}/initramfs.cpio.gz" /tmp/aesd-autograder/initramfs.cpio.gz

echo "Autograder files installed."


