#!/usr/bin/env bash
# The pseudo-locale walk (task 5.13), run INSIDE the Ubuntu 24.04 container by
# headless-proof.sh --walk <dir> pseudo-walk.sh. German, the longest of the four languages,
# padded by half again through STORYARC_PSEUDO_LOCALE, at a text scale of 2.0 set through
# org.gnome.desktop.interface on the keyfile GSettings backend (GTK reads it as gtk-xft-dpi).
# Each screen is captured with grim and its accessibility tree dumped, so a clipped label or
# a control pushed off the screen can be read off the tree as well as the frame.
set -euo pipefail
out=/out
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
export STORYARC_PDFIUM_DIR=/target/pdfium/lib
export HOME=/tmp/home; mkdir -p "$HOME"
export LANG=C.UTF-8 LANGUAGE=de_DE:de
export STORYARC_PSEUDO_LOCALE=1
export GSETTINGS_BACKEND=keyfile
gsettings set org.gnome.desktop.interface text-scaling-factor 2.0
echo "text-scaling-factor: $(gsettings get org.gnome.desktop.interface text-scaling-factor)"

eval "$(dbus-launch --sh-syntax)"
export DBUS_SESSION_BUS_ADDRESS
export GTK_A11Y=atspi
/usr/libexec/at-spi-bus-launcher --launch-immediately >/tmp/at-spi.log 2>&1 &
sleep 1

data="$HOME/.local/share/com.mecedric.StoryArc"; mkdir -p "$data"
printf 'path\t%s\n' "$fixtures/comics" > "$data/sources"

RUST_BACKTRACE=1 G_MESSAGES_DEBUG=storyarc cage -- "$app" >/tmp/storyarc.log 2>&1 &
app_pid=$!
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

shot home 2; tree home
act library; shot library 2; tree library
act downloads; shot downloads 2; tree downloads
for page in sources appearance reading storage privacy; do
  act preferences-page "'$page'"; shot "settings-$page" 2; tree "settings-$page"
  wtype -k Escape; sleep 1
done
act shortcuts; shot shortcuts 2; wtype -k Escape; sleep 1
act about; shot about 2; tree about; wtype -k Escape; sleep 1
act open-reader "'$fixtures/comics/manga-metadata.cbz'"; shot reader 4; tree reader
act reader-action "'find'"; shot reader-find 2 || true
wtype -k Escape; sleep 1
wtype -M ctrl -k w -m ctrl; sleep 2
act open-reader "'$fixtures/comics/text-pages.pdf'"; shot pdf-reader 5; tree pdf-reader
wtype -M ctrl -k w -m ctrl; sleep 2
echo "walk done"
