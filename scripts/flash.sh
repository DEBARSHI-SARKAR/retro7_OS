#!/usr/bin/env bash
# Flash helpers. Device MUST be in lk2nd fastboot mode: Vol-Down + Power (no Home).
set -euo pipefail
cd "$(dirname "$0")/.."
cmd="${1:-help}"
case "$cmd" in
  boot)
    # --- volatile RAM-boot test: kernel+initramfs boot without touching storage
    fastboot boot out/boot.img ;;
  flash-boot)
    # persistent: writes boot.img into BOOT (this is where lk2nd/kernel live)
    fastboot flash boot out/boot.img ;;
  rootfs)
    echo "This ERASES userdata — writes out/rootfs.img (Debian, label RETRO7ROOT)."
    printf 'type "yes" to continue: '; read -r a
    [ "$a" = "yes" ] || { echo "aborted."; exit 1; }
    fastboot erase userdata 2>/dev/null || true
    fastboot flash userdata out/rootfs.img ;;
  *)
    echo "usage: $0 boot|flash-boot|rootfs"
    echo "  boot         RAM-boot test (safe)"
    echo "  flash-boot   persist kernel/boot.img"
    echo "  rootfs       write Debian rootfs to userdata (destructive)"
    ;;
esac
