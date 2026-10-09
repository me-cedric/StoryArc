# Sync places, Android, wave 5 - 2026-10-09

Device: emulator `storyarc-ci` (1080x2400 at 420 dpi), started headless with `-memory 2048`.
Debug build `com.mecedric.storyarc.debug` from the head of `wave-5` (`8c126ef96`). Default text size.
Dark frames end in `-dark`. A frame with no dark twin is light only, and the table says so.

Proves `library-sync` 5.3 (Android half), 2.1, 2.2, 2.3, 2.4, 4.3 (emulator proofs).
The conflict notice is owed (see Owed).

Fixtures: `node scripts/corpus.mjs /tmp/sa-corpus`, pushed into
`/sdcard/Android/data/com.mecedric.storyarc.debug/files/`. Writable Samba shares:
`scripts/smb-server.sh --writable /tmp/sa-corpus` (4448) and
`scripts/smb-server.sh --writable --encrypted /tmp/sa-corpus` (4449, `smb encrypt = required`).
All frames of the share place come from 4449 except `sync-2` and `sync-3` (4448, same display name)
and `sync-9` (4448).

## Frames

| Frame | What it proves |
| --- | --- |
| `sync-1-off-no-share*.png` | Settings > Your libraries, Sync section, off, no share added: the about sentence, "Choose a folder", the every-device sentence and the Android 15-minute sentence. "Use a shared folder" is absent because no share exists. |
| `sync-2-off-share-offered*.png` | Same, with one share added: "Use a shared folder" appears above "Choose a folder". |
| `sync-3-choose-share*.png` | "Use a shared folder" opened: the menu lists the added share. The menu covers the "Choose a folder" row while it is open. |
| `sync-4-synced*.png` | Sync on, place `10.0.2.2/Sync`, grey line "Synced at 2:31 PM", "Sync now", "Turn off sync". The document is on the share. |
| `sync-5-unreachable*.png` | The share server is stopped and "Sync now" is tapped: grey words "10.0.2.2/Sync cannot be reached. StoryArc syncs again when it can reach it." No red, no error dialog. The source row reads "Not answering". |
| `sync-6-library-while-unreachable.png` | Same moment, the Library tab (light only): the shelf is intact. The place never blocks the library. |
| `sync-7-recovered.png` | The server is back: "Synced at 2:35 PM". Light only. |
| `sync-8a-refused-not-a-library*.png` | The share holds a text file under the sync name: "The sync file is not a StoryArc library. Nothing was changed." The file on the share stayed as written. |
| `sync-8b-refused-newer*.png` | The share holds a document with `formatVersion` 999: "The sync file comes from a newer version of StoryArc. Update StoryArc on this device. Nothing was changed." |
| `sync-9-merged-with-ios-rows.png` | Light only. Port 4448 was shared with the iOS frames agent. The document that the iOS simulator wrote reached the emulator: the source list holds the iOS rows `Silent NAS` and `127.0.0.1/Sync`. This is the cross-platform path working on real devices of both kinds. It is not a clean frame of the Android section. |
| `sync-10-off-after-turn-off.png` | "Turn off sync" returns the section to the off state. Light only. |
| `sync-11a-folder-picker-system.png`, `sync-11b-folder-allow-system.png` | "Choose a folder" opens the system picker; the Documents folder; the system "Allow StoryArc to access files in Documents?" dialog. System screens, light only. |
| `sync-12-folder-chosen.png` | The folder is the place ("Documents") and the first sync wrote the file. Light only. |
| `sync-13-folder-after-relaunch.png` | After `am force-stop`, the place is still "Documents" and "Synced at" shows. Light only. |
| `sync-14-folder-is-a-library-refused*.png` | A folder that already is a library is refused: "This folder is one of your libraries. Choose another folder for sync." |

## Emulator proofs (what was watched)

- **2.2 write, read back, overwrite, unreachable.** Share on 4449 (encrypted). First sync wrote
  `StoryArc Library.json` (`writtenAt` 12:31:45Z). A second sync rewrote it (12:33:43Z). The server was
  stopped: the line turned to the grey unreachable sentence and the Library stayed usable. The server was
  restarted: "Synced at" returned. On 4448 (signed, not encrypted) the first sync also wrote and merged.
- **2.3 folder across a relaunch.** Documents picked through the system picker.
  `dumpsys activity permissions` showed `persisted=0x3` (read and write). After `am force-stop` and a new
  launch the grant was unchanged and the next sync changed the file time (14:40 to 14:41), and `writtenAt`
  moved to 12:41:49Z.
- **4.3 background job.** `dumpsys jobscheduler` lists job 1398361667 for `LibrarySyncJobService`:
  periodic, 15 minutes, network required. `adb shell cmd jobscheduler run -f com.mecedric.storyarc.debug 1398361667`
  ("Running job [FORCED]") moved `writtenAt` from 12:35:51Z to 12:38:39Z. The natural wake-up was not watched.

## Owed

- **The conflict notice (5.3).** The runner drops the conflicts that a sync returns, so the app never draws
  one. There is nothing to photograph. Needs a product change first.
- **A clean frame of two devices at rest.** `sync-9` has the iOS rows because 4448 was shared.
- **French, German and Spanish frames.** Not taken. Only the default text size and English were asked.
- **iOS frames** belong to the frames-ios lane.

## Defects found (not fixed)

1. The source row of the sync share reads "Connecting - 0 titles" for the first seconds after a place is
   chosen, and the frame `sync-7` shows it beside "Synced at". Cosmetic and short.
2. A sync adds the iOS-only source rows (`sync-9`): `Silent NAS` and `127.0.0.1/Sync` appear on the
   emulator, where `127.0.0.1` is the emulator itself. A source that came from another device and cannot work
   here is listed as a library with no mark that it came from elsewhere.

## Repeat

```bash
export PATH=$HOME/Library/Android/sdk/platform-tools:$PATH ANDROID_SERIAL=emulator-5554
node scripts/corpus.mjs /tmp/sa-corpus
scripts/smb-server.sh --writable --encrypted /tmp/sa-corpus      # 4449
adb shell pm clear com.mecedric.storyarc.debug
pnpm capture:android "Sources > add share sync" --out f.png     # adds the share; each run adds one
pnpm capture:android "Settings > Sync choose share" --out f.png [--dark]
pnpm capture:android "Settings > Sync on" --out f.png [--dark]   # chooses the share, first sync
pnpm capture:android "Settings > Sync now" --out f.png [--dark]  # taps Sync now, then draws the line
pnpm capture:android "Settings > Sync section" --out f.png --dark
pnpm capture:android "Settings > Sync turn off" --out f.png
pnpm capture:android "Settings > Sync pick folder" --out f.png   # opens the system picker; tap by hand
```

Refusals: write a text file, or the good document with `formatVersion` 999, to
`$TMPDIR/storyarc-smb-4449/sync/StoryArc Library.json`, then "Settings > Sync now".
Unreachable: `pkill -f storyarc-smb-4449/smb.conf`, then "Settings > Sync now".
