#!/usr/bin/env bash
# The wave 4 player walk, run INSIDE the Ubuntu 24.04 container by
# `headless-proof.sh --walk <dir> wave4-player-walk.sh`. Under cage with a session bus, an
# accessibility bus, speech-dispatcher on libao's null driver and no sound device: an
# audiobook's page, the full player and its lists, a book with no cover, then a voice reading
# the corpus EPUB, the bar that leads back to it, the book reopened on the voice, and another
# book displacing it. Each screen is captured with grim and dumped as an accessibility tree.
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
HOME="$(mktemp -d /tmp/home-player.XXXXXX)"; export HOME
export LANG=C.UTF-8
# speech-dispatcher with no sound device: libao's null driver, so a sentence reaches its end.
mkdir -p "$HOME/.config/speech-dispatcher"
printf 'AudioOutputMethod "libao"\nLogLevel 3\n' > "$HOME/.config/speech-dispatcher/speechd.conf"
printf 'default_driver=null\n' > "$HOME/.libao"
eval "$(dbus-launch --sh-syntax)"
export DBUS_SESSION_BUS_ADDRESS
export GTK_A11Y=atspi
/usr/libexec/at-spi-bus-launcher --launch-immediately >/tmp/at-spi.log 2>&1 &
sleep 1

# The corpus comics, audiobooks and ebooks as three folder libraries.
data="$HOME/.local/share/com.mecedric.StoryArc"; mkdir -p "$data"
printf 'path\t%s\npath\t%s\npath\t%s\n' "$fixtures/comics" "$fixtures/audiobooks" "$fixtures/ebooks" > "$data/sources"

RUST_BACKTRACE=1 G_MESSAGES_DEBUG=storyarc cage -- "$app" >/tmp/storyarc.log 2>&1 &
app_pid=$!
sock=""
for _ in $(seq 1 40); do
  sock=$(ls "$XDG_RUNTIME_DIR" | grep -m1 '^wayland-[0-9]*$' || true)
  [ -n "$sock" ] && break
  sleep 0.5
done
export WAYLAND_DISPLAY=$sock
sleep 8
wtype -k Tab; sleep 1

shot() { sleep "${2:-1}"; wtype -k Shift_L; sleep 0.5; grim "$out/$1.png"; echo "shot $1"; }
act() { gapplication action com.mecedric.StoryArc "$@" || echo "action $1 failed"; }
tree() { python3 /src/apps/desktop-linux/scripts/a11y-tree.py > "$out/a11y-$1.txt" 2>&1 || true; echo "tree $1: $(wc -l < "$out/a11y-$1.txt") lines"; }

# The page of a chaptered audiobook never started: its chapters, and Listen.
act show-detail "'$fixtures/audiobooks/chaptered.m4b'"; shot player-detail 4
tree player-detail

# The book plays: the full player, then its lists. The fixture lasts six seconds, so it is
# paused in its second chapter and read from outside the app first.
act open-reader "'$fixtures/audiobooks/chaptered.m4b'"; sleep 2.5
{
  echo "status: $(playerctl -p storyarc status 2>&1)"
  echo "title: $(playerctl -p storyarc metadata title 2>&1)"
  echo "chapter line: $(playerctl -p storyarc metadata xesam:artist 2>&1)"
  echo "art: $(playerctl -p storyarc metadata mpris:artUrl 2>&1)"
  playerctl -p storyarc play-pause || true; sleep 1
  echo "after play-pause: $(playerctl -p storyarc status 2>&1)"
} | tee "$out/playerctl-player.txt"
shot player-full 1
tree player-full
act player-action "'chapters'"; shot player-chapters 2
tree player-chapters
wtype -k Escape; sleep 1
act player-action "'speed'"; shot player-speed 2
wtype -k Escape; sleep 1
act player-action "'sleep'"; shot player-sleep 2
wtype -k Escape; sleep 1

# Back on the page: the primary action names the chapter it resumes inside; the bar names it too.
act player-action "'window.close'"; sleep 1
act show-detail "'$fixtures/audiobooks/chaptered.m4b'"; shot player-detail-resume 3
tree player-detail-resume

# A book with no cover and no chapter marks: the coverless artwork, and its page states its length.
act open-reader "'$fixtures/audiobooks/unchaptered.m4a'"; sleep 1
playerctl -p storyarc play-pause || true
echo "coverless art: $(playerctl -p storyarc metadata mpris:artUrl 2>&1)" | tee -a "$out/playerctl-player.txt"
shot player-coverless 1
act player-action "'window.close'"; sleep 1
playerctl -p storyarc stop || true; sleep 1
act show-detail "'$fixtures/audiobooks/unchaptered.m4a'"; shot player-detail-one-part 3

# The EPUB's page names the voice that reads it, once, where the player names none.
act show-detail "'$fixtures/ebooks/fixture.epub'"; shot epub-detail-voice 3

# A voice reads the EPUB: the spoken sentence drawn on the page, Stop and the player at the top.
act open-reader "'$fixtures/ebooks/fixture.epub'"; sleep 8
act reader-action "'read-aloud'"; shot epub-voice 4
tree epub-voice
# The book closes and the voice goes on: the bar names the book and the chapter and leads back.
wtype -M ctrl -k w -m ctrl; shot player-bar-voice 3
tree player-bar-voice
# Reopened, the book takes the voice again at its sentence.
act open-reader "'$fixtures/ebooks/fixture.epub'"; shot epub-voice-reopened 8
# Another book opens: the voice stops and that window says so once.
act open-reader "'$fixtures/ebooks/fixed-layout.epub'"; shot epub-voice-stopped 4
tree epub-voice-stopped

echo "walk done"
