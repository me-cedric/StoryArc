# A server's shelves, before and after — Android, 2026-09-10

Every frame is the **OnePlus 7T Pro** (`f7cee850`, Android 16, API 36, 1440×3120
at 560 dpi), against the owner's own Kavita **0.9.1.4** server, over the real
network. Each is halved to 720×1560 for weight; nothing else is edited.

The *before* frames are build `92deec66`, installed 01:43. The *after* frames
are the build in this change. Same device, same server, same shelves, same
appearance — only the build differs.

The reading lists here are the server's, not the device's: the comics in this
app's own library were added by hand from local storage, and none of them come
from Kavita. That is a separate gap and belongs to
`one-library-three-destinations`.

## What each pair proves

| Before | After | The claim |
| --- | --- | --- |
| `android-collections-dark-before.png` | `android-collections-dark-after.png` | A server **collection** was a black rectangle with a caption. It composites its members now — *Marvel Cosmic* and *Star Wars* draw four quadrants, *Ghost Rider Trades* and *Punisher* have fewer than four members and draw one cover across the frame, which is `CompositeCover`'s rule unchanged. |
| `android-lists-dark-before.png` | `android-lists-dark-after.png` | The same for a server **reading list**, and the four tiles are the list's *first four in the server's order* rather than by id. |
| `android-list-dark-before.png` | `android-list-dark-after.png` | Inside a list: no artwork and no read state, against a poster on every row and **0 of 25 read** above them. |
| `android-list-light-before.png` | `android-list-light-after.png` | The same in light. |

## Largest text

`android-list-dark-ax5-after.png` and `android-list-light-ax5-after.png` are the
77-entry *Blackest Night* list at `font_scale 2.0`: the summary reads **0 of 77
read**, the number, the poster and the wrapped title all keep their places, and
no row loses its reorder controls.

**These two have no control frame, and that is a gap rather than a decision.**
Changing `font_scale` recreates the activity, which pops the navigation stack
back to Library — so the two *before* captures taken that way are of the Library
and were discarded rather than presented as something they are not. Taking a
real control means reinstalling `92deec66`, setting the scale first, and
navigating again.

## What these frames also show, and this change does not fix

**This section was wrong, and is corrected here.** It said the last row sits
*under* the navigation bar. Measuring the frames says the opposite: the list
viewport ends 24.0 dp *above* the bar, leaving a band of dead background. The
bar covers nothing — the layout reserves its height — but the gesture inset was
being paid twice, once inside the bar's height and again by every screen's own
`Scaffold`.

It predates this change and is not caused by it, which is the one thing the
original note got right. It is fixed separately, with its own measurements, at
[`../navigation-inset-2026-09-10/`](../navigation-inset-2026-09-10/README.md).

## Repeating it

```bash
adb shell am start -n com.mecedric.storyarc.debug/app.storyarc.MainActivity
adb shell input tap 505 2763    # Library
adb shell input tap 1342 240    # More
adb shell input tap 1282 604    # Shelves
adb exec-out screencap -p > shot.png
```

`adb shell uiautomator dump /sdcard/ui.xml` gives the bounds of every node, and
is how those coordinates were found rather than guessed. Light and dark are
`adb shell cmd uimode night no|yes`; the text size is
`adb shell settings put system font_scale 2.0`, which must be set **before**
navigating.
