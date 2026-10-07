#!/usr/bin/env bash
# Launch the Linux app under a headless wlroots compositor (cage) in an Arch container and capture it
# with grim, in the light and the dark style. This proves the app starts on Wayland with no X11 fallback.
# Usage: wayland-capture.sh [output-dir]   (default: docs/designs/screenshots/desktop-linux-base-2026-10-07)
# Output: <output-dir>/base-light.png and base-dark.png
set -euo pipefail
root="$(cd "$(dirname "${BASH_SOURCE[0]}")/../../.." && pwd)"
out="${1:-$root/docs/designs/screenshots/desktop-linux-base-2026-10-07}"
mkdir -p "$out"
out="$(cd "$out" && pwd)"

docker run --rm --platform linux/amd64 \
  -v "$root":/src:ro -w /src \
  -v storyarc-target-arch:/target \
  -v storyarc-cargo-arch:/root/.cargo \
  -v "$out":/out \
  -e CARGO_TARGET_DIR=/target \
  archlinux:latest bash -c '
set -e
pacman --disable-sandbox -Syu --noconfirm --needed base-devel gtk4 libadwaita libarchive rust cage grim ttf-dejavu cantarell-fonts adwaita-icon-theme >/dev/null
cargo build --locked -p storyarc-linux
export XDG_RUNTIME_DIR=/tmp/xdg; mkdir -p -m 700 $XDG_RUNTIME_DIR
export WLR_BACKENDS=headless WLR_RENDERER=pixman WLR_LIBINPUT_NO_DEVICES=1
export GSK_RENDERER=cairo GDK_BACKEND=wayland
shot() {
  scheme=$1; name=$2
  ADW_DEBUG_COLOR_SCHEME=$scheme cage -- /target/debug/storyarc >/tmp/cage-$name.log 2>&1 &
  pid=$!
  for i in $(seq 1 40); do sock=$(ls $XDG_RUNTIME_DIR | grep -m1 "^wayland-[0-9]*$" || true); [ -n "$sock" ] && break; sleep 0.5; done
  sleep 6
  WAYLAND_DISPLAY=$sock grim /out/base-$name.png
  kill $pid; wait $pid 2>/dev/null || true
  rm -f $XDG_RUNTIME_DIR/wayland-*
}
shot default light
shot prefer-dark dark
pkg-config --modversion gtk4 libadwaita-1
'
ls -la "$out"
