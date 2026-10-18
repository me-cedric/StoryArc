#!/usr/bin/env bash
# Build and test StoryArc inside a distro container, with that distro's own packages.
# Usage: container-build.sh <ubuntu-24.04|arch|manjaro|fedora> [--clippy]
# --clippy also runs cargo clippy on storyarc-linux with warnings denied.
# The arch and manjaro rows also build the AUR package from the working tree with makepkg and
# install it (task 6.6): the tree is packed as the release tarball the PKGBUILD names.
# The repository mounts read-only. The target and cargo caches live in named docker volumes.
# CARGO_BUILD_JOBS defaults to 3: an 8 GB Docker VM runs out of memory when the linker runs
# ten test binaries at once (ld terminated with signal 9).
set -euo pipefail

distro="${1:-}"
clippy="${2:-}"
root="$(cd "$(dirname "${BASH_SOURCE[0]}")/../../.." && pwd)"

case "$distro" in
  ubuntu-24.04)
    image="ubuntu:24.04"; platform=""
    setup='export DEBIAN_FRONTEND=noninteractive
      apt-get update -qq
      apt-get install -y -qq build-essential pkg-config curl ca-certificates libgtk-4-dev libadwaita-1-dev libwebkitgtk-6.0-dev libgstreamer1.0-dev libgstreamer-plugins-base1.0-dev libgstreamer-plugins-bad1.0-dev gstreamer1.0-plugins-good gstreamer1.0-libav appstream desktop-file-utils
      curl -sSf https://sh.rustup.rs | sh -s -- -y --profile minimal >/dev/null
      . /root/.cargo/env
      pkg-config --modversion gtk4 libadwaita-1 webkitgtk-6.0 gstreamer-play-1.0' ;;
  arch)
    image="archlinux:latest"; platform="linux/amd64"
    # Emulated amd64 on Apple silicon lacks the syscalls pacman 7 sandbox needs.
    setup='pacman --disable-sandbox -Syu --noconfirm --needed base-devel gtk4 libadwaita webkitgtk-6.0 gstreamer gst-plugins-base-libs gst-plugins-bad-libs gst-plugins-good gst-libav rust appstream desktop-file-utils >/dev/null
      pkg-config --modversion gtk4 libadwaita-1 webkitgtk-6.0 gstreamer-play-1.0' ;;
  manjaro)
    image="manjarolinux/base"; platform="linux/amd64"
    setup='pacman -Syu --noconfirm --needed base-devel gtk4 libadwaita webkitgtk-6.0 gstreamer gst-plugins-base-libs gst-plugins-bad-libs gst-plugins-good gst-libav rust appstream desktop-file-utils >/dev/null
      pkg-config --modversion gtk4 libadwaita-1 webkitgtk-6.0 gstreamer-play-1.0' ;;
  fedora)
    image="fedora:latest"; platform=""
    setup='dnf install -y -q gcc gcc-c++ make pkgconf-pkg-config gtk4-devel libadwaita-devel webkitgtk6.0-devel gstreamer1-devel gstreamer1-plugins-base-devel gstreamer1-plugins-bad-free-devel gstreamer1-plugins-good cargo rust appstream desktop-file-utils >/dev/null
      pkg-config --modversion gtk4 libadwaita-1 webkitgtk-6.0 gstreamer-play-1.0' ;;
  *) echo "usage: $0 <ubuntu-24.04|arch|manjaro|fedora> [--clippy]" >&2; exit 2 ;;
esac

lint=""
if [ "$clippy" = "--clippy" ]; then
  lint='command -v rustup >/dev/null && rustup component add clippy
  cargo clippy --locked -p storyarc-linux --all-targets -- -D warnings'
elif [ -n "$clippy" ]; then
  echo "unknown option: $clippy" >&2; exit 2
fi

# The pinned PDFium for the container's architecture, the way `pnpm pdfium:fetch` puts it on a
# host: downloaded once into the target volume, digest checked against pin.json before it is
# unpacked, so the PDF tests of the core and the app run instead of skipping (task 4.11).
pdfium='case "$(uname -m)" in x86_64) p=linux-x64 ;; aarch64) p=linux-arm64 ;; *) p= ;; esac
  if [ -n "$p" ]; then
    asset="pdfium-$p.tgz"
    pin=apps/desktop-core/pdfium/pin.json
    want=$(grep -o "\"$asset\": \"[0-9a-f]*\"" "$pin" | cut -d\" -f4)
    tag=$(grep -o "\"tag\": \"[^\"]*\"" "$pin" | cut -d\" -f4)
    if [ ! -f /target/pdfium/lib/libpdfium.so ] || [ "$(cat /target/pdfium/digest 2>/dev/null)" != "$want" ]; then
      rm -rf /target/pdfium && mkdir -p /target/pdfium
      curl -sSfL --max-time 180 -o "/target/pdfium/$asset" "https://github.com/bblanchon/pdfium-binaries/releases/download/${tag/\//%2F}/$asset"
      echo "$want  /target/pdfium/$asset" | sha256sum -c -
      tar -xzf "/target/pdfium/$asset" -C /target/pdfium && rm "/target/pdfium/$asset" && echo "$want" > /target/pdfium/digest
    fi
    export STORYARC_PDFIUM_DIR=/target/pdfium/lib
  fi'

# The AUR package (arch and manjaro): the working tree packed as the tag tarball the PKGBUILD
# fetches, built by makepkg as an unprivileged user with the cargo cache on the target volume,
# then installed with pacman and checked for the pieces it must leave.
aur=""
case "$distro" in arch|manjaro) aur='ver=$(sed -n "s/^version = \"\(.*\)\"/\1/p" Cargo.toml | head -1)
  id builder >/dev/null 2>&1 || useradd -m builder
  work=$(mktemp -d /tmp/aur.XXXXXX); mkdir -p /target/aur-cargo /target/aur-target
  cp apps/desktop-linux/packaging/aur/PKGBUILD "$work/"
  tar -czf "$work/storyarc-$ver.tar.gz" --exclude=./.git --exclude=./node_modules --exclude=./.build --exclude=./.claude --transform "s,^\./,StoryArc-$ver/," -C /src .
  chown -R builder "$work" /target/aur-cargo /target/aur-target
  su builder -c "cd $work && CARGO_HOME=/target/aur-cargo CARGO_TARGET_DIR=/target/aur-target CARGO_BUILD_JOBS=${CARGO_BUILD_JOBS:-3} makepkg --skipchecksums --noconfirm && makepkg --printsrcinfo > .SRCINFO"
  pacman -U --noconfirm "$work"/storyarc-*.pkg.tar.zst
  test -x /usr/lib/storyarc/storyarc && test -f /usr/lib/storyarc/libpdfium.so && test -L /usr/bin/storyarc
  test -x /usr/bin/storyarc-thumbnailer && test -f /usr/share/thumbnailers/com.mecedric.StoryArc.thumbnailer
  desktop-file-validate /usr/share/applications/com.mecedric.StoryArc.desktop
  /usr/bin/storyarc-thumbnailer -s 64 packages/test-fixtures/comics/single-page.cbz "$work/cover.png" && test -s "$work/cover.png"
  echo "AUR package installed: $(pacman -Q storyarc)"; echo "--- .SRCINFO"; cat "$work/.SRCINFO"' ;; esac

# The same two commands as pnpm test:desktop:core and pnpm build:linux, plus the data file checks.
run="set -e
  cargo --version
  $pdfium
  cargo test --locked -p storyarc-core -p storyarc-ffi
  cargo build --locked -p storyarc-linux
  cargo test --locked -p storyarc-linux
  $lint
  desktop-file-validate apps/desktop-linux/data/com.mecedric.StoryArc.desktop
  appstreamcli validate --no-net apps/desktop-linux/data/com.mecedric.StoryArc.metainfo.xml
  $aur"

# storyarc-ffi's build.rs regenerates generated/NativeMethods.g.cs into the source tree on every
# build. A tmpfs over that one directory takes the write, so the repository mount stays read-only.
docker run --rm ${platform:+--platform "$platform"} \
  -v "$root":/src:ro -w /src \
  --tmpfs /src/apps/desktop-core/storyarc-ffi/generated \
  -v "storyarc-target-$distro":/target \
  -v "storyarc-cargo-$distro":/root/.cargo \
  -e CARGO_TARGET_DIR=/target \
  -e CARGO_BUILD_JOBS="${CARGO_BUILD_JOBS:-3}" \
  "$image" bash -c "set -e; $setup; $run"
