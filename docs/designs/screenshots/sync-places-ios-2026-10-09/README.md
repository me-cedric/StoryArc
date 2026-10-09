# Sync places, iOS, wave 5 - 2026-10-09

Device: iPhone 17 Pro Max simulator `EC086B47-A976-4DC4-B206-194D8E46EC3F`, iOS 26.4.
Debug build from the head of `wave-5` (`8c126ef96`). Default text size only.
Dark frames end in `-dark`. A frame with no dark twin is light only.

Proves `library-sync` 5.3 (iOS half), 2.1, 2.2, 2.3, 2.4 and 4.4.
Task 4.3 is NOT proved here (see Owed). The conflict notice is owed (see Owed).

## Frames

All frames show Settings > Your libraries, Sync section.

| Frame | What it proves |
| --- | --- |
| `ios-sync-off*.png` | Sync is off and no share exists: only "Choose a folder", the about sentence, the every-device sentence and the iOS sentence (iOS can sync in the background "from time to time, or never"). |
| `ios-sync-share-menu*.png` | A share exists: "Use a shared folder" opens a menu that lists the share. |
| `ios-sync-synced*.png` | The share `127.0.0.1/Sync` is the place. Grey line "Synced at HH:MM", then "Sync now" and "Turn off sync". The other libraries still read "Connecting" because the frame is taken at once after launch. |
| `ios-sync-synced-encrypted.png` | The same, on the share with `smb encrypt = required` (port 4451). Light only. It proves the write path over SMB3 encryption, not a new look. |
| `ios-sync-unreachable*.png` | The share server is stopped and the app launched: grey words "127.0.0.1/Sync cannot be reached. StoryArc syncs again when it can reach it." No red. The library row reads "Not answering". |
| `ios-sync-refused-not-library*.png` | The share holds a text file under the sync name: "The sync file is not a StoryArc library. Nothing was changed." The file on the share stayed byte for byte as it was. |
| `ios-sync-refused-newer*.png` | The share holds a document with `formatVersion` 999: "The sync file comes from a newer version of StoryArc. Update StoryArc on this device. Nothing was changed." The file stayed as it was. |
| `ios-sync-search-results*.png` | Settings search for "sync" offers one row: Sync, under Your libraries. |
| `ios-sync-search-opened*.png` | That row opens Your libraries on the Sync section with the Place row highlighted. |
| `ios-sync-folder-picker*.png` | "Choose a folder" opens the system folder picker at On My iPhone > StoryArc, with the folder `Sync Folder` in it. |
| `ios-sync-folder-picker-inside*.png` | `Sync Folder` opened in the picker, with Open at the top right. |
| `ios-sync-folder-synced*.png` | After Open: Place is `Sync Folder`, "Synced at HH:MM". |
| `ios-sync-folder-after-relaunch*.png` | A new process (the test relaunched the app): Place is still `Sync Folder`. "Sync now" writes. The file `StoryArc Library.json` in the folder changed from 14:48:47 to 14:50:44 between the two runs (measured on an earlier light run of the same walk). |

## How to repeat

1. `node scripts/corpus.mjs`, then build and seed: `cd apps/ios && xcodegen generate && xcodebuild build-for-testing ... -derivedDataPath ../../.build/ios-ui`, then `node scripts/install-and-seed-simulator.mjs <id>`.
2. Make the folder: `mkdir "$(xcrun simctl get_app_container <id> com.mecedric.storyarc data)/Documents/Sync Folder"`.
3. Start a writable share on a port that no other agent uses. This run used `scripts/smb-server.sh --writable ~/StoryArcCorpus 4450` (and `--writable --encrypted ... 4451`), because the Android frames agent served 4448 and 4449 at the same time. Run each server in its own session (`perl -e 'use POSIX; setsid(); exec @ARGV'`): `smbd` signals its process group when it stops.
4. `echo 4450 > /tmp/w5sync/port`.
5. Run the tests of `SyncSettingsWalkTests` in this order, one by one, with `node scripts/capture-ios.mjs --out <dir> --only SyncSettingsWalkTests/<test> --device <id> --appearance light|dark`:
   `testCaptureSyncOff`, `testCaptureSyncShareOffered`, `testCaptureSyncSynced`, stop the server, `testCaptureSyncUnreachable`, start the server again and write the file, `testCaptureSyncRefusedNotLibrary` (a text file named `StoryArc Library.json` in `<tmp>/storyarc-smb-4450/sync/`), `testCaptureSyncRefusedNewer` (`{"formatVersion": 999, ...}`), `testCaptureSyncSearch`, `testCaptureSyncFolderPicker`, `testCaptureSyncFolderRelaunch`.
   For the encrypted frame: port file `4451`, a fresh install, `testCaptureSyncShareOffered`, `testCaptureSyncSynced`.
   Reinstall the app between the light run and the dark run, so the "off, no share" frame is taken with no share in both.

## Emulator proofs

- 2.2 (SMB write): the app wrote `StoryArc Library.json` on both writable shares (signed 4450, encrypted 4451). A stopped server gave "cannot be reached", not an error dialog. A restarted server with a foreign file gave a named refusal, and the file was not changed.
- 2.3 (folder): the folder from the system picker is kept. A new process still showed it as the place, and a sync wrote into it.
- 2.4 (unreachable is normal): `ios-sync-unreachable*.png` and the refusal frames. The library stays usable.
- 4.4 (per platform sentence): the iOS sentence is on every frame.

## Owed

- 4.3 (background refresh), proof on the simulator: not possible. `BGTaskScheduler.submit` fails on a simulator with `BGTaskSchedulerErrorDomain` code 1 (unavailable). Measured through lldb on the running app. With no scheduled request, `_simulateLaunchForTaskWithIdentifier:` answers "No task request with identifier app.storyarc.sync has been scheduled". The installed app does carry `UIBackgroundModes` `fetch` and the permitted identifier `app.storyarc.sync`. This needs a real iPhone (device checklist line added).
- 5.3, the conflict notice: the runner drops the conflicts that a sync returns (worker note 6), so no notice exists to photograph. Not taken.
- Largest text: not taken, by the owner rule of 2026-10-08.
- A true second device reading the same share or folder: not available.

## Product findings

- The other libraries in the list stay "Connecting" for more than 12 seconds after launch on this simulator, even when the share answers. It does not touch sync, but it shows on every frame of the section.
- A first-time picker opens at On My iPhone (not inside the StoryArc folder). A reader who taps Open there chooses the whole of On My iPhone ("File Provider Storage" in the Place row). This happened once in the dark run. The app accepts it without a word. Choosing the app's own Documents folder, which is also the library folder, is accepted the same way (Place reads "Documents"), and the sync file then lands among the books. Android refuses a folder that already is a library; iOS has no such refusal (reviewer note 4).
