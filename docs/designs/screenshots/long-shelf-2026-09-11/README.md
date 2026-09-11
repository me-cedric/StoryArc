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
  The 220 files were read: *Ashfall* showed *3 titles* where the same corpus at 140
  showed 2, and `Ashfall 3.cbz` exists only at 220.

- **The 29 are not explained by base-versus-filler, and my first note here said
  they were.** I wrote that every base publication was indexed and every `--count`
  filler absent. That is false: `FILLER_SOLO` in `scripts/corpus.mjs` begins
  *Ashfall, Bellwether, Cinderpath* and `FILLER_SERIES` includes *Copper Wake* — so
  *Ashfall*, *Bellwether #3* and *Copper Wake #1* to *#6* are all filler, and all
  indexed. I read the indexed titles, recognised some, and asserted a rule instead
  of checking the script.

  What can be said: **29 of 220, and the subset has no explanation here.** It is
  not alphabetical either — *The Long Field*, *Tidal Reach* and *Tidal Voices* are
  all in it while *Cinderpath* and *Dovetail* are not.
- The missing files are not malformed. `unzip -l` shows `Dovetail.cbz` (absent from
  the index) and `Ashfall.cbz` (present in it) are both two-page CBZs written by the
  same `zip(at(...), pages(2, index))` call, so whatever separates them is not the
  file.
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

**A note on how this page was written.** It carries three corrections, each of a
claim made before it was checked: the shelf size, the base-versus-filler rule, and
the sectioning conclusion that rested on both. The measurements in it are real and
were re-run; the explanations were not, until they were asked for. `LibraryScanning`
speaks of "picking up where an interrupted scan of it stopped" and of a journal,
which is a lead and is left as one rather than turned into a fourth claim.

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
