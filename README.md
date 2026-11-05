# retro7 — one phone, one kernel, one menu, all the games

A **full normal Linux** experience for the Samsung Galaxy On7 / On7 Pro
(SM-G600F / G600FY / G600S — Snapdragon 410 / msm8916, Adreno 306).

- **Kernel:** mainline fork [`msm8916-mainline/linux`](https://github.com/msm8916-mainline/linux)
  (carries `msm8916-samsung-o7` device tree) + our hardware bring-up
- **Userspace:** minimal-but-full Debian (`debootstrap minbase`, systemd, apt-universe available)
- **DE:** X11 + Openbox + a tiny custom game-launcher menu (touch + gamepad friendly)
- **Games:** re3 / reVC + old-NFS reverse-engineered reimplementations, aarch64 builds
- **Power:** cross-compiled on your PC, plain apt on-device

## Legend
✅ proven on this device · ⚠️ partial/untested · ❌ needs kernel/porting work

| Piece | Status |
|---|---|
| lk2nd boot + fastboot | ✅ |
| Display panel + brightness workaround | ✅ |
| GPU (freedreno/Mesa), WiFi, Bluetooth, buttons | ✅ |
| USB device mode → SSH/gadget-net console | ✅ |
| Debian minbase rootfs on userdata | ✅ DIY in this repo |
| Openbox + launcher menu | ✅ DIY in this repo |
| Touchscreen (Zinitix ZT7548) | ❌ port driver → docs/bringup.md §2 |
| Audio | ⚠️ drivers exist, o7 routing untested → §3 |
| USB **host** mode (wired gamepad) | ⚠️ device-mode ok, host path absent → §4 |
| Battery/charging (SM5703) | ⚠️ → §5 |
| Camera, GPS, sensors | ❌ out of scope |

## Milestones
| | Goal | Proven by |
|---|---|---|
| M0 | lk2nd flashed (fastboot unlocked) | Vol-Down *while booting* shows lk2nd fastboot |
| M1 | Our kernel + busybox initramfs RAM-boot | SSH-console over USB |
| M2 | Debian rootfs on userdata, autologin | boots to console |
| M3 | Touchscreen merged | menu usable by finger |
| M4 | USB-host gamepad + audio | game playable with sound |
| M5 | Ports compiled (re3/reVC, NFS reimpl) | ~30 fps GTA III |

## Layout
```
scripts/build-kernel.sh     kernel + dtb + modules (+ boot.img)
scripts/make-initramfs.sh   tiny busybox initramfs (rescue + RAM-boot test)
scripts/make-rootfs.sh      Debian minbase arm64 -> rootfs.img (ext4 RETRO7ROOT)
scripts/flash.sh            fastboot boot / flash helpers
kernel/retro7-fragment.config
initramfs/init              initramfs /init (gadget console, switch_root)
rootfs-overlay/             system config planted into the Debian rootfs
launcher/                   Openbox config + game menu (source of truth)
docs/bringup.md             hardware facts + §1..§5 driver plans
docs/ports.md               cross-compiling re3/reVC & NFS reimpl
```

## Quickstart
0. Build PC (Debian/Ubuntu):
   `sudo apt install gcc-aarch64-linux-gnu mkbootimg debootstrap qemu-user-static
   busybox-static e2fsprogs fastboot xz-utils rsync`
   Build PC (Fedora, verified):
   `sudo dnf install -y gcc-aarch64-linux-gnu binutils-aarch64-linux-gnu make
   flex bison bc perl elfutils-libelf-devel openssl-devel cpio xz tar rsync git`
   + mkbootimg via tiny AOSP clone + wrapper (single-file/pypi routes dead —
   details: docs/bringup.md §0).
1. Phone: flash lk2nd once (docs/bringup.md §1).
2. `chmod +x scripts/*.sh launcher/games-menu.sh initramfs/init
   rootfs-overlay/usr/local/sbin/usb-gadget.sh` (one-time)
3. `scripts/build-kernel.sh` → `scripts/make-initramfs.sh` → `scripts/flash.sh boot`
   (volatile RAM-boot test — Android untouched).
3. Happy? `scripts/make-rootfs.sh` → `scripts/flash.sh rootfs` → permanent.
4. Every step after: boot, grab dmesg over the USB console, we iterate together.

> NOTE: kernel branch, config symbols and DTS details get pinned during the first
> build/boot loop — the fork moves; scripts state their assumptions loudly (`TODO`).
>
> This unit verified at M0: 8 GB model → userdata rootfs budget ≈ 4.7 GB
> (see make-rootfs.sh / bringup.md). Display panel = S6D7AA0X62 (fork-supported).
