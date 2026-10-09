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

- [x] 2.1 **The reader chooses a place** (both): a share they already added, or a folder
  through the system document picker. Sync is off until they do.

  **Wave 5 (close-all-yellow), 2026-10-09.** Verified by the reviewer. Android frames, light and dark, are in `docs/designs/screenshots/sync-places-android-2026-10-09/` (`sync-1` to `sync-3`). The iOS frames are in `docs/designs/screenshots/sync-places-ios-2026-10-09/` (`ios-sync-off`, `ios-sync-share-menu`, `ios-sync-search-results` and `ios-sync-search-opened`, light and dark).
- [x] 2.2 **SMB write** (both). The share client reads today. A write, with the same
  credential, the same pins and the same unreachable-is-grey behaviour.

  **Wave 5 (close-all-yellow), 2026-10-09.** Verified. The reviewer fixed one defect on iOS: a sync left its share session open. Android emulator proof against the writable share on 4449 (`smb encrypt = required`) and 4448: the first sync writes the file, a second sync overwrites it, a stopped server reads as "cannot be reached" in grey words, and a restarted server returns to "Synced at". See the README of `docs/designs/screenshots/sync-places-android-2026-10-09/`. iOS simulator proof: the app wrote `StoryArc Library.json` on a signed writable share (port 4450) and on an encrypted one (port 4451), a stopped share gave the grey line, and a foreign file stayed unchanged. Frames: `docs/designs/screenshots/sync-places-ios-2026-10-09/` (`ios-sync-synced`, `ios-sync-synced-encrypted`, `ios-sync-unreachable`, `ios-sync-refused-not-library` and `ios-sync-refused-newer`).
- [~] 2.3 **A folder through the picker, held across launches** (both). A security-scoped
  bookmark on iOS, a persisted URI grant on Android — the same thing `local-library` already
  does for a picked folder, so reuse it rather than writing a second one.

  **Wave 5 (close-all-yellow), 2026-10-09.** Android emulator proof is done: a picked Documents folder holds a read and write grant (`persisted=0x3`) that survives `am force-stop`, and the next sync overwrites the file. A folder that already is a library is refused with a dialog. The iOS simulator proof is done too: the system picker chose Sync Folder under On My iPhone, a new process still named the folder in the Place row, and Sync now moved the file time from 14:48:47 to 14:50:44 (`docs/designs/screenshots/sync-places-ios-2026-10-09/`, `ios-sync-folder-*`). **Left:** an owner step on a device. Pick a folder in iCloud Drive (iPhone) and in Google Drive (Android), write on one device, see the file arrive on the other, relaunch, and check the place still works. The device checklist has both steps (section H).
- [x] 2.4 **Unreachable is a normal state** (both). The library keeps working, the place shows
  as unreachable rather than as an error, and sync resumes when it can.

  **Wave 5 (close-all-yellow), 2026-10-09.** Verified by the reviewer. Android frames `sync-5` to `sync-8b` in `docs/designs/screenshots/sync-places-android-2026-10-09/` show the grey sentence, the Library with the place stopped, the return to "Synced at", and the two refusals. The iOS frames `ios-sync-unreachable`, `ios-sync-refused-not-library` and `ios-sync-refused-newer` in `docs/designs/screenshots/sync-places-ios-2026-10-09/` show the same grey words, with no red.

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

- [x] 4.1 **On foreground** (both).

  **Wave 5 (close-all-yellow), 2026-10-09.** Verified by the reviewer.
- [x] 4.2 **When the reader leaves a publication** (both). This is the moment that matters.

  **Wave 5 (close-all-yellow), 2026-10-09.** Verified by the reviewer.
- [~] 4.3 **In the background, as far as each platform allows** (both). Android periodic work at
  its 15-minute floor; iOS background refresh, which the system may skip.

  **Wave 5 (close-all-yellow), 2026-10-09.** Android emulator proof is done: the job is scheduled as a 15-minute periodic job that needs a network, and `adb shell cmd jobscheduler run -f` made the sync write the file again. **Left:** the natural 15-minute wake-up on a locked Android phone was not watched. The iOS refresh is not proved: `BGTaskScheduler.submit` fails on the simulator with `BGTaskSchedulerErrorDomain` code 1, and `_simulateLaunchForTaskWithIdentifier` answers that no task request is scheduled. Only the Info.plist keys `fetch` and `app.storyarc.sync` were read on the installed app. A real iPhone is needed. The device checklist has both steps (section H).
- [x] 4.4 **The setting says what each platform actually does** (both), per platform, in four
  languages. One sentence claiming the same on both would be false on at least one.

  **Wave 5 (close-all-yellow), 2026-10-09.** Verified by the reviewer. The Android sentence is in every Sync frame, and the iOS sentence is in the footer of every iOS Sync frame.

## 5. Proof

- [x] 5.1 **Two devices, reconciled in a test** (both). Device A reads to page 40, device B to
  page 20, both offline; after a sync both are at 40 and neither saw a conflict notice.

  **Wave 4 (close-all-yellow), 2026-10-09.** Verified. Two in-memory devices share an in-memory place. Devices at 40 and 20 that never synced both reach 40 with no notice. Two devices that both moved after a shared sync get one notice that names both positions. A finished publication stays finished.
- [x] 5.2 **Cross-platform**: a document written by Android is merged by iOS and the reverse. **Wave 4 (close-all-yellow), 2026-10-09.** Verified. Each platform commits the document that its sync path writes (`sync-written-by-android.json`, `sync-written-by-ios.json`) and merges the document of the other platform.
- [~] 5.3 **Frames**: choosing the place, the sync state, and a conflict notice that is real.
  Both platforms, light and dark, default and largest text.

  **Wave 4 (close-all-yellow), 2026-10-09.** Not taken. The sync-engine lane changes no screen. The frames need tasks 2.x and 4.x first.

  **Wave 5 (close-all-yellow), 2026-10-09, Android.** The place choice and the sync states are taken, light and dark, at the default text size: `docs/designs/screenshots/sync-places-android-2026-10-09/`. **Left:** the conflict notice (the runner drops the conflicts a sync returns, so no real notice exists).

  **Wave 5 (close-all-yellow), 2026-10-09, iOS.** The place choice and the sync states are taken on the iPhone 17 Pro Max simulator, light and dark, at the default text size: `docs/designs/screenshots/sync-places-ios-2026-10-09/` (25 frames: Sync off, the share menu, synced, synced over an encrypted share, unreachable, refused as not a library, refused as a newer version, Search finding the section, the folder picker, the folder synced, and the folder after a relaunch). **Left:** the conflict notice, because no real notice exists, and the largest text size, which is not taken by the owner rule of 2026-10-08. The task stays partial until a product change shows the conflict.
- [ ] 5.4 **A conflict notice that is real** (both). The runner drops the conflicts that a sync returns, so the app shows no notice, and 5.3 has nothing to photograph. Hand the returned conflicts to the notice that the engine already builds (decision D3: one title names the kept and the discarded position, several titles give a count and a Show action). Then take the notice frames on both platforms, light and dark, and tick 5.3.

- [ ] 5.5 **iOS accepts a library folder or the storage root as the sync place** (defect, ios). Found while landing wave 5. The first-time picker at On My iPhone accepts the whole File Provider storage root, and the app's own Documents folder (the library folder) is accepted too, so `StoryArc Library.json` lands among the books. Android refuses a library folder. Refuse both on iOS, with the same sentence Android shows, and test it.
- [ ] 5.6 **A refused background refresh is invisible on iOS** (defect, ios). `BGTaskScheduler.submit` errors are swallowed by `try?`. Log the refusal and show it in the sync status as a reason, in grey words, so the reader knows background sync is off.
- [ ] 5.7 **Libraries and the sync share read "Connecting" while the share answers** (defect, both). iOS: other libraries in Your libraries stay Connecting for 12 seconds or more after launch. Android: the sync share's source row reads "Connecting - 0 titles" for a few seconds after a place is chosen, beside "Synced at". Show the state the share already answered.
- [ ] 5.8 **Android shows sources that came from another device as libraries** (defect, android). Rows that the sync brought from iOS (for example a 127.0.0.1 address) appear as libraries with no mark, and a 127.0.0.1 row cannot work on another device. Mark a source that belongs to another device, and do not try to reach a loopback address from it.