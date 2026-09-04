# The player draws, and three other things the sweep found — Android, 2026-09-04

Visual proof for four findings in
[`../android-sweep-2026-09-02/README.md`](../android-sweep-2026-09-02/README.md): §3, §4, §6
and §7. **Every frame here is after.** The before is in that folder, named beside each row.

The headline is §3. Fifteen of these pixels have never been photographed at all — the full
player, its chapter list, the speed slider and the sleep timer — because the screen that
holds them rendered its empty state while audio played.

---

## §3 The player says "Nothing is playing" while it is playing

| After | Before | What to look at |
| --- | --- | --- |
| `android-player-full.png` | `../android-sweep-2026-09-02/android-player-full.png` | The whole point. The before is *"Nothing is playing."* and a **Go back** link on an otherwise empty screen; this is the chapter name, the scrub, the elapsed and total, the transport, the two skip intervals, the speed slider and the sleep timer. |
| `android-player-chapters.png` | `../android-sweep-2026-09-02/android-player-chapters.png` | The same screen scrolled. Three chapters, each with its length, and *Playing* against the one that is. They come from the M4B container's own chapter atom — the thing `AudiobookChapters` exists to read and which nothing had ever shown working on a device. |
| `android-player-full-dark.png` | `../android-sweep-2026-09-02/android-player-full-dark.png` | The same, dark. |
| `android-player-full-scale2.png` | `../android-sweep-2026-09-02/android-player-full-scale2.png` | `font_scale 2.0`. `audio-playback` asks that "the surface scrolls if it must, and no transport control is pushed off the screen"; the chip rows wrap to two lines and the transport stays. First picture of that. |
| `android-player-compact-bar.png` | `../android-sweep-2026-09-02/android-player-compact-bar.png` | Home after starting a book. The before has **no bar**. |
| `android-player-compact-bar-scale2.png` | — | The bar at the largest text size, on the Library. Not in the sweep, because there was no bar to photograph. |

**The root cause, in one sentence.** `PlaybackCentre.start` attaches its listener and *then*
asks the source to play, while `AudiobookSource.play` asked the player first and marked its own
session started afterwards — so the callback a real player fires inside `play()`
(`playWhenReady` true, `isPlaying` still false, nothing buffered) reached
`PlaybackCentre.publish` while the session still said `IDLE`, and `publish` reads an inactive
session as *the book ran out*. The centre dropped the source it had just started and published
null, while the controller had already told the service to play.

`PlayerStartTest` pins it; `FakePlayer` could not see it, because its `play()` set
`wantsToPlay` above the call to `change`, so a play that produced no sound reported nothing at
all.

## §4 Turning Material You off changes less than it should

The sweep's complaint is right and its diagnosis is not. Two separate things, and only one of
them is a scheme.

**What was Material's, and now is not.** Every bottom sheet, every dialog, every menu and the
navigation bar drew Material's baseline lavender greys on the brand path, because the
`surfaceContainer` family was never set — the accent pass of 2026-09-01 listed it among the
roles it left. Sampled off the frames, not argued:

| Surface | Before | After | Role |
| --- | --- | --- | --- |
| Navigation band, light | `#F3EDF7` | `#FFFFFF` | `surfaceContainer` ← `light.surfaceRaised` |
| Navigation band, dark | `#211F26` | `#1A1815` | `surfaceContainer` ← `dark.surfaceRaised` |
| Comic menu sheet, dark | `#1D1B20` | `#1A1815` | `surfaceContainerLow` ← `dark.surfaceRaised` |
| Comic menu sheet, light | `#F7F2FA` | `#FFFFFF` | `surfaceContainerLow` ← `light.surfaceRaised` |

| After | Before |
| --- | --- |
| `android-library-grid-nodynamic.png` | `../android-sweep-2026-09-02/android-library-grid-nodynamic.png` |
| `android-library-grid-nodynamic-dark.png` | `../android-sweep-2026-09-02/android-library-grid-nodynamic-dark.png` |
| `android-comic-menu-nodynamic.png` | `../android-sweep-2026-09-02/android-comic-menu-nodynamic.png` |
| `android-comic-menu-nodynamic-dark.png` | `../android-sweep-2026-09-02/android-comic-menu-nodynamic-dark.png` |
| `android-library-sort-menu-nodynamic.png` | `../android-sweep-2026-09-02/android-library-sort-menu-nodynamic.png` |

`android-library-grid.png` is the control: the same screen with Material You **on**, which is
unchanged and has to be. It is the frame that would say so if the grounds had been pinned on
the dynamic scheme by mistake.

Natural had the same hole and never set `secondaryContainer` either; both its variants are
fixed the same way. It and OLED Dark decline dynamic colour outright, so for those two
appearances this was the only thing a reader ever saw. **Material You is untouched**: the
grounds are pinned inside the brand and Natural schemes, never on the dynamic one.

**What the sweep got wrong.** It reads the `+`, the `⋮`, the *What couldn't be opened* and
*Dismiss* buttons, the selection ticks, the three bulk-action icons and *Done* as "Material's
baseline". They are not. Sampled at the same pixels in both of the sweep's own frames:

| Control | Material You on | Material You off |
| --- | --- | --- |
| `+` and `⋮` | `#8A4DF0` | `#8A4DF0` |
| Bulk-action icons | `#8A4DF0` | `#8A4DF0` |
| *What couldn't be opened*, *Dismiss*, *Done* | `#475D92` | `#8A4DF0` |

`#8A4DF0` is `brand.accent` exactly, and `#475D92` is the emulator wallpaper's `primary`. So
the text buttons **do** change — they were always right — and the icon buttons and ticks are
hand-tinted `LocalStoryArcPalette.current.accent` at their call sites, which is the *opposite*
defect: not Material leaking into the brand, but the brand overriding Material You on chrome.
The chrome/content rule on `LocalStoryArcPalette` forbids exactly that, and the accent pass's
own README says so in as many words about `TextButton`s. Those call sites are in
`:feature:library` and are not fixed here.

**The nav bar's two brand colours** are real and are left. The indigo pill is
`secondaryContainer` (the accent pass's `brand.accentMuted`); the crimson label is `secondary`
(`brand.secondaryStrong`), which `ShortNavigationBarItemDefaults.colors()` reads for a selected
label — measured, not assumed. `NaturalTheme.kt` carried a note saying nothing in this app
reads `colorScheme.secondary`; that was already false, and the note now says so. Making the two
agree is a palette decision.

## §6 The reader chrome sits on the text with nothing behind it

`android-epub-chrome.png` beside `../android-sweep-2026-09-02/android-epub-chrome.png`.

The comic reader named its floating toolbar's colours and the reflowable one did not, so the
capsule was Material's `surfaceContainer` — a pale lavender lozenge laid straight over running
body text. It is now the palette's scrim with white glyphs: the treatment the comic reader has
always had, and now one definition (`readerChromeColours()` in `:core:designsystem`) so the two
readers cannot drift apart again.

## §7 The page slider's handle is detached from its track

`android-comic-menu.png` beside `../android-sweep-2026-09-02/android-comic-menu.png`, and
`android-comic-adjustments.png` beside its counterpart.

Material 3 Expressive separates the handle from both halves of the rail so it reads against
the *active* half, and at a mid-range value it works — the sweep's own Brightness and Contrast
rows look right. At either end of the travel one half has no width and the gap has nothing
behind it, which is where the page slider sits whenever a book has just been opened, and where
Sharpness sits always. The gap is gone on every slider the app owns.

---

## How they were taken

Emulator `storyarc-j6` (API 36, 1080 × 2400, 420 dpi), started with `-gpu host`. Every frame
came from `pnpm capture:android <route>` except `android-player-full-dark.png`,
`android-player-full-scale2.png` and `android-player-compact-bar-scale2.png`, which were taken
by hand: with a book already playing the app comes back onto the player, and the route's walk
expects to tap in from the shelf.

**The build in these pictures is the build that was made for them**, and on this occasion that
had to be re-established twice. The debug APK's SHA-256 was compared against the installed
`base.apk` before the first frame of the final batch and after the last:

```
1ebe09625236e7e99891981ac755fadca408718ae9ce2ab218a2d3ccd2623f84
```

Byte-identical both times, same `codePath`, `lastUpdateTime` unchanged at 08:21:34.

**The emulator was not free, and it cost about forty minutes.** Twice during this session
another agent installed their build over this one — `lastUpdateTime` moved to 08:03 and then
to 08:09 with a different `codePath` and a different hash — and the device was found rotated to
landscape twice, which is not a `wm size` override and does not show up as one:
`user_rotation` was 1 and `dumpsys window displays` reported `cur=2400x1080`. A capture taken
then is a landscape frame of somebody else's build, and neither fact is visible in the picture.
**Check `user_rotation`, not just `wm size`**, and check the hash *and* the `codePath` on both
sides of a batch rather than only the timestamp.

A second emulator on a private adb server (`ANDROID_ADB_SERVER_PORT=5038`, so the shared
server never sees it and nobody else's unqualified `adb` breaks) is a way out, and it half
worked: `storyarc-api36`'s panel is 320 × 640 at 160 dpi, `wm size 1080x2400` clamps to
1080 × 1920 there, and at 731 dp tall the publication page's primary action falls below the
fold, so the player route cannot be walked. It then crashed. The frames here are all from
`storyarc-j6`.

## What was on the device

`pm clear`, then the 17 publications `scripts/corpus.mjs` generates pushed into the app's own
external files directory, plus one audiobook — the sweep's condition **A + one audiobook**.

The audiobook is **not** a committed fixture. `packages/test-fixtures/audiobooks/chaptered.m4b`
is six seconds long, which is not enough to walk a route through, so `Sea Room.m4b` was
generated for the device with ffmpeg: 45 minutes, three container chapter marks at 15-minute
boundaries, `title=Sea Room`, `artist=Adam Nicolson` — named to match the book the sweep had on
the device, so the two folders' player frames are comparable. Nothing in the repository
changed to make it.
