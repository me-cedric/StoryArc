# A long shelf, and the headings it does not draw — 2026-09-11

A 220-publication library on a `storyarc-ci` emulator (`emulator-5554`,
1080 × 2400, Android 16), built with `node scripts/corpus.mjs <dir> --count 220`
and pushed to `/sdcard/Android/data/com.mecedric.storyarc.debug/files`, the folder
`LibraryViewModel.managedFolder` documents as what an emulator scans without a
picker.

Taken for `one-library-three-destinations` task 6.5, item 9: *an Android
sectioned shelf, and on either platform a shelf on record as holding at least 200
publications.*

## The shelf is on record at 220. It is not sectioned.

| Frame | Grouping | Theme |
| --- | --- | --- |
| `android-sectioned-light.png` | series | light |
| `android-sectioned-dark.png` | series | dark |
| `android-sectioned-issues-light.png` | issues | light |
| `android-sectioned-issues-dark.png` | issues | dark |
| `android-long-list-light.png` | series, **list layout** | light |

`library-browsing` asks a long shelf to be "divided by series where a publication
declares one, and otherwise by the active sort key".
`LibrarySections.THRESHOLD` is **12**. This shelf holds 220 and is sorted by
title, and **no frame carries a heading** — in the grid or in the list.

The single letters down the right edge of every frame are the alphabetical
index, not headings. Their accessibility labels read *Jump to A*, *Jump to B* and
so on, and they sit at x ≈ 1017–1037, hard against the trailing edge. A dump of
the whole tree found nothing else that could be a heading.

## What is established, and what is not

**Established.** `LibrarySections.divide` is correct and covered.
`LibrarySectionsTest` holds eight cases including *a series the shelf holds more
than one of becomes a heading*, *sections are contiguous runs, so the sort
survives them*, and *a heading is the initial of the sort key*. All pass. So this
is not the pure function.

**Established.** The shelf really does hold 220. *Ashfall* reads *3 titles* and
*Copper Wake* reads *8 titles*, where the same corpus at 140 read 2 and 4.

**Not established, and not guessed at here.** Which part of the wiring drops the
sections. `LibraryScreen` computes
`long = groups.isEmpty() && shelved.size > LibrarySections.THRESHOLD` and then
`divide(shelved, query.sort, other, locale)`, and `CoverGrid` draws a
`stickyHeader` per section when `groups.isEmpty() && sections.isNotEmpty()`. Every
one of those reads right. Something between them yields an empty list and reading
the source has not said which.

## The recipe, so the next person starts where this stopped

```bash
node scripts/corpus.mjs /tmp/corpus220 --count 220
adb -s emulator-5554 push /tmp/corpus220/. \
  /sdcard/Android/data/com.mecedric.storyarc.debug/files/
node scripts/capture-android.mjs "Library > series with index" --out shot.png
adb -s emulator-5554 shell uiautomator dump /sdcard/ui.xml   # then read it
```

The fastest next step is a Robolectric test over `LibraryScreen` at 220
publications asserting one `stickyHeader`, because that is the one thing between
the tested function and the drawn shelf that nothing asserts.
