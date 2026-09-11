# A shelf of 29, mistaken for a shelf of 220 — 2026-09-11

> **Read this first: the claim this directory was committed with was wrong, and
> the frames are not what their filenames say.**
>
> I pushed 220 valid CBZs into the managed folder, saw the file count come back as
> 220, and captured the shelf as a 220-publication library. It was not one. The
> app's own index, `cache/library.json`, held **29 publications** across ten
> initials — `ABCFGHPQST` — which is exactly the set the alphabetical rail drew in
> every frame. The corpus on disk spans twenty-four initials. I had the evidence
> of the mismatch on screen and read the file count instead of the index.
>
> So: these five frames are of a **29-publication** shelf. Whether a 220-publication
> shelf sections is **not shown here and not established**.
>
> This is the same mistake I had caught in someone else's work earlier the same
> day — counting what is on disk rather than what the app holds — and I made it
> next. The remaining notes below are kept because the measurements in them are
> real; the conclusion they were written to support is withdrawn.

## What is actually established

- **29 publications indexed from 220 files on disk**, before anything was cleared.
  Every publication of the base nineteen-title corpus is indexed, expanded into
  its parts. **Every `--count` filler publication is absent** — no Cinderpath, no
  Dovetail, no Ember Line.
- Filler files are not malformed. `unzip -l` shows `Dovetail.cbz` and
  `Ashfall.cbz` are both two-page CBZs, written by the same `zip(at(...), pages(2, index))`
  call in `scripts/corpus.mjs`.
- **After `adb shell pm clear`, the app indexes 0 of the same 220 files** and reads
  *Nothing here yet*. `pm clear` also deletes the external files directory, so the
  corpus has to be re-pushed first — which it was, and the count stayed 0.
  So the managed folder is not scanned on a fresh install: something `pm clear`
  removes is what tells the app to scan it.
- That last fact **confounds** the first. The 29 came from a registration and a
  scan journal that predated this session, so "220 files yielded 29 publications"
  is not yet a statement about one scan of 220 files.

## What the next person should do

Establish the scan's behaviour before trusting any long-shelf capture:

1. Re-register the managed folder on a cleared app — through *Add books*, since
   `pm clear` removes whatever registration drives the scan.
2. Count `cache/library.json`, not the files on disk. That is the only number that
   says what the shelf holds.
3. Only then ask whether a long shelf sections.

`LibrarySections.divide` remains correct and covered by eight passing cases in
`LibrarySectionsTest`; nothing here casts doubt on the pure function.

## The original notes, kept for their measurements



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
