# iOS — the player, 2026-09-01

Taken on the booted `StoryArc-iPhone17Pro` simulator (iOS 26.5) by
`node scripts/capture-ios.mjs --out … --only <test>`, which drives
`UITests/ScreenshotTests` rather than photographing whatever is in front of it.

The device needs an audiobook on its shelf first — the walk fails by name rather than
photographing an empty shelf if it has none:

```bash
D=$(xcrun simctl get_app_container <udid> app.storyarc.StoryArc data)/Documents
cp packages/test-fixtures/audiobooks/chaptered.m4b "$D/<library folder>/Sea Room.m4b"
```

| Picture | What it shows |
| --- | --- |
| `ios-library-nothing-playing.png` | **The control.** The shelf with no session running. |
| `ios-compact-player.png` | The compact bar while an audiobook is loaded and paused. |
| `ios-full-player.png` | The full player, opened from the bar. |
| `ios-full-player-largest-text.png` | The same player at `AccessibilityXXXL`. |

## Why the first one is here

`AGENTS.md` §6: "a screenshot that could look the same for a boring reason needs a
control". The claim the second picture makes is that a bar *appears* above the
navigation control and **does not displace it** — and a picture of the bar cannot prove
that on its own, because a tab bar that had always been that high would look identical.
The two are the same device, the same shelf, the same text size, minutes apart. The four
destinations sit at the same height in both.

## What each picture settles

**`ios-compact-player.png`** — the bar names the publication (*Sea Room*) and the
**chapter** (*Two*), not the file and not a countdown. That is `audio-playback`'s compact
bar and the reason `design.md` gives for it: a narrated file knows its duration and a
synthesised voice does not, so the bar states the thing both know.

**`ios-full-player.png`** — cover, publication, chapter, a scrub control with the
chapter's own `0:00 / 0:02`, skip glyphs carrying **15** and **30** (the product-decision
defaults `design.md` records — no guideline is cited for them), play/pause, and the
chapter list, speed and sleep timer.

The chapter names are read from the M4B's own chapter atom, on the device: the fixture's
three chapters are *One*, *Two*, *Three*, and the player is showing the second. That is
also the end-to-end proof of the correction in `AudiobookReader` — asking the asset for
its own chapter locales rather than for the reader's preferred languages. Had that been
wrong, this picture would show one unnamed part.

## What these do not show

The bar is **paused** in both. The corpus audiobooks are seconds long, so a capture that
let one play would photograph the bar once and an empty shelf the next time, the book
having ended correctly in between. A paused session keeps its bar, which
`CompactPlayerTests` pins.

Read-aloud is still drawn by `ReadAloudDock`, not by this player. See task 4.2 —
the merge is blocked on Readium 3.11.0 having no speech rate.

`ios-full-player-largest-text.png` shows the player at the largest accessibility text
size: the publication and the chapter are readable in full rather than truncated to one
word, the times are readable, and the transport is on the screen with its glyphs at their
own size rather than grown with the text. The settings row below it is past the fold and
the surface scrolls to it, which is what `audio-playback` asks for — "the surface scrolls
if it must".

It is **not** the whole of §8, which is not started: nothing here has been through
VoiceOver. The announcements `PlayerLabels` produces are asserted by `PlayerLabelsTests`
and have not been heard.
