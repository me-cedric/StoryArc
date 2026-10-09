# Playback proofs, iOS, 2026-10-09

Tasks: read-aloud-beyond-the-reader 0.1, 2.3 and 4.3. audiobooks-and-playback 4.5, 13.3 and 15.6.

Device: iPhone Air simulator (iOS 26.4), default text size, light and dark. A frame with the suffix `-dark` is dark. Simulator answers are simulator-only: the session state is read, not the sound.

## Frames

| Frame | Task | What it proves |
| --- | --- | --- |
| `ios-voice-running-reader-closed` | 0.1 | The reader is closed. The compact bar sits above the tab bar and offers Pause. Four seconds earlier it offered Pause and named the same book. |
| `ios-shell-home-no-session`, `-library-`, `-downloads-`, `-search-` | 2.3 | Each destination with no session. No bar. No empty capsule above the tab bar. |
| `ios-shell-home-session`, `-library-`, `-downloads-`, `-search-` | 2.3 | The same four destinations with a read-aloud session. The bar sits above the tab bar. |
| `ios-chapter-list-marks` | 15.6 | Sea Room chapter list: One finished, Two in progress, Three not reached. |
| `ios-full-player-embedded-cover` | 4.5 | Full player over an M4B with an embedded cover. The artwork is the cover, not the headphones well. |
| `ios-voice-end-reader` | 4.3 | One Sentence, the moment the voice stops: the page shows the sentence with no decoration and no controls. |
| `ios-voice-end-shelf` | 4.3 | The Library after the voice ended: no bar and no empty slot above the tab bar. |
| `ios-audiobook-reopened` | 13.3 | The player after a kill and a relaunch, in chapter Two at 0:01. |

Every `-dark` twin is the same walk in the dark appearance. `ios-audiobook-reopened` is light only (optional in the task).

## What the tests assert

- `ReadAloudShellTests/testTheVoiceCarriesOnAfterTheReaderCloses` (0.1). Starts the voice, closes the reader without pausing, and asserts Pause on the bar at once and after four seconds, with the same title. Mutation: pausing the bar before the first read fails it with "the bar offers no Pause".
- `ReadAloudShellTests/testTheShellReservesNothingWithoutASession` (2.3). Takes the tab bar frame of each destination before any session. Starts a session and photographs. Stops it. Asserts no bar control, no wide 48 pt slot above the tab bar, and the same tab bar frame as before. Mutation: `tabViewBottomAccessory(isEnabled: true)` fails it with "Home holds an empty slot above the tab bar". The tab bar frame alone passed that mutation, so the slot check was added.
- `PlayerScreenshotTests/testCaptureChapterListMarks` (15.6). Reads the label of each row. Asserts "Finished" on row one, "In progress" on row two and no mark on row three. The spoken rows are `Finished, One`, `In progress, Two, 1 second left` and `Three`. Mutation: swapping the two words in `PlayerSheets.mark(_:)` fails it with the row labels printed.
- `AudiobookResumeTests/testAnAudiobookReopensAtTheSavedPart` (13.3). Chooses chapter Two at 0.5x, pauses, kills the app, relaunches, opens the same book and reads the chapter marked in progress. Before the kill: part 2 (Two). After the relaunch: part 2 (Two), 0:01. Mutation: `resumePlace` returning nil fails it with "reopened at part 1".
- `PlayerScreenshotTests/testCaptureFullPlayerWithAnEmbeddedCover` (4.5). Photographs only.
- `ReadAloudShellTests/testTheEndOfThePublicationWithdrawsTheVoice` (4.3). Reads `One Sentence` (new fixture `one-sentence.epub`, copied into the simulator's `Documents/Corpus`) aloud with the reader open. Waits up to 60 s for the bar to go, photographs the page, closes the reader, and asserts no bar, no player entry and no empty slot on the shelf. The simulator voice ended in a few seconds. Mutation: reading `Harbour Lights 01` instead fails it with "The voice never reached the end of one sentence". The highlight is a web view decoration that XCUITest cannot read, so only the page frame shows it gone.

## Owed

- 2.5 (AX5 frames). The owner ruled on 2026-10-08 that no frame is taken at another text size. Nothing was taken.

## Notes

- The destinations are Home, Library, Downloads and Search. The task text says Settings. The shell has no Settings tab.
- 4.5 uses `With Cover Long.m4b`: the fixture `with-cover.m4b` looped to two minutes, cover atom kept. The fixture alone lasts two seconds and ends before a walk can pause it. The cover is a 2 x 3 pixel image, so it draws as a flat blue block.
- Both Sea Room walks end by choosing chapter One and pausing, so a run does not leave the six-second book near its end. Five alternating runs passed with that rule.
- 13.3 needs a book that was never marked finished. A finished mark is sticky, and a finished book restarts from zero. Reset with `xcrun simctl uninstall <id> com.mecedric.storyarc`, then repeat the steps below.
- The walk in `ReadAloudPlayerTests` pauses the voice before it leaves the reader. In two runs the bar still offered Pause afterwards, so that pause does not take. Its frames may show a running voice. This lane does not change it.

## How to repeat

```bash
cd apps/ios && xcodegen generate && xcodebuild build-for-testing -project StoryArc.xcodeproj -scheme StoryArc -destination 'platform=iOS Simulator,id=<id>' -derivedDataPath ../../.build/ios-ui -quiet
node scripts/install-and-seed-simulator.mjs <id>
node scripts/corpus.mjs --simulator <id>
# 4.5 only: put With Cover Long.m4b in the app's Documents/Corpus (ffmpeg -stream_loop 59 on with-cover.m4b)
node scripts/capture-ios.mjs --out <dir> --only ReadAloudShellTests --device <id> --appearance light|dark
node scripts/capture-ios.mjs --out <dir> --only PlayerScreenshotTests/testCaptureChapterListMarks --device <id> --appearance light|dark
node scripts/capture-ios.mjs --out <dir> --only PlayerScreenshotTests/testCaptureFullPlayerWithAnEmbeddedCover --device <id> --appearance light|dark
node scripts/capture-ios.mjs --out <dir> --only AudiobookResumeTests --device <id> --appearance light
```
