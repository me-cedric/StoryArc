# Wave 6 frames, iOS, 2026-10-09

Device: iPhone 17 Pro Max simulator `EC086B47-A976-4DC4-B206-194D8E46EC3F`, iOS 26.4.
Debug build from the head of `wave-6`. Default text size only.
A file that ends in `-dark` is the dark twin. A file with no twin is light only.
The walks are in `apps/ios/UITests/SweepWave6.swift`.

## Frames

| Frame | Task | What it proves |
| --- | --- | --- |
| `ios-provenance-fr.png` | 25.1 | The publication page of a comic held on the device reads "Sur cet appareil, lisible sans réseau" in French. |
| `ios-epub-resume-light.png` | 7.9 | `fixture.epub` closed on a page that starts at "Chapter 1, paragraph 27" opens again on a page that starts at the same paragraph, after a new app process. The book has 80 paragraphs, so this page is near 0.33 of the book. The Android frame must start at the same paragraph. |
| `ios-home-resume*.png` | 25.7 | The Resume button on the Home hero, with the label colour made for the fill. The hero shows `Fixture Publication`. |
| `ios-continue-listening*.png` | 25.7 | "Continue listening" on the title page of the audiobook Sea Room after one play and pause. |
| `ios-conflict-one*.png` | 5.4 | One title moved on both devices: the notice "Read in two places" names the title, the kept page and the set aside page. |
| `ios-conflict-several*.png` | 5.4 | Two titles moved on both devices: the notice gives the count and offers Show. |
| `ios-sync-picker-inside-storyarc*.png`, `ios-sync-folder-refused*.png` | 5.5 | The system picker opened on On My iPhone > StoryArc (the app's Documents folder, which is the library folder). After Open, the alert says "This folder is one of your libraries. Choose another folder for sync." |
| `ios-sync-background-footnote*.png` | 5.6 | The simulator refuses every background request. The Sync section shows the grey words "iOS refused background sync. StoryArc still syncs when you open the app and when you close a book." |
| `ios-libraries-answered*.png` | 5.7 | After a sync, Your libraries shows "Available" for every source, not "Connecting". |
| `ios-theme-axes*.png` | preview:proof | The Customise sheet of the reader themes, opened from an EPUB. |
| `ios-comic-pager*.png` | preview:proof | The comic reader after one page turn, with the chrome shown. |

## How to repeat

1. `node scripts/corpus.mjs`. Build and seed: `cd apps/ios && xcodegen generate`, then `xcodebuild build-for-testing ... -derivedDataPath ../../.build/ios-ui`, then `node scripts/install-and-seed-simulator.mjs <id>`.
2. Copy into the app's `Documents`: `Quiet Machines.cbz`, `Tidal Reach 01.cbz` and `Corpus/fixture.epub` (from `packages/test-fixtures/ebooks`).
3. Every frame is `node scripts/capture-ios.mjs --out <dir> --only SweepWave6Tests/<test> --device <id> --appearance light|dark`.
   Tests: `testCaptureProvenanceFrench`, `testCaptureEpubResume`, `testCaptureHomeResume`, `testCaptureContinueListening`, `testCaptureSyncFolderRefusal`, `testCaptureSyncBackgroundFootnote`, `testCaptureLibrariesAnswered`, `testCaptureThemeAxes`, `testCaptureComicPager`.
4. Sync frames need a writable share. This run used `scripts/smb-server.sh --writable ~/StoryArcCorpus 4450` (the Android agent held 4448), in its own session (`perl -e 'use POSIX; setsid(); exec @ARGV' ...`). Write the port in `/tmp/w5sync/port` and the path of `StoryArc Library.json` in `/tmp/w5sync/remote-file`.
   Add the share and choose it with `SyncSettingsWalkTests/testCaptureSyncShareOffered` and `testCaptureSyncSynced`.
5. One title (`testCaptureConflictOne`): a second device is simulated by the test. It edits the position of the title in the sync file before this device closes the book. The close of the book syncs, and both sides have moved since the last sync. Run `testSetupQuiet` and `testSyncOnly` once before.
6. Several titles (`testCaptureConflictSeveral`): in one test the share folder is renamed away while both books are read, so no sync settles them. The folder returns, the sync file is edited for both titles, and Sync now runs once. The turn counts for the two books are in `/tmp/w5sync/turns` (for example `3 4`). Each run must use counts that differ from the page where the last sync left each book, or that book raises no conflict.

## Why the sync frames needed these steps

A sync runs when the app opens and when a book closes. A conflict needs both devices to have moved since the last sync, so the edit of the sync file has to come before the close that syncs, or the sync must fail while the book is read.

## Owed

- 25.6, "1 of 1 title" in the source detail: not taken. The line shows only while a Kavita read is partial, and a partial read needs more than 60 series on the server (`KavitaContributor.firstSlice`). A stored record with read 1 and total 1 would also have to be injected, and the continued read then finishes in a moment. No walk reaches a steady state of that screen.
- 25.7, Finish on the Home hero: not taken. The seeded comic has three pages. At its last page the record is finished, so Home lists it under Finished and offers no Finish. A comic with more pages is needed. Resume was photographed instead; Resume and Finish share one modifier (`onAccentLabel`).
- 25.7, Resume with an audiobook hero: not taken. The hero shows the most recent book, which was the EPUB.
- 25.1, the four other provenance states (server title not downloaded, server stopped, library removed, second place): not taken.
- 7.9, a frame inside a long paragraph: not taken. The paragraphs of `fixture.epub` are two lines long.
- The accessibility audit of the title page passes (`AccessibilityAuditTests/testPublicationPagePassesTheAudit`). The Home audit reports 11 issues, all on cover cells and captions (contrast and clipped text); none names the Resume or Finish button.

## Product findings

- A folder audiobook has no content digest, so its position is keyed by its path in the app container. The sync file of this run holds one position for `Sea Room` under each of seven container paths. After a reinstall the container path changes, the old position is not found, and the page says "Listen", not "Continue listening". The covers of comics and EPUBs, which have a digest, kept their positions.
- An EPUB record in the sync file read `isFinished: true` at progression 0.1667 after a resume and one page turn. The cause is not found. Earlier in the run, the same book opened at its first page with the button "Continue reading" after a run that turned to the end of the book.
- In the conflict walks the comic reader opened on its first page (the cover colour) while the title page said "Continue reading". The saved page was 2 to 6. It is not proved whether the reader ignored the saved page or the walk reset it.
- Adding the share again through the form added a second source with the same name, `127.0.0.1/Sync`. Your libraries lists both.
