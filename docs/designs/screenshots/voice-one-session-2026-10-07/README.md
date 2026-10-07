# Read-aloud is one media session, 2026-10-07

Task 13.2 of `close-the-audited-gaps` (Android). The voice speaks through the one media3
session. The app has no second notification and no `ReadAloudService`.

Device: Android emulator `storyarc-ci`, API 35, 1080 x 2400. Book: `Harbour Lights 01.epub`,
read from a guest SMB share (`scripts/smb-server.sh`, port 4445).

| Frame | What it proves |
| --- | --- |
| `android-voice-shade-light.png` | One media card while the voice speaks: the book title, the chapter, Previous sentence, pause, Next sentence. |
| `android-voice-shade-dark.png` | The same card in the dark appearance. |
| `android-voice-reopen-light.png` | A tap on the card opens the reader at the spoken sentence (the shaded block, 1.4). The voice goes on. |

`adb shell dumpsys media_session` showed one app session in state `PLAYING`, with the custom
actions Previous sentence and Next sentence. `dumpsys notification` showed one app
notification, in `media3_group_key`.

## The car list

A car list needs the Desktop Head Unit, and no DHU runs here. The instrumented test
`PlayerBrowseTreeTest` ran on the emulator instead: 7 cases passed, among them
`aVoiceThatSpeaksIsTheFirstRow`.

## How to repeat

```bash
node scripts/seed-android-sources.mjs --share   # after a pm clear and one app launch
# in the app: Library > Harbour Lights 01 > Read > menu > Read aloud
adb shell cmd statusbar expand-notifications
adb shell cmd uimode night yes                  # then no, to put the device back
pnpm gradle :app:connectedDebugAndroidTest -Pandroid.testInstrumentationRunnerArguments.class=app.storyarc.PlayerBrowseTreeTest
```

## Not photographed

The lock screen was not photographed. The device check for an audiobook that plays while the
voice starts is in `device-checklist.md`.
