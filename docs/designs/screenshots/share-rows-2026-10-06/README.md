# Share rows catalogued from their headers, 2026-10-06

These frames come from task 14.13 (decision D28) of `close-the-audited-gaps`. They show one
shelf, drawn from one live SMB share, before and after that shelf reads each row's own
headers.

## The fixture

The share holds four files, chosen so that the name and the headers disagree three times out
of four. `scripts/smb-server.sh` serves them; the device reaches the Mac at `127.0.0.1` on the
iOS simulator and at `10.0.2.2` on the Android emulator.

| File on the share | Its source fixture | What the name claims | What its headers say |
| --- | --- | --- | --- |
| `Tidal Reach 04.cbr` | `comics/mislabelled-zip.cbr` | a RAR comic | a ZIP comic, three pages |
| `Salt and Iron 02.cbr` | `comics/rar4-solid.cbr` | a RAR comic that streams | a solid RAR4, which never opens |
| `Harbour Lights 03.cbr` | `comics/rar5-store.cbr` | a RAR comic | a stored RAR5, three pages |
| `Quiet Machines 02.cbz` | `comics/natural-sort.cbz` | a ZIP comic | a ZIP comic, agreeing |

**`Quiet Machines 02` is the control.** It is the one file whose name was telling the truth,
so a pair where every row changed would be a picture of something else going on.

## The frames

| Frame | What it shows |
| --- | --- |
| `ios-share-rows-before.png` | Every row as the file name made it. `Salt and Iron 02` captions its series line and offers to open. |
| `ios-share-rows.png` | The same shelf, catalogued. `Salt and Iron #2` now states "This comic uses solid compression…" before any tap, and `Tidal Reach` is a CBZ. |
| `ios-share-rows-dark.png` | The same, in dark appearance. |
| `android-share-rows-before.png` | Android, every row as the file name made it. |
| `android-share-rows.png` | Android, catalogued. The same refusal, the same detected format. |
| `android-share-rows-dark.png` | The same, dark. |

The titles change with the rest: a row built from a file name is titled with the file name,
and a catalogued one is titled the way every locally indexed publication already is —
`title(from:fallback:filename:)` on iOS and `title` on Android both build `Series #Number`
when the archive declares no title of its own.

## How to take them again

```bash
scripts/smb-server.sh <a folder holding the four files above> 4445
# iOS
node scripts/capture-ios.mjs --out <dir> --only ShareRowWalkTests --device "iPhone 17 Pro" --matrix
# Android
adb shell pm clear com.mecedric.storyarc.debug
node scripts/seed-android-sources.mjs --share
node scripts/capture-android.mjs "Library > share rows" --out <dir> --matrix
```

The "before" frames were taken from the same walks with `catalogueIfOnShare` returning the row
it was handed, which is the behaviour this task replaced.
