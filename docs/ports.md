# Cross-compiling games for aarch64

Rule zero: never compile re3-class games on the phone (A53 @ 1.2 GHz = hours).
Cross-compile on the PC, push over the USB interface.

## Toolchain flags
```sh
export CC=aarch64-linux-gnu-gcc
export CXX=aarch64-linux-gnu-g++
export CFLAGS="-march=armv8-a -O2"     # A53-friendly, NEON implied
export CXXFLAGS="$CFLAGS"
```
Sysroot pattern for cmake projects:
```sh
# tiny arm64 sysroot with the exact lib versions Debian ships:
sudo debootstrap --arch=arm64 --variant=minbase trixie /out/sysroot http://deb.debian.org/debian
# install build-inside deps INTO that sysroot (qemu binfmt):
sudo mount --bind /proc /out/sysroot/proc && sudo chroot /out/sysroot apt-get build-deps? better: apt-get install libgl-dev libgles-dev libopenal-dev cmake ...
# then: cmake -DCMAKE_FIND_ROOT_PATH=/out/sysroot -DCMAKE_SYSTEM_NAME=Linux ...
```

## re3 / reVC (reverse-engineered GTA III / Vice City)
- Upstream repos (github GTAmodding) got Take-Two DMCA'd at various points —
  maintained mirrors exist on GitLab/Codeberg/mirrors; pick a fresh one at build time.
- Data: retail CD `.IMG/.SND` files from your own copy — no pirated data.
- Audio: consumes OpenAL/ALSA; works once bring-up §3 lands.
- Perf on Adreno 306: ~30 fps at native 720p with modest scaling; drop internal
  resolution to 0.5x if it chokes. Original mobile GTA ran on weaker hardware,
  so the port should be fine here.

## Old NFS reimplementations
- NFS II SE reimplementation and related classic-NFS reconstruction
  ports are lighter than re3 — ideal first build to validate the whole chain.
- Repo names rotate as takedowns happen; grab the current maintained mirror
  when we start that milestone.

## RetroArch (no cross-compile needed)
Lives in the distro: inside the rootfs run
`sudo apt install retroarch` — uses freedreno GL 3.1 (proven on msm8916).
Core set: keep small (psx ReARMed, snes, genesis, gba).

## Pushing builds to the phone
USB gadget exposes `usb0` on the phone side at 10.15.0.2 (see rootfs-overlay
network file). Host side gets 10.15.0.1 manually or via rc-local config —
then plain scp/rsync:
```sh
rsync -avh --progress games/ retro@10.15.0.2:/home/retro/games/
```
