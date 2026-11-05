#!/usr/bin/env bash
# Build minimal-but-full Debian (trixie) rootfs -> out/rootfs.img
# ext4 labelled RETRO7ROOT. Cross-ready via qemu-user-static binfmt.
set -euo pipefail
cd "$(dirname "$0")/.."
ROOT="$PWD"
STAGE="$ROOT/out/rootfs-build"
IMG="$ROOT/out/rootfs.img"
IMGSIZE="${IMGSIZE:-4200M}"   # MEASURED on this unit: userdata partition (where this
                              # image is flashed) is only 4759 MiB (8 GB eMMC model).
                              # Keep well under 4.6G; games budget is the rest afterwards.
SUITE="${SUITE:-trixie}"
DEBMIRROR="${DEBMIRROR:-http://deb.debian.org/debian}"

# Base already-included at debootstrap level; the rest go in via apt after 2nd stage.
BOOTSTRAP_PKGS="systemd,sudo,iproute2,netbase,locales,ca-certificates,e2fsprogs,openssh-server"
# DESKTOP_PKGS installed later (qemu chroot needs working /proc which we mount):
DESKTOP_PKGS="xserver-xorg openbox xinit xmenu xterm mesa-utils libgl1-mesa-dri \
xinput joystick alsa-utils wpasupplicant rsync"

sudo rm -rf "$STAGE" "$IMG"; mkdir -p out

echo "==> debootstrap stage 1 (foreign, arm64)"
sudo debootstrap --arch=arm64 --variant=minbase --foreign \
  --include="$BOOTSTRAP_PKGS" \
  "$SUITE" "$STAGE" "$DEBMIRROR"

echo "==> stage 2 (qemu binfmt must be enabled: qemu-user-static)"
sudo mount --bind /dev  "$STAGE/dev"
sudo mount --bind /proc "$STAGE/proc"
sudo mount --bind /sys  "$STAGE/sys"
sudo chroot "$STAGE" /debootstrap/debootstrap --second-stage

echo "==> overlay + launcher files"
sudo cp -a "$ROOT/rootfs-overlay/." "$STAGE/"
sudo mkdir -p "$STAGE/home/retro/.config/openbox"
sudo cp "$ROOT/launcher/openbox-rc.xml"      "$STAGE/home/retro/.config/openbox/rc.xml"
sudo cp "$ROOT/launcher/openbox-autostart"   "$STAGE/home/retro/.config/openbox/autostart"
sudo mkdir -p "$STAGE/usr/local/bin"
sudo cp "$ROOT/launcher/games-menu.sh"       "$STAGE/usr/local/bin/games-menu"
sudo chmod 755 "$STAGE/usr/local/bin/games-menu"
sudo mkdir -p "$STAGE/home/retro/.config"
sudo cp "$ROOT/launcher/games.list"          "$STAGE/home/retro/.config/games.list"
sudo chown -R 1000:1000 "$STAGE/home/retro"

echo "==> kernel modules (if kernel was built)"
if [ -d "$ROOT/linux/out/modules/lib/modules" ]; then
  sudo mkdir -p "$STAGE/lib/modules"
  sudo cp -a "$ROOT/linux/out/modules/lib/modules/." "$STAGE/lib/modules/"
  sudo chroot "$STAGE" depmod -a || true
else
  echo "WARN: no built modules found (run scripts/build-kernel.sh first)"
fi

echo "==> users + services (offline enable)"
echo "root:retro" | sudo chroot "$STAGE" chpasswd
sudo chroot "$STAGE" useradd -m -s /bin/bash -G sudo,video,audio,plugdev retro
echo "retro:retro" | sudo chroot "$STAGE" chpasswd
sudo chroot "$STAGE" groupadd -f input 2>/dev/null || true
sudo chroot "$STAGE" chgrp -R input /dev/input 2>/dev/null || true
for s in openssh-server systemd-networkd usb-gadget; do
  sudo chroot "$STAGE" systemctl enable "$s" 2>/dev/null || true
done

echo "==> apt polish (desktop pkgs; may be partial offline)"
sudo chroot "$STAGE" apt-get update || true
sudo chroot "$STAGE" apt-get -y install --no-install-recommends $DESKTOP_PKGS \
  || echo "WARN: desktop pkgs incomplete - finish on-device: sudo apt-get install $DESKTOP_PKGS"

echo "==> unmount + pack image"
sudo umount "$STAGE/dev" "$STAGE/proc" "$STAGE/sys"
truncate -s "$IMGSIZE" "$IMG"
sudo mkfs.ext4 -L RETRO7ROOT -F "$IMG"
MNT=out/mnt; mkdir -p "$MNT"
sudo mount -o loop "$IMG" "$MNT"
sudo rsync -aHAX --numeric-ids "$STAGE"/ "$MNT"/ \
  --exclude=proc/ --exclude=sys/ --exclude=dev/
sudo mkdir -p "$MNT/proc" "$MNT/sys" "$MNT/dev"   # empty mountpoints on ext4 root
sudo umount "$MNT"
sudo chown "$USER":"$USER" "$IMG"

echo "ready: $IMG - flash via scripts/flash.sh rootfs"
