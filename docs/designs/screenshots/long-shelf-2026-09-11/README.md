# A sectioned shelf of 218 — 2026-09-11

The long-shelf frames `one-library-three-destinations` task 6.5 item 9 asks for, and
the answer to the question the first attempt at them could not answer.

**The first attempt is withdrawn and its frames are replaced.** It captured a shelf
of 29 publications and labelled it 220, because it read the file count on disk
instead of the app's own index. The cause of that 29 is now known, it was a defect
in the corpus generator, and the app was never at fault. The section below records
it, because the same class of defect can return.

## The frames

Taken on `emulator-5554` (1080 × 2400, Android 16) with
`node scripts/capture-android.mjs`. The shelf holds **218 publications** and is
sorted by title in every frame.

| Frame | Grouping | Layout | Theme | Text size | Headings |
| --- | --- | --- | --- | --- | --- |
| `android-issues-sectioned-light.png` | issues | grid | light | 1.0 | *Ashfall*, *Bellwether* |
| `android-issues-sectioned-dark.png` | issues | grid | dark | 1.0 | *Ashfall*, *Bellwether* |
| `android-issues-sectioned-large-light.png` | issues | grid | light | 2.0 | *Ashfall* |
| `android-issues-sectioned-large-dark.png` | issues | grid | dark | 2.0 | *Ashfall* |
| `android-series-grouped-light.png` | series | grid | light | 1.0 | none |
| `android-series-grouped-dark.png` | series | grid | dark | 1.0 | none |
| `android-long-list-light.png` | issues | list | light | 1.0 | none |

Each row was read from a `uiautomator` dump, not from the picture. A heading is a
full-span text node at the leading edge — *Ashfall* measures `x 53–964` on a
1080 px screen — and the alphabetical index is the column of single letters at
`x ≈ 1017`, which reads `A` to `R` in every frame. At text size 2.0 the grid drops
from three covers across to two and the heading stays pinned. The rail's letters
grow with the text size on Android, so the column shows `A` to `M` instead of `A`
to `S` — fewer letters in view, each one a larger target. iOS caps the rail's text
size instead (`LibraryRail.swift:176`, `.dynamicTypeSize(...DynamicTypeSize.large)`),
so the two platforms differ here and neither is photographed against the other.

The green outline around the rail in every frame is **TalkBack's accessibility
focus**, which is enabled on this emulator. It is not a border the app draws. The
focus rests on the whole rail rather than on one letter, which is worth knowing
before anyone reads the ring as a design element.

## What the frames establish

1. **A long shelf sections.** Under *Grouping: Issues* the grid draws a pinned
   heading per series, beside the A–Z rail. This is the frame item 9 asks for and
   it had never been taken.
2. **Under *Grouping: Series* the same shelf draws no heading.** A series is one
   cell in that grouping, so 218 publications collapse to 47 rows and a heading
   would head about one cover each. `LibrarySections.kt:121` refuses a division
   that averages fewer than three covers per heading, and its comment gives the
   reason: a tall column of announcements reads worse than the wall it replaced.
   *Read from the source, not instrumented.* The measurement is only that the
   headings are absent.
3. **The list layout draws no heading at 218 either.** `CoverList` takes no
   sections, and says so at its `rail` parameter: the list "draws one item per row
   and opens no headings while the index is offered". Whether `library-browsing`
   means its division to reach the list is a question for that spec, and this page
   does not answer it.
4. **220 files on disk, 218 publications indexed.** The two missing files are the
   two the shelf refuses out loud. The notice reads *2 couldn't be opened*, and
   *What couldn't be opened* names them: `Locked Vault.cbz`, "the archive is
   password protected", and `Sealed Archive.cb7`, "CB7 is not a format StoryArc
   reads". So the index is complete, and the file count was never the shelf size.

## The defect that produced the shelf of 29

`scripts/corpus.mjs` built filler publications with `pages(2, index)`, and `pages`
used its second argument as a **palette index**. The palette holds six colours, so
the filler wrapped onto the same six colours, and a two-page comic built from them is
one of a small set of byte-identical files.

Measured at `--count 220`, with the fix reverted:

| | files | distinct contents | shared groups |
| --- | --- | --- | --- |
| before | 226 | 37 | 12, six of them 28 files each |
| after | 226 | 226 | 0 |

Of the 209 CBZ files, only **20** held distinct content before the fix.

ADR-0006 makes a publication's identity a **content digest**, so the app read those
identical files as one publication each time and was right to. A corpus asked for
220 publications delivered a few dozen, and every conclusion drawn from the shelf
size was a conclusion about the generator.

The fix gives each filler publication its own two bytes of colour shift. The
invariant is now guarded: `node scripts/corpus.mjs --self-test` builds a
`--count 60` corpus and fails unless every file in it is its own content.

## Reproducing this

```bash
node scripts/corpus.mjs /tmp/corpus220 --count 220
adb -s emulator-5554 push /tmp/corpus220/. \
  /sdcard/Android/data/com.mecedric.storyarc.debug/files/
# The index caches a row per path, so a rescan over unchanged paths keeps the old
# rows. Clear it before measuring a corpus that was rebuilt in place.
adb -s emulator-5554 shell run-as com.mecedric.storyarc.debug \
  rm -f /data/data/com.mecedric.storyarc.debug/cache/library.json
# Then pull to refresh on the shelf. A rescan needs no folder picker: ScanTargets.of
# always walks the managed folder.
node scripts/capture-android.mjs "Library > issues with index" --out shot.png
```

Count `cache/library.json`, never the files on disk. That is the only number that
says what the shelf holds.
