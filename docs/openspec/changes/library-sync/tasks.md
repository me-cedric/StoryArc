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

- [ ] 3.1 **A write is read-merge-write, never a blind overwrite** (both). Two devices writing
  within moments of each other both survive. Each record carries which device last changed it
  and when.
- [ ] 3.2 **Reading progress merges by ADR-0006** (both), reusing `ProgressMerge` after task 1.
- [ ] 3.3 **Shelves merge their members** (both), reusing `ShelfMerge`.
- [ ] 3.4 **A deletion travels** (both). A collection the reader deleted on one device does not
  come back at the next sync.
- [ ] 3.5 **Settings and themes merge last-writer-wins per field** (both), with the device and
  the moment recorded. A preference is not an accumulating value, so furthest-wins does not
  apply to it.
- [ ] 3.6 **A provider's conflicted copy is merged, not ignored** (both). iCloud Drive and
  Google Drive both produce sibling files when two devices write at once; the app finds one and
  merges it.
- [ ] 3.7 **Kavita rows are left to Kavita** (both). A test asserting the document carries no
  position for a Kavita publication, so there are not two sources of truth for one fact.

## 4. When it happens

- [ ] 4.1 **On foreground** (both).
- [ ] 4.2 **When the reader leaves a publication** (both). This is the moment that matters.
- [ ] 4.3 **In the background, as far as each platform allows** (both). Android periodic work at
  its 15-minute floor; iOS background refresh, which the system may skip.
- [ ] 4.4 **The setting says what each platform actually does** (both), per platform, in four
  languages. One sentence claiming the same on both would be false on at least one.

## 5. Proof

- [ ] 5.1 **Two devices, reconciled in a test** (both). Device A reads to page 40, device B to
  page 20, both offline; after a sync both are at 40 and neither saw a conflict notice.
- [ ] 5.2 **Cross-platform**: a document written by Android is merged by iOS and the reverse.
- [ ] 5.3 **Frames**: choosing the place, the sync state, and a conflict notice that is real.
  Both platforms, light and dark, default and largest text.
