# The word a stopped voice owes — 2026-09-05 / 06

`ebook-reader`, *Opening a different publication*: "the listener is told once that the voice
stopped, rather than discovering it by silence". The rule is `VoiceStoppedNotice` on both
platforms; these are the frames of the word itself.

| Frame | Device | What it shows |
| --- | --- | --- |
| `ios-voice-stopped-in-reader.png` | iPhone 17 Pro | *The Long Field* opened over a voice reading *Harbour Lights 01*: the page, with *Stopped reading “Harbour Lights 01” aloud.* as a banner at its foot |
| `ios-voice-stopped-on-shelf.png` | iPhone 17 Pro | *The Peregrine* started over the same voice: the capsule at the top of the screen says the word while the dock below already names the new book |
| `android-epub-reader-voice-stopped-light.png` | `storyarc-j6` | The route's frame of *Harbour Lights 02* opened over the voice — **and the word is not on it**; see below |

Taken with `scripts/capture-ios.mjs` and the two `ReadAloudPlayerTests` walks (light), and
`scripts/capture-android.mjs "EPUB reader > voice stopped"`.

## iOS: the word is where the listener is looking

Two surfaces, one rule. A reader that displaced a voice takes the word itself and draws it over
its page (`VoiceStoppedBanner`); a displacement from the shelf — an audiobook started with no
screen to open — is drawn by the shell over whatever is there (`VoiceStoppedCapsule`, at the
top, because the foot is the dock that has just started saying the *new* book's name). Six
seconds, this app's dwell for transient chrome. The sentence names the book that went quiet.

**Getting these two frames found a defect that had nothing to do with the voice.** Both walks
failed for an evening with *"The page for Harbour Lights 01 offered no way to open it"*, and the
recordings showed the shelf not moving under the tap. The cover was fine; the Library split's
value links had had no destination since 2026-09-05 13:05, and no cover on the shelf opened
anything on any device. `docs/designs/screenshots/ios-pane-2026-09-06/README.md` has that story;
the walks passed on the first run after the fix.

## Android: the surfaces exist, the emulator has not shown the word

`EpubReaderOverlays` and `PlayerScreen` each collect `SpokenAudio.voiceStopped` with the
lifecycle, take the notice and show it as a snackbar; `VoiceStoppedWordTest` and
`SpokenAudioTest` pin the arming and the taking. Four device frames were taken across two
routes and none shows the snackbar. The Short duration was one cause — the surface composes
while the book is still being parsed, and four seconds were gone before the first page drew —
and both surfaces now use `SnackbarDuration.Long`; the frames retaken after that change still
show no word. A diagnostic run confirmed the speech engine connects when the voice is started,
and found no notification from the app, which points at the notification permission the route
answers with an optional `?=Allow` step. **Whether the voice was speaking at the moment the
second book opened is not established**, so neither is whether the displacement armed anything.
The one Android frame kept is the honest one: the route reaches the page and the word is not on
it. The Android half of this scenario's proof is still owed, and the place to look first is
whether `ReadAloudHost.speaking` is set before the route presses Back.

## How to retake them

```bash
O=docs/designs/screenshots/voice-stopped-2026-09-05
node scripts/capture-ios.mjs --out $O --only ReadAloudPlayerTests/testCaptureVoiceStoppedByAnotherBook --appearance light
node scripts/capture-ios.mjs --out $O --only ReadAloudPlayerTests/testCaptureVoiceStoppedByAnAudiobook --appearance light
node scripts/capture-android.mjs "EPUB reader > voice stopped" --out $O/android-epub-reader-voice-stopped-light.png
node scripts/capture-android.mjs "Player > voice stopped" --out $O/android-player-voice-stopped-light.png
```

The iOS walks filter the shelf to EPUBs and audiobooks so every book they name sits in the first
two rows; read the run summary, not the exit code.
