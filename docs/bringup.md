# Hardware bring-up bible — Galaxy On7 (`samsung-o7`)

Facts from postmarketOS wiki (Samsung_Galaxy_On7_(2015)_(samsung-on7)) and fork
sources. SM-G600FY = "o7lte-swa" SKU (shares platform with On7 Pro — variant
compat unverified; this project is the verification).

## §0 Build PC prerequisites
Your PC: **Fedora 44 (x86_64)** — and Fedora ships native cross toolchains,
so no tarball and no container needed:
```sh
# cross toolchain (aarch64 = the phone's ARMv8 64-bit; installs aarch64-linux-gnu-*)
sudo dnf install -y gcc-aarch64-linux-gnu binutils-aarch64-linux-gnu
# kernel host-side build deps
sudo dnf install -y make flex bison bc perl elfutils-libelf-devel openssl-devel \
     cpio xz tar rsync git
# mkbootimg (build script expects a `mkbootimg` command) — pypi pkg dead AND the
# AOSP single-file fetch broke (main-branch script imports gki/ from its repo).
# VERIFIED 2026-11-05: tiny clone + wrapper:
rm -rf ~/opt/mkbootimg
mkdir -p ~/opt
git clone --depth 1 https://android.googlesource.com/platform/system/tools/mkbootimg ~/opt/mkbootimg
printf '#!/bin/sh\nexec python3 %s/mkbootimg.py "$@"\n' "$HOME/opt/mkbootimg" > ~/.local/bin/mkbootimg
chmod +x ~/.local/bin/mkbootimg
mkbootimg --help   # sanity check (prints usage incl. --dtb)
```
The default `CROSS_COMPILE=aarch64-linux-gnu-` in build-kernel.sh matches these
packages exactly — no PATH/export juggling needed.

Fallbacks (only if something breaks):
- Arm GNU Toolchain tarball (developer.arm.com, `aarch64-none-linux-gnu`) +
  `export CROSS_COMPILE=aarch64-none-linux-gnu-`
- LLVM flavor (github.com/arm/arm-toolchain — RHEL/Ubuntu repo packages only,
  no Fedora repo, no GH assets): `LLVM=1 ./scripts/build-kernel.sh` is supported.
- gcc 16.2 is very new; if the kernel build trips over brand-new-compiler
  warnings-as-errors, report the log — worst case we pin the tarball toolchain.
- **M2 note:** `make-rootfs.sh` needs debootstrap + arm64 qemu binfmt + static
  busybox — awkward natively on Fedora. When M1 boots, run just that script
  inside a `distrobox create --image debian:trixie` box (`dnf install distrobox podman`).
  Everything else stays native.
### M1 STATUS: **DONE 2026-11-05** — custom kernel RAM-boots, rescue shell via USB serial
Verified on this unit: `fastboot boot out/boot.img` → banner + shell on `/dev/ttyACM0`,
eMMC enumerated (27 parts), gadget up at ~1.6 s. Gotchas that cost us (do not forget):
- boot.img = `Image.gz` **+ DTB appended** (`cat Image.gz $DTB > Image.gz-dtb`) —
  lk2nd requires the append_dtb convention; a `--dtb` section gives "dtb not found".
- cmdline `rw panic=10`: init crash ⇒ auto-reboot after 10 s (visible diagnostic).
- initramfs busybox must be **ARM64 static** — busybox.net publishes no aarch64
  build; extract Alpine's `busybox-static` apk (it's a gzipped tar).
- `merge_config.sh` writes to `./.config` in the CWD unless given `-O $OUT` —
  without it the fragment is silently ignored.
- gadget functions are `CONFIG_USB_CONFIGFS_ACM` / `_NCM` — **no F_ prefix**
  (F_* is only for newer functions). kconfig silently drops typos.

## §1 lk2nd (once — from the rooted phone, DONE on this unit 2026-11-04)
lk2nd is a tiny Android-boot-image **shim**: the stock Samsung bootloader
still does the booting, it just finds lk2nd in `BOOT` instead of the Android
kernel. Thereafter the real OS gets chainloaded from a **512 KiB offset**
inside the same partition (that's how lk2nd keeps itself safe when you
`fastboot flash boot` — the offset writes never overwrite lk2nd).
```sh
# PC side
adb push lk2nd-msm8916.img /sdcard/lk2nd-msm8916.img   # file from https://github.com/msm8916-mainline/lk2nd/releases
adb shell        # then:
su
# 0) locate the boot partition (verified on this unit: Samsung msm8916 uses
#    LOWERCASE names; boot -> /dev/block/mmcblk0p16)
ls -l /dev/block/bootdevice/by-name/
# 1) BACKUP the current boot image (your rooted Android kernel lives here!)
dd if=/dev/block/bootdevice/by-name/boot of=/sdcard/stock_boot.img
sync
exit && exit
adb pull /sdcard/stock_boot.img .          # keep OFF the phone, e.g. in ~/backup
# 2) flash lk2nd (back into android: adb shell; su)
dd if=/sdcard/lk2nd-msm8916.img of=/dev/block/bootdevice/by-name/boot
sync && reboot
```
Partition-map note (observed on this unit):
```
aboot    p5  = Samsung LK secondary bootloader  → DO NOT WRITE lk2nd here
boot     p16 = Android kernel slot (12 MiB)     → lk2nd target
recovery p17 = recovery slot (unchanged)
userdata p27 = our future Debian rootfs target (M2)
```

### Hardware facts confirmed by the lk2nd log (M0)
- lk2nd detects the device as `samsung,on7lte-swa` (SM-G600FY) — the exact SKU.
- Panel: **S6D7AA0X62_BV050HDM HD** (`lcd_id=0x59b810`) — covered by the fork DTS.
- eMMC: SK Hynix **8 GB** model (7.3 GiB):
  - `userdata` = **4759 MiB** → rootfs.img must fit ≤ ~4.6 G (see make-rootfs.sh)
  - reclaimable later (Android gone by M2): `cache` 200 MiB, `system` 2304 MiB —
    extra game-storage space; treat as optional (§9 note)
  - microSD works mainline in the port — game data can live on a card too.
- **After this flash, normal boots land in lk2nd, not Android** — the Android
  kernel left the slot. Both are alive, though:
  - `fastboot flash boot stock_boot.img` (from lk2nd fastboot) re-stages
    stock Android at the 512 KiB offset → default boot becomes Android again,
    Vol-Down still opens lk2nd fastboot. Nice sanity check the chain works.
  - our kernel goes the same way later (M1 RAM-boot DONE → M2: flash).
- lk2nd **fastboot**: hold **Vol-Down** while booting (per lk2nd README; wait
  until the screen lights/vibrates first so stock keys aren't intercepted).
- lk2nd *recovery-target* boot: Vol-Up while booting.
- Samsung **Download Mode** (boot-ROM rescue, for Odin): **Power + Vol-Up + Home**
  (per the pmOS On7 page — this device uses Vol-**Up**, unlike newer Samsungs).
- Full revert at any time: `dd if=stock_boot.img of=/dev/block/bootdevice/by-name/boot`, or whole
  phone via Odin with the Frija `.tar.md5`.
- You can also update lk2nd later without re-flashing boot: from lk2nd
  fastboot, `fastboot flash lk2nd lk2nd-msm8916.img`.

## §2 Touchscreen — Zinitix ZT7548 (must-do for the launcher UX)
Known wiring (wiki/driver notes):
```
irq-gpio 13, scl-gpio 19, sda-gpio 18
i2c bus: i2c@78b9000 (blsp_i2c5), tsp addr 0x14 (decimal 20)
```
Plan:
1. Locate zinitix driver: fork may carry an out-of-tree variant by Mis012
   (`drivers/input/touchscreen/zinitix*`); else port it into the fork tree.
2. DTS: `touchscreen@14` node on `&blsp_i2c5`, compatible matching that driver
   (zt7548 vs bt-series), `interrupt-parent/pinctrl` for irq 13, `irq-gpio`.
3. evtest + dmesg loop; add `mount-matrix` if orientation is flipped.

## §3 Audio (untested on o7)
SoC audio (PM8916 wcd + qcom DSP/Apr) drivers are mainline and working on
sibling msm8916 phones; o7 needs analog routing + UCM. Steps:
1. Enable `CONFIG_SND_*` msm symbols in fragment (look up exact names in fork).
2. Add/verify `sound` node in `msm8916-samsung-o7.dts`.
3. `aplay -l`, then write a small UCM2 for speaker/headset/mic.

## §4 USB host mode (wired gamepad) — SM5703 MUIC via sm5502 extcon
Current: device-mode + charger detect OK; host path absent (hence pmOS "OTG: partial").
Precedent: sibling Samsung msm8916 A3/A5 2015 ports have host mode working in
the same fork — diff their DTS/MUIC usage against ours and adapt.
1. `drivers/extcon/extcon-sm5502.c` — teach MUIC the host/accessory route.
2. dwc3 node: `usb-role-switch`, `dr_mode = "otg"`, `otg-supply` (VBUS 5V boost
   from PM8916 `-otg` regulator path — verify PMIC wiring in fork DT).
3. Test: OTG adapter + wired pad → `jstest`/`evtest`.
   Fallback if hardware can't route host VBUS: sysfs force role-switch; else BT pad.

## §5 Battery/charging — Siliconmitus SM5703
One PMIC does fuel-gauge + charger + vibrator + (muic as above). I²C pins:
scl 106 / sda 105 / irq 12 / uart 114 (per wiki).
Roadmap: minimal driver for status (charge %, plugged/unplugged). Vibrator can
ride the same bus later (tiny driver, fun).

## §6 Firmware files (WiFi/BT — WCN3620)
Drivers (`wcn36xx` for WLAN, `hci_uart` + `hciattach`/`btsnoop`-free serial BT
attach for BT) need WLAN/BT firmware
blobs shipped by pmOS (`firmware-qcom-msm8916` family packages). At M2, pull
those pmOS firmware packages (aarch64 .apk) and unpack into `/lib/firmware/`
before first WLAN bring-up. Do NOT ship these in-repo; fetch step lives in
scripts/make-rootfs.sh (TODO at M2).

## §7 Debug workflow
- **Fedora USB perms (one-time):** fastboot *sending* needs raw USB write access
  — without it you get "Write to device failed (Permission denied)".
  Fix: `/etc/udev/rules.d/71-fastboot.rules` →
  `SUBSYSTEM=="usb", ATTRS{idVendor}=="18d1", ATTRS{idProduct}=="d00d", MODE="0660", TAG+="uaccess", ENV{ID_MM_DEVICE_IGNORE}="1"`
  then `sudo udevadm control --reload-rules` + replug. Also:
  `sudo usermod -aG dialout $USER` (for /dev/ttyACM* rescue console) and
  `sudo systemctl disable --now ModemManager` (it hijacks serial-ish USB devices).
- Phone side normal boot: usb-gadget.service → `usb0` = 10.15.0.2/30.
- PC side manual add of the host end (or a small rc-local):
  ```
  ip link set usbX up; ip addr add 10.15.0.1/30 dev usbX
  ssh retro@10.15.0.2     (pw: retro)
  ```
- Kernel hang = screen freeze: dmesg still reachable over USB; keep a second
  log channel over /dev/ttyGS0 (the initramfs shell already does this).

## §8 Brick-safety recap
Samsung boot ROM + Download Mode = Odin forever. Our writes: `BOOT` (lk2nd +
kernel) and `userdata` (rootfs). Both dd-restorable / Odin-restorable.
