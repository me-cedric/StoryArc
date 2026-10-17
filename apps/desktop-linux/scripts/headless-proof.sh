#!/usr/bin/env bash
# Run the Linux tests that need a display, a session bus or a sound device inside the Ubuntu 24.04
# container, under cage (a headless wlroots compositor), on the same volumes as container-build.sh.
# Usage: headless-proof.sh [test-name-filter]      (default: every such test; they skip without a display)
#        headless-proof.sh --walk <output-dir> [walk]  a walk script of this folder (default wave4-walk.sh),
#                                                   captures into <output-dir>
# WebKitGTK's web process sandbox needs user namespaces the container does not have, so the
# sandbox is switched off here, and only here; the app never does that.
set -euo pipefail
filter="${1:-}"
root="$(cd "$(dirname "${BASH_SOURCE[0]}")/../../.." && pwd)"
walk=""
script="${3:-wave4-walk.sh}"
if [ "$filter" = "--walk" ]; then
  out="${2:?an output directory}"; mkdir -p "$out"; out="$(cd "$out" && pwd)"
  walk="-v $out:/out"; filter=""
fi

docker run --rm \
  -v "$root":/src:ro -w /src \
  --tmpfs /src/apps/desktop-core/storyarc-ffi/generated \
  -v storyarc-target-ubuntu-24.04:/target \
  -v storyarc-cargo-ubuntu-24.04:/root/.cargo \
  -e CARGO_TARGET_DIR=/target \
  -e CARGO_BUILD_JOBS="${CARGO_BUILD_JOBS:-3}" \
  -e STORYARC_PDFIUM_DIR=/target/pdfium/lib \
  $walk \
  ubuntu:24.04 bash -c "
set -e
export DEBIAN_FRONTEND=noninteractive
apt-get update -qq
apt-get install -y -qq build-essential pkg-config curl ca-certificates libgtk-4-dev libadwaita-1-dev libwebkitgtk-6.0-dev \
  libgstreamer1.0-dev libgstreamer-plugins-base1.0-dev libgstreamer-plugins-bad1.0-dev gstreamer1.0-plugins-good gstreamer1.0-libav \
  speech-dispatcher speech-dispatcher-espeak-ng speech-dispatcher-audio-plugins libao4 playerctl at-spi2-core python3-pyatspi dbus-x11 \
  cage grim wtype dbus gdb fonts-dejavu-core adwaita-icon-theme >/dev/null
# The cargo volume keeps the proxies and the registry; the toolchain lives outside it, so rustup runs each time.
curl -sSf https://sh.rustup.rs | sh -s -- -y --profile minimal >/dev/null
. /root/.cargo/env
pkg-config --modversion gtk4 libadwaita-1 webkitgtk-6.0 gstreamer-play-1.0
export XDG_RUNTIME_DIR=/tmp/xdg; mkdir -p -m 700 \$XDG_RUNTIME_DIR
export WLR_BACKENDS=headless WLR_RENDERER=pixman WLR_LIBINPUT_NO_DEVICES=1
export GSK_RENDERER=cairo GDK_BACKEND=wayland
export WEBKIT_DISABLE_SANDBOX_THIS_IS_DANGEROUS=1 WEBKIT_DISABLE_COMPOSITING_MODE=1 WEBKIT_DISABLE_DMABUF_RENDERER=1
# The app writes under HOME; rustup and cargo keep theirs where the install put them.
export RUSTUP_HOME=/root/.rustup CARGO_HOME=/root/.cargo
export HOME=/tmp/home; mkdir -p \$HOME
# speech-dispatcher with no sound device: libao's null driver, so a sentence can reach its END.
mkdir -p \$HOME/.config/speech-dispatcher
printf 'AudioOutputMethod \"libao\"\nLogLevel 3\n' > \$HOME/.config/speech-dispatcher/speechd.conf
printf 'default_driver=null\n' > \$HOME/.libao
if [ -n '$walk' ]; then
  cargo build --locked -p storyarc-linux
  exec bash /src/apps/desktop-linux/scripts/$script
fi
cargo test --locked -p storyarc-linux --no-run
eval \$(dbus-launch --sh-syntax); export DBUS_SESSION_BUS_ADDRESS
# A test that hangs on a bus it cannot bring down must not hold the container: fifteen minutes.
timeout 900 cage -- cargo test --locked -p storyarc-linux -- $filter --nocapture --test-threads=1
"
