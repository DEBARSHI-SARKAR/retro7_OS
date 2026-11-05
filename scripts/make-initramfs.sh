#!/usr/bin/env bash
# Tiny busybox initramfs: gadget-USB rescue console + find RETRO7ROOT + switch_root.
# NOTE: the busybox binary must be ARM64 + STATIC — it runs on the phone, not the PC.
# (busybox.net publishes no aarch64 build, so we extract Alpine's busybox-static apk,
#  which is just a gzipped tar.)
set -euo pipefail
cd "$(dirname "$0")/.."
RD=out/initramfs
BUSYBOX=out/busybox-aarch64-static
APKURL=https://dl-cdn.alpinelinux.org/alpine/v3.21/main/aarch64/busybox-static-1.37.0-r14.apk

if [ ! -x "$BUSYBOX" ]; then
  echo "==> fetching static arm64 busybox (one-time, from Alpine)"
  rm -rf out/busybox-extract
  mkdir -p out/busybox-extract
  curl -fsSL -o out/busybox-static.apk "$APKURL"
  tar -xzf out/busybox-static.apk -C out/busybox-extract
  cp "$(find out/busybox-extract -type f -name 'busybox*' | head -1)" "$BUSYBOX"
  chmod +x "$BUSYBOX"
fi

if ! file "$BUSYBOX" | grep -q 'ARM aarch64'; then
  echo "ERROR: busybox is not an ARM64 binary — the phone cannot execute it:"
  file "$BUSYBOX"
  exit 1
fi

rm -rf "$RD"
mkdir -p "$RD"/{bin,dev,proc,sys,tmp,run,etc,mnt,usr/local/sbin}
cp "$BUSYBOX" "$RD/bin/busybox"
chmod +x "$RD/bin/busybox"

cp initramfs/init "$RD/init"
chmod +x "$RD/init"
cp rootfs-overlay/usr/local/sbin/usb-gadget.sh "$RD/usr/local/sbin/"
chmod +x  "$RD/usr/local/sbin/usb-gadget.sh"

(cd "$RD" && find . | cpio -o -H newc | gzip -9) > out/initramfs.cpio.gz
echo "ready: out/initramfs.cpio.gz  (build boot.img with scripts/build-kernel.sh)"
