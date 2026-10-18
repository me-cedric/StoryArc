#!/usr/bin/env bash
# The wave 4 EPUB surfaces walk, run INSIDE the Ubuntu 24.04 container by
# `headless-proof.sh --walk <dir> wave4-epub-walk.sh`. Under cage with a session bus and an
# accessibility bus: opens the corpus EPUB, then the theme surface, the contents, a search with
# its hits, the way back after a hit, and the bookmarks and highlights, each captured with grim
# into the output folder and dumped as an accessibility tree. The surfaces open through
# `reader-action`, because a wtype Control chord is not delivered under cage.
set -euo pipefail
out=${WALK_OUT:-/out}
app=/target/debug/storyarc
fixtures=/src/packages/test-fixtures
mkdir -p "$out"
finish() {
  kill "${app_pid:-0}" 2>/dev/null || true
  grep -v '^$' /tmp/storyarc.log 2>/dev/null | grep -v "keysym\|xkbcomp\|keycode" | tail -300 > "$out/storyarc.log" || true
  echo "walk ended; app log in $out/storyarc.log"
}
trap finish EXIT

export XDG_RUNTIME_DIR=/tmp/xdg; mkdir -p -m 700 "$XDG_RUNTIME_DIR"
export WLR_BACKENDS=headless WLR_RENDERER=pixman WLR_LIBINPUT_NO_DEVICES=1
export GSK_RENDERER=cairo GDK_BACKEND=wayland
export WEBKIT_DISABLE_SANDBOX_THIS_IS_DANGEROUS=1 WEBKIT_DISABLE_COMPOSITING_MODE=1 WEBKIT_DISABLE_DMABUF_RENDERER=1
export STORYARC_AUDIO_NULL_SINK=1
# A fresh home each run, so the look and the marks start from their defaults.
HOME="$(mktemp -d /tmp/home-epub.XXXXXX)"; export HOME
export LANG=C.UTF-8
eval "$(dbus-launch --sh-syntax)"
export DBUS_SESSION_BUS_ADDRESS
export GTK_A11Y=atspi
/usr/libexec/at-spi-bus-launcher --launch-immediately >/tmp/at-spi.log 2>&1 &
sleep 1

RUST_BACKTRACE=1 G_MESSAGES_DEBUG=storyarc cage -- "$app" >/tmp/storyarc.log 2>&1 &
app_pid=$!
sock=""
for _ in $(seq 1 40); do
  sock=$(ls "$XDG_RUNTIME_DIR" | grep -m1 '^wayland-[0-9]*$' || true)
  [ -n "$sock" ] && break
  sleep 0.5
done
export WAYLAND_DISPLAY=$sock
sleep 6
wtype -k Tab; sleep 1

shot() { sleep "${2:-1}"; wtype -k Shift_L; sleep 0.5; grim "$out/$1.png"; echo "shot $1"; }
act() { gapplication action com.mecedric.StoryArc "$@" || echo "action $1 failed"; }
tree() { python3 /src/apps/desktop-linux/scripts/a11y-tree.py > "$out/a11y-$1.txt" 2>&1 || true; echo "tree $1: $(wc -l < "$out/a11y-$1.txt") lines"; }
reader() { act reader-action "'$1'"; }

act open-reader "'$fixtures/ebooks/fixture.epub'"; sleep 8
shot epub-paper 2
tree epub-paper

reader theme; shot epub-theme 2
tree epub-theme
wtype -k Escape; sleep 1

reader contents; shot epub-contents 2
tree epub-contents
wtype -k Escape; sleep 1

reader find; sleep 1; wtype "paragraph 3"; wtype -k Return; shot epub-search 3
tree epub-search
wtype -k Escape; sleep 1

reader bookmark; sleep 1
reader marks; shot epub-marks 2
tree epub-marks
wtype -k Escape; sleep 1

# The second chapter from the contents, then the way back it leaves.
reader contents; sleep 1; wtype -k Down; wtype -k Down; wtype -k Return; shot epub-jump 3
tree epub-jump
reader back; shot epub-back 3
wtype -M ctrl -k w -m ctrl; sleep 2

# A fixed-layout book, as the renderer lays it out.
act open-reader "'$fixtures/ebooks/fixed-layout.epub'"; sleep 8
shot epub-fixed 2

echo "walk done"
