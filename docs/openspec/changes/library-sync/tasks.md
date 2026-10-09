A ticked box here means: the code exists on both platforms, a test that fails without it
landed, and two devices were actually reconciled in a test. A tick does **not** mean a person
synced two real devices through a real cloud folder.

## 1. The watermark, which everything else rests on

- [x] 1.1 **Production writes the last-synchronised position** (both). `reading-progress`'s **Verified built on 2026-10-07** against the source: KavitaExchange.settled stamps the watermark on every Kavita pull, push, open-seed and EPUB report path, on both platforms.
  *Conflict resolution* asks four times whether a side changed "since the last sync", and
  nothing writes what the last sync was. `STATUS.md` records that every conflict notice the app
  shows is therefore false. Write it wherever a position is synchronised, in either direction.
- [x] 1.2 **An absent watermark means "nothing is known", not "the local side moved"** (both). **Verified built on 2026-10-07** against the source: ProgressMerge returns the further position quietly when syncedPosition is absent; neverSyncedTakesTheFurther and neverSyncedKeepsTheFurtherLocal on both platforms.
  A device that never synchronised is the common case — it is a new phone. Test both readings.
- [x] 1.3 **A false conflict notice stops appearing** (both). A test that reconciles a **Verified built on 2026-10-07** against the source: ProgressPullTest, ProgressPullTests and both LibraryImport suites reconcile a never-synchronised device with no conflict notice.
  never-synchronised device against a further remote position and asserts the position is
  adopted silently, with no notice.

## 2. Where the document lives

- [ ] 2.1 **The reader chooses a place** (both): a share they already added, or a folder
  through the system document picker. Sync is off until they do.
- [ ] 2.2 **SMB write** (both). The share client reads today. A write, with the same
  credential, the same pins and the same unreachable-is-grey behaviour.
- [ ] 2.3 **A folder through the picker, held across launches** (both). A security-scoped
  bookmark on iOS, a persisted URI grant on Android — the same thing `local-library` already
  does for a picked folder, so reuse it rather than writing a second one.
- [ ] 2.4 **Unreachable is a normal state** (both). The library keeps working, the place shows
  as unreachable rather than as an error, and sync resumes when it can.

## 3. Merging

- [x] 3.1 **A write is read-merge-write, never a blind overwrite** (both). Two devices writing
  within moments of each other both survive. Each record carries which device last changed it
  and when.

  **Wave 4 (close-all-yellow), 2026-10-09.** Built. The reviewer fixed one defect. `LibrarySync` reads the document, merges it and each conflicted copy, writes with the version it read, retries three times, then reports Busy. A newer or unreadable document is refused and not written. `LibraryTransfer.sync` first wrote through the store save, which stamps the current moment on each value that the merge took from the other device. `LibraryArchive.apply(exactly = true)` now writes what the merge decided. Mutation proofs ran on both platforms. **For tasks 2.x and 4.x:** `SyncPlace` has no real place until 2.2 and 2.3. A screen must not write the stores while a sync runs, and it must reload its in-memory shelves after a sync. A screen that saves an old in-memory `Shelves` records a tombstone, and that deletion goes to every device.
- [x] 3.2 **Reading progress merges by ADR-0006** (both), reusing `ProgressMerge` after task 1. **Wave 4 (close-all-yellow), 2026-10-09.** Built. The reviewer fixed one defect. The Android progress store keeps only the fraction of a watermark, so no stored position equalled its stamped copy, and each sync wrote every position back and undid a page turned during the sync. `LibraryTransfer.sync` now compares records in stored form. The new test 'a page turned while a sync runs is not put back' failed before the fix. The iOS twin passes.
- [x] 3.3 **Shelves merge their members** (both), reusing `ShelfMerge`. **Wave 4 (close-all-yellow), 2026-10-09.** Verified. A member removed on one device comes back through the union. The spec asks only for the union.
- [x] 3.4 **A deletion travels** (both). A collection the reader deleted on one device does not
  come back at the next sync.

  **Wave 4 (close-all-yellow), 2026-10-09.** Built. The reviewer fixed one defect on both platforms. A member taken from the other device got the sync moment, which is later than a deletion, so the deleted shelf came back. The exact apply of task 3.1 corrects it. The new tests failed before the fix.
- [x] 3.5 **Settings and themes merge last-writer-wins per field** (both), with the device and
  the moment recorded. A preference is not an accumulating value, so furthest-wins does not
  apply to it.

  **Wave 4 (close-all-yellow), 2026-10-09.** Verified. `SettingsStamps` and `ThemeStamps` merge each field by last writer, to the whole second. On a tie, the device id that sorts last wins. A field that the other platform cannot express keeps the value of this device. No sync-place setting travels.
- [x] 3.6 **A provider's conflicted copy is merged, not ignored** (both). iCloud Drive and
  Google Drive both produce sibling files when two devices write at once; the app finds one and
  merges it.

  **Wave 4 (close-all-yellow), 2026-10-09.** Verified. `isConflictedCopy` recognises the copy names of iCloud, Google Drive, Dropbox and OneDrive. A readable copy is merged and deleted. An unreadable copy is skipped and named. A copy that cannot be deleted is kept as `name@version` and is not merged twice. **Left:** the proof with copy files that a person writes in a real picked folder needs task 2.3 and a trigger from tasks 4.x.
- [x] 3.7 **Kavita rows are left to Kavita** (both). A test asserting the document carries no
  position for a Kavita publication, so there are not two sources of truth for one fact.

  **Wave 4 (close-all-yellow), 2026-10-09.** Verified. A test asserts that the document carries no position for a Kavita publication.

## 4. When it happens

- [ ] 4.1 **On foreground** (both).
- [ ] 4.2 **When the reader leaves a publication** (both). This is the moment that matters.
- [ ] 4.3 **In the background, as far as each platform allows** (both). Android periodic work at
  its 15-minute floor; iOS background refresh, which the system may skip.
- [ ] 4.4 **The setting says what each platform actually does** (both), per platform, in four
  languages. One sentence claiming the same on both would be false on at least one.

## 5. Proof

- [x] 5.1 **Two devices, reconciled in a test** (both). Device A reads to page 40, device B to
  page 20, both offline; after a sync both are at 40 and neither saw a conflict notice.

  **Wave 4 (close-all-yellow), 2026-10-09.** Verified. Two in-memory devices share an in-memory place. Devices at 40 and 20 that never synced both reach 40 with no notice. Two devices that both moved after a shared sync get one notice that names both positions. A finished publication stays finished.
- [x] 5.2 **Cross-platform**: a document written by Android is merged by iOS and the reverse. **Wave 4 (close-all-yellow), 2026-10-09.** Verified. Each platform commits the document that its sync path writes (`sync-written-by-android.json`, `sync-written-by-ios.json`) and merges the document of the other platform.
- [ ] 5.3 **Frames**: choosing the place, the sync state, and a conflict notice that is real.
  Both platforms, light and dark, default and largest text.

  **Wave 4 (close-all-yellow), 2026-10-09.** Not taken. The sync-engine lane changes no screen. The frames need tasks 2.x and 4.x first.
