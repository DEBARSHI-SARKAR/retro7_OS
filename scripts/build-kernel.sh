#!/usr/bin/env bash
# Build the msm8916-mainline kernel for Galaxy On7 (samsung-o7).
# Requires aarch64 cross toolchain + mkbootimg installed (docs/bringup.md §0).
set -euo pipefail
cd "$(dirname "$0")/.."
ROOT="$PWD"
KDIR="${KDIR:-$ROOT/linux}"
OUT="$KDIR/out"
FRAG="$ROOT/kernel/retro7-fragment.config"
FORK="${FORK:-https://github.com/msm8916-mainline/linux}"
BRANCH="${BRANCH:-}"   # e.g. pmos-6.6; pick the newest release branch of the fork

if [ ! -d "$KDIR" ]; then
  echo "==> cloning $FORK"
  if [ -n "$BRANCH" ]; then
    git clone --depth 1 -b "$BRANCH" "$FORK" "$KDIR"
  else
    git clone "$FORK" "$KDIR"
  fi
elif [ -n "$BRANCH" ]; then
  git -C "$KDIR" fetch --depth 1 origin "$BRANCH" || true
  git -C "$KDIR" checkout "$BRANCH" 2>/dev/null || git -C "$KDIR" checkout FETCH_HEAD
fi

export ARCH=arm64
# B1 (containerless, GNU tarball): export CROSS_COMPILE=aarch64-none-linux-gnu-
# LLVM flavor (Arm Toolchain for Linux): export LLVM=1  (and no CROSS_COMPILE)
# Default: Debian/Ubuntu-style prefix (works via distrobox or name shims).
if [ -n "${LLVM:-}" ]; then
  export CROSS_COMPILE=""
else
  export CROSS_COMPILE="${CROSS_COMPILE:-aarch64-linux-gnu-}"
fi
echo "==> defconfig + retro7 fragment"
# NOTE: this fork ships msm8916_defconfig (no qcom_defconfig) — verified on msm8916/6.12.1
DEFCONFIG="${DEFCONFIG:-msm8916_defconfig}"
make -C "$KDIR" O="$OUT" ${LLVM:+LLVM=1} "$DEFCONFIG"
# merge_config.sh writes its result to ./.config in the CURRENT directory by
# default — pass -O so the merged config actually lands in linux/out/.config
"$KDIR/scripts/kconfig/merge_config.sh" -m -O "$OUT" "$OUT/.config" "$FRAG"
make -C "$KDIR" O="$OUT" ${LLVM:+LLVM=1} olddefconfig

echo "==> Image.gz + dtbs + modules"
# NOTE: 'modules' target matters — modules.order only exists after the modules pass
make -C "$KDIR" O="$OUT" -j"$(nproc)" ${LLVM:+LLVM=1} Image.gz dtbs modules
make -C "$KDIR" O="$OUT" ${LLVM:+LLVM=1} modules_install INSTALL_MOD_PATH="$OUT/modules" INSTALL_MOD_STRIP=1

DTB=$(find "$OUT/arch/arm64/boot/dts/qcom" -name 'msm8916-samsung-on7*.dtb' 2>/dev/null | head -1)
[ -n "$DTB" ] || { echo "ERROR: msm8916-samsung-on7 dtb not built — check branch/DTS (fork builds it on msm8916/6.12.1)" >&2; exit 1; }

echo "==> boot.img"
mkdir -p "$ROOT/out"
# lk2nd expects the DTB APPENDED to the kernel image (append_dtb convention),
# not in a separate --dtb section — hence Image.gz-dtb:
cat "$OUT/arch/arm64/boot/Image.gz" "$DTB" > "$OUT/Image.gz-dtb"
# Standard msm8916 boot-image params; if M1 fails to boot, cross-check against
# the pmaports recipe (linux-postmarketos-qcom-msm8916).
INITRAMFS=""
[ -f "$ROOT/out/initramfs.cpio.gz" ] && INITRAMFS="--ramdisk $ROOT/out/initramfs.cpio.gz"
mkbootimg \
  --kernel "$OUT/Image.gz-dtb" \
  --cmdline "rw panic=10" \
  --base 0x80000000 --kernel_offset 0x00080000 \
  --ramdisk_offset 0x01000000 --tags_offset 0x00000100 \
  --pagesize 2048 \
  $INITRAMFS \
  --output "$ROOT/out/boot.img"

echo "ready:"
echo "  out/boot.img"
echo "  out/modules/lib/modules/...   (picked up by scripts/make-rootfs.sh)"
