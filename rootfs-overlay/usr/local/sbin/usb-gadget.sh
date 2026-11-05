#!/bin/sh
# USB gadget: ECM network + ACM serial console, Linux Foundation composite.
# Host-side pairing: PC gets 10.15.0.1 (see docs/bringup.md §7).
set -e
modprobe libcomposite 2>/dev/null || true
# configfs carries the gadget API — systemd mounts it in the real rootfs,
# but the initramfs does not, so mount it here (no-op if already mounted)
mkdir -p /sys/kernel/config
mount -t configfs configfs /sys/kernel/config 2>/dev/null || true
G=/sys/kernel/config/usb_gadget/retro7
[ -d /sys/kernel/config/usb_gadget ] || exit 0

# unbind existing binding first so we can (re)apply config
if [ -d "$G" ]; then
  echo "" > "$G/UDC" 2>/dev/null || true
else
  mkdir -p "$G"
fi

echo 0x1d6b > "$G/idVendor"   # Linux Foundation
echo 0x0104 > "$G/idProduct"  # Multifunction Composite
echo 0x0100 > "$G/bcdDevice"

mkdir -p "$G/strings/0x409"
echo "retro7" > "$G/strings/0x409/manufacturer"
echo "Galaxy On7 retro" > "$G/strings/0x409/product"

mkdir -p "$G/functions/ncm.usb0" "$G/functions/acm.usb0"
mkdir -p "$G/configs/c.1"
echo 250 > "$G/configs/c.1/MaxPower"
ln -sf "$G/functions/ncm.usb0"  "$G/configs/c.1/"
ln -sf "$G/functions/acm.usb0"  "$G/configs/c.1/"

UDC=$(ls /sys/class/udc | head -1)
[ -n "$UDC" ] && echo "$UDC" > "$G/UDC"
echo "usb-gadget: bound to $UDC"
