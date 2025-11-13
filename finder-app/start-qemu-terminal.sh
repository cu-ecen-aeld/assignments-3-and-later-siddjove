#!/bin/bash
# -------------------------------------------------------------------
# QEMU launcher for Assignment 3
# Usage: ./start-qemu-terminal.sh <kernel Image> <initramfs.cpio.gz>
# -------------------------------------------------------------------

KERNEL_IMAGE="$1"
INITRAMFS="$2"

if [ -z "$KERNEL_IMAGE" ] || [ -z "$INITRAMFS" ]; then
    echo "Usage: $0 <kernel Image> <initramfs.cpio.gz>"
    exit 1
fi

if [ ! -f "$KERNEL_IMAGE" ]; then
    echo "❌ Missing kernel image at $KERNEL_IMAGE"
    exit 1
fi

if [ ! -f "$INITRAMFS" ]; then
    echo "❌ Missing initrd image at $INITRAMFS"
    exit 1
fi

echo "🚀 Launching QEMU..."
qemu-system-aarch64 \
    -M virt \
    -cpu cortex-a53 \
    -nographic \
    -smp 1 \
    -m 1024 \
    -kernel "$KERNEL_IMAGE" \
    -initrd "$INITRAMFS" \
    -append "console=ttyAMA0"

