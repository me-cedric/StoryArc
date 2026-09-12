# What a page curl costs, before and after the roll

`page-transitions` says a transition "holds the display's refresh rate, and a dropped frame
during a turn is treated as a defect". Change `a-page-that-rolls-both-ways`, tasks 4.1
and 4.2. The instrument is `FrameProbe`, armed by
`adb shell settings put global storyarc_frame_probe 1`; the turns are driven by
`adb shell input swipe 1250 1500 200 1500 250`, which is a 250 ms drag across the page.

**These numbers describe this device and this build. Nothing asserts them.** They exist so
that the roll can be compared against the fold on the same phone, in the same session, with
the same drag.

## OnePlus 7T Pro (`f7cee850`), 90 Hz

The panel reports 90 Hz, and a 250 ms drag plus its settle spans about 390 ms — so a turn
that holds the rate delivers about 35 frames.

### Before the roll: the fold

| Turns | Frames delivered | Dropped | Span | Delivered per second |
| --- | --- | --- | --- | --- |
| 20 forward | 713 | 5 | 381–393 ms | 88.7 |

Twenty rather than ten, because the drags are cheap to drive and the spread matters more
than the count: every turn reported 36 frames but five frames across the twenty arrived
late, which is what 88.7 against 90 means.

### After the roll

| Turns | Frames delivered | Dropped | Span | Delivered per second |
| --- | --- | --- | --- | --- |
| 10 forward | 356 | 2 | 383–394 ms | 88.6 |
| 10 backward | 355 | 2 | 382–397 ms | 88.6 |

**No more dropped frames than the baseline.** Per turn: 0.25 before, 0.2 after in each
direction. The rate is the same to a tenth. The lip costs an `asin`, a `cos` and a `sin`
per pixel, and on this panel that is free — which was the open question, because ADR-0009
chose a fold partly to keep the fragment cheap.

The backwards turns are new: before this change a backwards drag moved nothing, so there
was nothing to measure.

## The iOS simulator

Not recorded. A simulator draws at its Mac's refresh rate, so the number would describe
this laptop; `measure-turn.mjs --ios` is written for a real device over `devicectl`, and
none is attached. `PageCurlShaderTests` is what holds the Metal to the same arithmetic in
the meantime.

## What these numbers score against the gate, from 2026-09-12

`measure-turn.mjs` now ends with a verdict and a non-zero exit. The threshold is
`--max-dropped`, and its default is **zero**, because *Frame budget* calls a dropped frame
during a turn "a defect rather than ... acceptable variance".

Every run above fails that threshold: 5 dropped frames across the twenty fold turns, and 2
across each ten-turn run after the roll. **That is the correct result, and it is a statement
about the build rather than about the gate.** The run above holds 88.6 delivered frames per
second against a panel that reports 90, and the gate says what the table already said.

`--max-dropped 2` is how a later run records what it allowed. Put the number in the command,
so that it appears beside its own result.
