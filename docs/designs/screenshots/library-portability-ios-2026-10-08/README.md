# library-portability, iOS frames, 2026-10-08

Device: iPhone 17 Pro Max simulator, iOS 26.4 (EC086B47-A976-4DC4-B206-194D8E46EC3F).
Branch wave-3. Light, dark, and the largest text size (`-ax5`) where a layout can wrap.

Tasks proved: library-portability 4.2 and 5.5, and the iOS screens of 2.4, 2.5, 3.1, 5.3 and 5.4.

## Frames

| Frame | What it proves |
| --- | --- |
| `ios-transfer-section-sources` (+ dark, ax5) | Settings > Your libraries holds "Export library", "Import library" and the footer sentence. |
| `ios-export-sheet-off` (+ dark, ax5) | The export sheet says what the file holds, what it is not (task 2.4), and shows "Include passwords" off with its warning. |
| `ios-export-passwords-empty` (+ dark) | Switch on: two masked fields, Export disabled while they are empty. |
| `ios-export-passphrases-differ` (+ dark) | Two different passphrases: the mismatch is stated, Export stays disabled. |
| `ios-import-preview`, `-scrolled` (+ dark, ax5) | The preview of a file of another library states what the import will do and changes nothing. |
| `ios-import-preview-pins` (+ dark, ax5) | The pin section comes first ("Changes what this app trusts"), then libraries to add. |
| `ios-import-preview-merge` (+ dark) | Libraries that ask for a sign-in, merged shelves with "Gains N titles", positions and settings. |
| `ios-import-passphrase` (+ dark) | A file with passwords asks for the passphrase and offers "Import without passwords" (task 5.4). |
| `ios-import-passphrase-wrong` (+ dark) | A wrong passphrase is stated and the reader can try again (task 5.4). |
| `ios-import-refused-newer` (+ dark, ax5) | A file with formatVersion 9 is refused by name. Nothing changes. |
| `ios-import-refused-not-a-library` (+ dark) | A JSON file that is not a library file is refused. |
| `ios-import-result-done` (+ dark) | The result sheet after a merge ("Library imported"). |
| `ios-import-result-sign-in` (+ dark, ax5) | The result sheet lists the libraries that still ask for a sign-in. The imported settings set the language to French, so the sheet shows French strings. |
| `ios-imported-source-sign-in` (+ dark, ax5), `-sheet` (+ dark) | An imported source with no stored secret reads "Needs sign-in" and offers "Sign in again" (task 4.2). |

## How to repeat

1. `cd apps/ios && xcodegen generate && xcodebuild build-for-testing -project StoryArc.xcodeproj -scheme StoryArc -destination 'platform=iOS Simulator,id=<id>' -derivedDataPath ../../.build/ios-ui -quiet`
2. `node scripts/install-and-seed-simulator.mjs <id>`
3. Copy the import test files into the app container's `Documents` folder. The app shares `Documents` with Files (`UIFileSharingEnabled`), so the picker lists them under On My iPhone > StoryArc. The files were `other-library.json` (a document written by Android), `with-passwords.json` (secrets sealed under a passphrase), a copy with `formatVersion` 9, and `{"hello":"world"}`.
4. Drive Settings > Your libraries by hand. Set the look with `xcrun simctl ui <id> appearance light|dark` and `xcrun simctl ui <id> content_size accessibility-extra-extra-extra-large`.

The walk was driven by hand through the simulator, not by a UI test. The system picker runs in another process.

## Not framed

- The result sheet with one conflict and with several conflicts. The merge found no conflict on iOS: the import of a file with a position on both devices wrote "Library imported" and no conflict section. See the report: the conflict section may be unreachable from an import on iOS.
- The export sheet after a failed write. It is hard to reach. The task marks it optional.
- Export with the switch on and a matching passphrase pair. Not framed. The file written with the switch off was read back instead (below).

## Emulator proof for task 2.5 (export, then read the file back)

Export on the simulator wrote `Documents/StoryArc library 2026-10-08.json` through the system save picker (On My iPhone > StoryArc). The file decodes as JSON with `formatVersion` 1, `writtenBy` "ios", no `secrets` key (the switch was off), and these counts: 6 sources, 12 progress records, 3 certificate pins, 2 reading themes, 1 collection, 1 chosen cover. The app wrote no other file.
