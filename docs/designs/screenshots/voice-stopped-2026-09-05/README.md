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

## Android: nothing spoke, so nothing was displaced — fixed, and the word is on the page

Four frames across two routes showed no snackbar, before and after the duration was lengthened,
and a diagnostic found the speech engine connecting and no notification from the app. The cause
was upstream of the notice (`002fbdbd`): `ReadAloudHost.begin` launched its watcher over the
controller's session *before* calling `start`; on `Dispatchers.Main.immediate` the collector ran at
once, read the idle session the controller was born with as the session ending, and ran `finish` —
releasing the controller, cancelling its scope, abandoning audio focus it had not asked for yet.
`start` then posted its first sentence onto a cancelled scope. `logcat` showed the abandon two
milliseconds before the request; `dumpsys media_session` showed no session; `SpokenAudio.speaking`
was null. There was no voice to displace, on any route, which is also why the reader's transport
was missing from every earlier Android frame here.

The voice is started before it is watched, and `ReadAloudHostTest` drives the host over a fake
engine so the watcher-first order fails by name. `android-epub-reader-voice-stopped-light.png` is
the retake: *Harbour Lights 02* open over the voice, the snackbar reading *Stopped reading “Harbour
Lights 01” aloud.* at the foot of the page. The `Player > voice stopped` frame was not retaken
before this branch merged and is still owed; the same fix is what it needed.

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
