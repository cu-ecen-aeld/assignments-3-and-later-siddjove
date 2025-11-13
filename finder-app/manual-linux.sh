# -------------------------------
# 4️⃣ Install BusyBox (static)
# -------------------------------
cd "$OUTDIR/busybox"

# Patch config for CI-safe static build
scripts/config --file .config \
    --enable CONFIG_STATIC \
    --disable CONFIG_PAM \
    --disable CONFIG_SELINUX \
    --disable CONFIG_FEATURE_UTMP \
    --disable CONFIG_FEATURE_WTMP \
    --disable CONFIG_FEATURE_LAST_SUPPORTED \
    --disable CONFIG_FEATURE_IPV6

make -j$(nproc)

# Install (works locally + on GitHub Actions)
make CONFIG_PREFIX="$ROOTFS" install || sudo make CONFIG_PREFIX="$ROOTFS" install

echo "✔ BusyBox installed into rootfs"

# -------------------------------
# 5️⃣ Copy finder-app files
# -------------------------------
# Use repo-relative finder-app directory
APPDIR="$REPO_ROOT/finder-app"

mkdir -p "$ROOTFS/home/finder-app/conf"

# Copy scripts/binaries
cp "$APPDIR/finder.sh"        "$ROOTFS/home/finder-app/"      || { echo "❌ Missing finder.sh"; exit 1; }
cp "$APPDIR/finder-test.sh"   "$ROOTFS/home/finder-app/"      || { echo "❌ Missing finder-test.sh"; exit 1; }
cp "$APPDIR/writer"           "$ROOTFS/home/finder-app/"      || { echo "❌ Missing writer binary"; exit 1; }

# Copy conf files
cp "$APPDIR/conf/"*           "$ROOTFS/home/finder-app/conf/" || { echo "❌ Missing conf files"; exit 1; }

# Ensure everything is executable
chmod +x "$ROOTFS/home/finder-app/"*

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

cd /home/finder-app || exec /bin/sh
chmod +x finder.sh finder-test.sh writer

./finder-test.sh

poweroff -f
EOF

chmod +x "$ROOTFS/init"
echo "✔ init script created"

# -------------------------------
# 7️⃣ Build initramfs
# -------------------------------
cd "$ROOTFS"

# MUST be root-owned and executable
sudo chown -R root:root "$ROOTFS"

find . -print0 | cpio --null -ov --format=newc | gzip -9 > "$OUTDIR/initramfs.cpio.gz"

echo "=========================================="
echo "  ✔️ Build Complete"
echo "  Kernel:    $OUTDIR/Image"
echo "  Initramfs: $OUTDIR/initramfs.cpio.gz"
echo "=========================================="

