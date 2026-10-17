#!/usr/bin/env bash
# The wave 4 headless walk, run INSIDE the Ubuntu 24.04 container by headless-proof.sh --walk.
# Under cage (headless wlroots) with a session bus, an accessibility bus and no sound device:
# opens the EPUB, the PDF and an audiobook of the corpus from the library, drives them with
# wtype, captures each screen with grim into /out, reads the player through playerctl, and
# dumps the accessibility tree of each screen with pyatspi (tasks 4.14 and 4.15).
set -euo pipefail
out=/out
app=/target/debug/storyarc
fixtures=/src/packages/test-fixtures
mkdir -p "$out"
# Whatever happens, the app's log and the state of its process reach the output folder.
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
export STORYARC_PDFIUM_DIR=/target/pdfium/lib
export HOME=/tmp/home; mkdir -p "$HOME"
export LANG=C.UTF-8

# The session bus every piece talks on, and the accessibility bus Orca would use.
eval "$(dbus-launch --sh-syntax)"
export DBUS_SESSION_BUS_ADDRESS
export GTK_A11Y=atspi
/usr/libexec/at-spi-bus-launcher --launch-immediately >/tmp/at-spi.log 2>&1 &
sleep 1

# One folder library: the corpus comics (the ebooks and audiobooks open by path).
data="$HOME/.local/share/com.mecedric.StoryArc"; mkdir -p "$data"
printf 'path\t%s\n' "$fixtures/comics" > "$data/sources"

sock=""
start_app() {
  RUST_BACKTRACE=1 G_MESSAGES_DEBUG=storyarc cage -- "$app" >/tmp/storyarc.log 2>&1 &
  app_pid=$!
  for _ in $(seq 1 40); do
    sock=$(ls "$XDG_RUNTIME_DIR" | grep -m1 '^wayland-[0-9]*$' || true)
    [ -n "$sock" ] && break
    sleep 0.5
  done
  export WAYLAND_DISPLAY=$sock
  sleep 6
  # A first key wakes the frame clock under cage; the walks of waves 2 and 3 did the same.
  wtype -k Tab; sleep 1
}
shot() { sleep "${2:-1}"; wtype -k Shift_L; sleep 0.5; grim "$out/$1.png"; echo "shot $1"; }
act() { gapplication action com.mecedric.StoryArc "$@" || echo "action $1 failed: is the app still running? $(pgrep -c storyarc || true) process(es)"; }
tree() { python3 /src/apps/desktop-linux/scripts/a11y-tree.py > "$out/a11y-$1.txt" 2>&1 || true; echo "tree $1: $(wc -l < "$out/a11y-$1.txt") lines"; }

start_app
shot library 2
tree library

# The audiobook: the mini player at the foot of the library, and the controls' view of it. The
# fixture is six seconds long, so the reads happen inside the first three and the pause holds it.
act open-reader "'$fixtures/audiobooks/id3-chapters.mp3'"; sleep 1.5
shot player-bar 0.2
{
  echo "status: $(playerctl -p storyarc status 2>&1)"
  echo "title: $(playerctl -p storyarc metadata title 2>&1)"
  echo "position: $(playerctl -p storyarc position 2>&1)"
  echo "players: $(playerctl -l 2>&1 | tr '\n' ' ')"
  playerctl -p storyarc play-pause || true; sleep 0.5
  echo "after play-pause: $(playerctl -p storyarc status 2>&1)"
  playerctl -p storyarc position 2 || true; sleep 0.5
  echo "after position 2: $(playerctl -p storyarc position 2>&1)"
} | tee "$out/playerctl.txt"
shot player-paused 1
tree player-bar
playerctl -p storyarc stop || true; sleep 1

# The EPUB reader: open, turn, turn back.
act open-reader "'$fixtures/ebooks/fixture.epub'"; sleep 8
shot epub-reader 2
tree epub-reader
wtype -k Right; shot epub-next 2
wtype -k Left; sleep 1
wtype -M ctrl -k w -m ctrl; sleep 2

# The PDF reader: the page, the outline, the text pane, a search.
act open-reader "'$fixtures/comics/text-pages.pdf'"; sleep 5
shot pdf-reader 2
tree pdf-reader
# The walk opens search through the hook: a wtype Control chord was not delivered under cage.
act reader-action "'find'"; sleep 1; wtype "chapter two"; shot pdf-search 2
tree pdf-search
wtype -k Return; shot pdf-search-hit 2
wtype -k Escape; sleep 1
wtype -M ctrl -k w -m ctrl; sleep 2

echo "walk done"
