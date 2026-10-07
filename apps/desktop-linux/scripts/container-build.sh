#!/usr/bin/env bash
# Build and test StoryArc inside a distro container, with that distro's own packages.
# Usage: container-build.sh <ubuntu-24.04|arch|manjaro|fedora> [--clippy]
# --clippy also runs cargo clippy on storyarc-linux with warnings denied.
# The repository mounts read-only. The target and cargo caches live in named docker volumes.
set -euo pipefail

distro="${1:-}"
clippy="${2:-}"
root="$(cd "$(dirname "${BASH_SOURCE[0]}")/../../.." && pwd)"

case "$distro" in
  ubuntu-24.04)
    image="ubuntu:24.04"; platform=""
    setup='export DEBIAN_FRONTEND=noninteractive
      apt-get update -qq
      apt-get install -y -qq build-essential pkg-config curl ca-certificates libgtk-4-dev libadwaita-1-dev libarchive-dev appstream desktop-file-utils
      curl -sSf https://sh.rustup.rs | sh -s -- -y --profile minimal >/dev/null
      . /root/.cargo/env
      pkg-config --modversion gtk4 libadwaita-1' ;;
  arch)
    image="archlinux:latest"; platform="linux/amd64"
    # Emulated amd64 on Apple silicon lacks the syscalls pacman 7 sandbox needs.
    setup='pacman --disable-sandbox -Syu --noconfirm --needed base-devel gtk4 libadwaita libarchive rust appstream desktop-file-utils >/dev/null
      pkg-config --modversion gtk4 libadwaita-1' ;;
  manjaro)
    image="manjarolinux/base"; platform="linux/amd64"
    setup='pacman -Syu --noconfirm --needed base-devel gtk4 libadwaita libarchive rust appstream desktop-file-utils >/dev/null
      pkg-config --modversion gtk4 libadwaita-1' ;;
  fedora)
    image="fedora:latest"; platform=""
    setup='dnf install -y -q gcc gcc-c++ make pkgconf-pkg-config gtk4-devel libadwaita-devel libarchive-devel cargo rust appstream desktop-file-utils >/dev/null
      pkg-config --modversion gtk4 libadwaita-1' ;;
  *) echo "usage: $0 <ubuntu-24.04|arch|manjaro|fedora> [--clippy]" >&2; exit 2 ;;
esac

lint=""
if [ "$clippy" = "--clippy" ]; then
  lint='command -v rustup >/dev/null && rustup component add clippy
  cargo clippy --locked -p storyarc-linux --all-targets -- -D warnings'
elif [ -n "$clippy" ]; then
  echo "unknown option: $clippy" >&2; exit 2
fi

# The same two commands as pnpm test:desktop:core and pnpm build:linux, plus the data file checks.
run="set -e
  cargo --version
  cargo test --locked -p storyarc-core -p storyarc-ffi
  cargo build --locked -p storyarc-linux
  $lint
  desktop-file-validate apps/desktop-linux/data/com.mecedric.StoryArc.desktop
  appstreamcli validate --no-net apps/desktop-linux/data/com.mecedric.StoryArc.metainfo.xml"

docker run --rm ${platform:+--platform "$platform"} \
  -v "$root":/src:ro -w /src \
  -v "storyarc-target-$distro":/target \
  -v "storyarc-cargo-$distro":/root/.cargo \
  -e CARGO_TARGET_DIR=/target \
  "$image" bash -c "set -e; $setup; $run"
