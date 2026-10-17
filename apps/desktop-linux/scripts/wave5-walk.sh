#!/usr/bin/env bash
# The wave 5 headless walk, run INSIDE the Ubuntu 24.04 container by headless-proof.sh --walk <dir> wave5-walk.sh.
# Under cage (headless wlroots) with a session bus: a second instance of the app hands
# `storyarc://` links to the running one through the open signal, the way the desktop entry's
# `x-scheme-handler/storyarc` would (task 5.8); each outcome is captured with grim into /out and
# the app's log keeps what the toast and the refusal said.
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
export LANG=C.UTF-8

eval "$(dbus-launch --sh-syntax)"
export DBUS_SESSION_BUS_ADDRESS

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
  wtype -k Tab; sleep 1
}
shot() { sleep "${2:-1}"; wtype -k Shift_L; sleep 0.5; grim "$out/$1.png"; echo "shot $1"; }
# A second instance with a link on its command line: GApplication hands it to the running one.
link() { "$app" "$1" || echo "second instance for $1 exited $?"; }

start_app
shot library 2

# A plain open: the title ComicInfo.xml gives manga-metadata.cbz.
link "storyarc://publication/The%20Third%20Chapter"; shot link-open 4
wtype -M ctrl -k w -m ctrl; sleep 2

# The unknown title: named in grey, nothing opens.
link "storyarc://publication/Nothing%20Like%20It"; shot link-unknown 2

# A link carrying a command: refused, nothing runs, the log says so.
link "storyarc://settings/reset"; shot link-command 2
link "storyarc://publication/The%20Third%20Chapter/delete"; sleep 1

# A source by its name: the library's folder.
link "storyarc://source/comics"; shot link-source 2

grep -c "link refused" /tmp/storyarc.log | sed 's/^/refusals logged: /' || true
grep -o "Nothing named[^\"]*" /tmp/storyarc.log | head -1 || true
echo "walk done"
