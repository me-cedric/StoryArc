#!/usr/bin/env bash
# The wave 5 headless walk, run INSIDE the Ubuntu 24.04 container by headless-proof.sh --walk <dir> wave5-walk.sh.
# Under cage (headless wlroots) with a session bus: a second instance of the app hands
# `storyarc://` links to the running one through the open signal, the way the desktop entry's
# `x-scheme-handler/storyarc` would (task 5.8); then the chrome accent and the click zones
# (task 5.11) with fake-settings-portal.py standing in for the settings portal, and without it
# for the absent choice. Each outcome is captured with grim into /out and the app's log keeps
# what the toast and the refusal said.
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
act() { gapplication action com.mecedric.StoryArc "$@" || echo "action $1 failed"; }
stop_app() { act quit; wait "$app_pid" 2>/dev/null || true; app_pid=0; sleep 1; }
# The preferences file the app reads at launch: appearance, accent, click zones.
prefs() { printf 'appearance=%s\naccent=%s\nclick-zones=%s\n' "$1" "$2" "${3:-true}" > "$data/preferences"; }
# A second instance with a link on its command line: GApplication hands it to the running one.
link() { "$app" "$1" || echo "second instance for $1 exited $?"; }

# The settings portal stands in from the start: the real xdg-desktop-portal of the image would
# take the name the moment libadwaita asks, and it reports no accent.
portal() { PORTAL_ACCENT="${1:-}" python3 /src/apps/desktop-linux/scripts/fake-settings-portal.py & portal_pid=$!; sleep 1; }
portal 0.21,0.52,0.89

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
stop_app

# The chrome accent (task 5.11): the portal reports a blue accent, and the four captures show
# the library with its preferences dialog open on Appearance.
for accent in storyarc system; do
  for appearance in light dark; do
    prefs "$appearance" "$accent"
    start_app
    act preferences-page "'appearance'"; shot "accent-$accent-$appearance" 2
    stop_app
  done
done

# A portal with no accent set, as a session on libadwaita 1.5 reads one: the Accent row is absent.
kill "$portal_pid"; sleep 1; portal
prefs light storyarc
start_app
act preferences-page "'appearance'"; shot accent-absent 2
stop_app

# The click zones on (the default): the Reading page of the preferences, then a reader.
prefs light storyarc true
start_app
act preferences-page "'reading'"; shot zones-setting 2
wtype -k Escape; sleep 1
act open-reader "'$fixtures/comics/natural-sort.cbz'"; shot reader-zones 4
wtype -k Right; shot reader-zones-next 2
echo "walk done"
