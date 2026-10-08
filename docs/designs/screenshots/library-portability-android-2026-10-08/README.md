# Library export and import, Android, 2026-10-08

Visual proof for `library-portability` tasks 4.2 (export sheet, import preview, a source that needs a sign-in) and 5.5 (the "Include passwords" switch with its warning, and the import passphrase prompt). The iOS half is in `../library-portability-ios-2026-10-08/`.

Device: emulator `storyarc-ci` (API 35, google_apis, arm64), headless. Debug build `com.mecedric.storyarc.debug` at commit `62eba386`. Way in: Library > More > Settings > Your libraries. The transfer rows sit below "Add a library".

Variants: no suffix is light at the default text size. `-dark` is dark. `-ax` is light at font scale 2.0. `-dark-ax` is dark at font scale 2.0.

## Frames

| Frames | What they prove |
| --- | --- |
| `android-transfer-section*` | The "Export library" and "Import library" rows and the sentence under them. |
| `android-export-sheet*` | Task 4.2. The export sheet states what the file holds and what it does not hold. "Include passwords" is off. |
| `android-export-passwords-empty*` | Task 5.5. With the switch on, the warning "Anyone who has the file and the passphrase can sign in to these servers", two passphrase fields, the hint "Enter a passphrase.", and Export disabled. `android-export-passwords-scrolled-ax` and `-dark-ax` show the fields at the largest text. |
| `android-export-passphrases-differ*` | Task 5.5. Two different passphrases: "The two passphrases do not match." and Export disabled. |
| `android-import-preview*`, `android-import-preview-scrolled-ax` | Task 4.2. The import preview of a file from another library. The pin section comes first with a warning icon and "Changes what this app trusts". Then libraries to add, libraries that ask for a sign-in, shelves, merged shelves ("Gains 3 titles"), positions, themes, covers and settings. |
| `android-import-passphrase*` | Task 5.5. A file exported with passwords. The preview ends with the passphrase field and "Import without passwords". Import is disabled until a passphrase is typed. |
| `android-import-passphrase-wrong*` | Task 5.5. After a wrong passphrase: "That passphrase did not open the passwords. Try again, or import without them." |
| `android-import-refused-newer*` (light, dark) | A file with `formatVersion` 9 is refused: "This file cannot be imported". Nothing changed. |
| `android-import-refused-not-a-library*` (light, dark) | A JSON file that is not a library file is refused. |
| `android-import-result-sign-in*` (light, dark) | The result sheet lists the libraries that still ask for a sign-in. |
| `android-import-result-conflict-one*` | One conflict: "Both devices had moved on in one title. The further position was kept (Page 31 of 40). Set aside: Page 13 of 40." The `-ax` frames show the full sentence. |
| `android-import-result-conflict-many*` (light, dark) | Several conflicts: the count, "Show", and one line per conflict. The lines do not name the titles. The reviewer reported this. |
| `android-imported-source-sign-in*` | Task 4.2. An imported source with no stored secret ("Loft Kavita") shows "Needs sign-in" and the action "Sign in again". |
| `android-imported-source-sign-in-sheet*` (light, dark) | "Sign in again" opens the Kavita sheet with the address filled and the API key empty. |

## Emulator proof for task 2.5 (export, then read the file back)

On the emulator, "Export library" and the system save picker wrote `Download/StoryArc library 2026-10-08 (2).json` (24131 bytes). I pulled it and decoded it as JSON. `formatVersion` is 1, `writtenBy` is `android`, and `secrets` is null (the switch was off). The library holds 7 sources, 3 certificate pins, 1 collection, 2 reading lists, 2 pinned shelves, 10 settings, 2 reading themes, 11 progress records and 2 covers. The file holds no API key and no password.

## Owed or not framed

- The export sheet after a failed write. It is hard to reach. The reviewer marked the frame optional.
- The screen "The sign-in is no longer stored" when the imported source is opened from the Library. I found no way into it from the Library on this device. The Settings way is framed.
- Largest text for the refusal sheets, `android-import-result-sign-in` and `android-import-result-conflict-many`. The sheets are short and do not wrap in the default frames.

## Fixtures

`fixtures/` holds the files the walk imports. They are fake data. Push them with `adb push fixtures/*.json /sdcard/Download/`.

| File | Use |
| --- | --- |
| `other-library.json` | Import preview. Written by Android, no secrets. |
| `sealed-library.json` | Import with a passphrase. The passphrase was not recorded. Any other value gives the wrong-passphrase frames. |
| `newer-format.json` | `formatVersion` 9. |
| `not-a-library.json` | Not a library file. |
| `conflict-one.json` | One position that conflicts. Needs the row for `/a.cbz` in `progress.db` at page 13 of 40 before each import. |
| `conflict-many.json` | Three positions that conflict. |
| `result-sign-in.json` | Sources with no secret. |

## How to repeat

1. `pnpm build:android` and `adb install -r`. Push the fixtures.
2. `pnpm capture:android "Transfer > export sheet" --out f.png [--dark] [--font-scale 2.0]`. The other routes start with `Transfer >` and `Settings > imported source`.
3. For the conflict frames at the largest text, run `Transfer > import conflict one expanded`. Reset the progress row first: `adb shell run-as com.mecedric.storyarc.debug sqlite3 databases/progress.db "update progress set page_index=12, progression=0.3076923076923077, updated_at=1791460000000 where id=6"`.
4. For the export proof: run `Transfer > export sheet`, tap Export, then tap Save in the system picker. Then `adb pull` the file.
