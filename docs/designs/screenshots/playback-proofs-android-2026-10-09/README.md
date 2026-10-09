# Playback proofs, Android, 2026-10-09

Tasks: read-aloud-beyond-the-reader 0.2, 3.1, 3.2, 4.1 and 4.3. audiobooks-and-playback 3.9, 4.5, 6.1 and 15.6. The iOS half is in `../playback-proofs-ios-2026-10-09/`.

Device: emulator `Pixel_9_Pro_XL` (Android 16, API 36.1, Google Play image, arm64), headless, 1344 x 2992, default text size. Debug build `com.mecedric.storyarc.debug`. Frames with the suffix `-dark` are dark. The device was put back to light.

## Limit of this emulator

Google speech synthesis crashes on this image: `signal 4 (SIGILL)` in `libgoogle_speech_sbg_tts_jni.so`, process `com.google.android.tts`. A read-aloud session starts and shows as PLAYING, but no sentence is spoken and no sentence ends. Everything below is a session fact (media session, notification, audio focus, back stack). No frame shows a moving sentence or a highlight, and no sound was made. The device checklist keeps the audible half.

## Frames

| Frame | Task | What it proves |
| --- | --- | --- |
| `android-voice-library-reader-gone`, `-dark` | 0.2 | The reader is closed. The Library shows the compact bar "Harbour Lights 01, Chapter 1" with Pause. |
| `android-voice-shade-speaking-foreground`, `-dark` | 0.2, 3.1 | The shade over the Library: one media card, "Harbour Lights 01", Pause, Previous and Next sentence. |
| `android-voice-shade-paused-foreground` | 3.1 | The same card paused. |
| `android-voice-shade-speaking-background`, `android-voice-shade-paused-background` | 3.1 | The app on the launcher. The card is the same, speaking and paused. |
| `android-voice-lockscreen-speaking` | 3.1 | The lock screen while the voice runs: the card and its controls. |
| `android-voice-shade-notifications-refused` | 3.1 | POST_NOTIFICATIONS refused. The shade still shows the media card. |
| `android-voice-lockscreen-notifications-refused` | 3.1 | POST_NOTIFICATIONS refused. The lock screen still has the controls. |
| `android-voice-tap-reader-closed-lands` | 3.2 | A tap on the card with the reader closed opens the reader on chapter one. No shaded sentence is visible (see the limit above). |
| `android-voice-tap-reader-open-lands` | 3.2 | A tap with the reader open rebuilds the reader the same way. |
| `android-voice-tap-back-shows-library` | 3.2 | One Back press after the tap shows Home, not the Library. |
| `android-voice-end-reader-after-stop`, `-dark` | 4.3 | One Sentence, after the last sentence: no controls, no shaded sentence. |
| `android-voice-end-shade-no-notification`, `-dark` | 4.3 | The shade after the end: no media card. |
| `android-chapter-list-marks`, `-dark` | 15.6 | Sea Room: One "Finished", Two "Playing", Three with no mark. |
| `android-player-embedded-cover`, `-dark` | 4.5 | The player over `With Cover Long.m4b`: the embedded cover, not the headphones well. |

## Emulator proofs

### 0.2, voice after the reader activity ends

Start read-aloud in Harbour Lights 01, press Back until the reader finishes, stay in the app. `dumpsys media_session`: one session, `state=PLAYING`, custom actions Previous sentence and Next sentence. `dumpsys notification`: one app notification, flags `ONLY_ALERT_ONCE|NO_CLEAR|FOREGROUND_SERVICE`. `dumpsys audio`: the focus owner is the app (`ReadAloudController`). The session stayed PLAYING after Back, after the app went to the launcher, and after the screen lock.

### 3.1, notification states

The paused card has the same title. After a pause the session is `PAUSED` with position 0 and speed 0. With POST_NOTIFICATIONS refused (`pm revoke`, then "Don't allow" in the dialog) the session is still PLAYING, the shade still shows the media card, and the lock screen keeps its controls.

### 3.2, tap on the card

- Reader closed: the card opens `EpubReaderActivity`. The task has two activities: `MainActivityInk` (the launcher entry, root) under `EpubReaderActivity`.
- Reader open: same stack. The reader is rebuilt, as the code says.
- One Back press shows Home. The listener was on the Library. `TaskStackBuilder` clears the task and rebuilds from the launch destination, so any other screen the listener had open is lost. This is the consequence the task named.

### 4.1, a call takes the audio and gives it back

`adb emu gsm call 5551234` while the voice runs: the session goes `PAUSED`, and `com.android.server.telecom` holds `GAIN_TRANSIENT`. `adb emu gsm cancel 5551234`: the session goes `PLAYING` again. With the voice paused by the listener, a call and its end leave it `PAUSED`.

`VoiceFocusInstrumentedTest` on this emulator: `aCallEndingDoesNotUndoAListenersPause` passes. `aCallEndingResumesTheVoice` fails in two runs of two: "the call ended and the voice stayed silent". The test asks for focus from the same uid, and the manual call path above resumes. The cause is not isolated.

### 4.3, end of the publication

`one-sentence.epub` (new fixture) read aloud. The engine never finishes a sentence here, so the end was reached with Next sentence on the last sentence. The same stop path ran: session `NONE`, no app notification, no focus owner, no controls on the page, no media card in the shade. The natural end (the engine reporting the last utterance done) is not proved here.

### 3.9, route change

`adb shell am broadcast -a android.media.AUDIO_BECOMING_NOISY` is refused: `SecurityException: Permission Denial ... uid=2000`. This image is a production build and `adb root` is refused. The proof needs a userdebug image. Not done.

### 6.1, the eight steps

Book: `With Cover Long.m4b` (two minutes), `Sea Room.m4b` (six seconds), `Harbour Lights 01.epub`.

1. Open the audiobook, press Listen. One session PLAYING ("With Cover Long"), one app notification, focus owner the app.
2. Back to the shelf. The compact bar carries the book. The session stays PLAYING.
3. Open the EPUB. The session goes `NONE`, the notification goes, the focus owner goes.
4. Menu, Read aloud. One session PLAYING ("Harbour Lights 01"), one notification, one focus owner. `dumpsys audio` shows no started player of the app (the engine makes no track here).
5. Reopen the audiobook. One session ("With Cover Long"), one notification, one focus owner. The voice is gone. The audiobook started at 2.8 s, not where it was displaced (see the defects).
6. Leave the player, tap Continue listening on the same cover. Position 48.0 s at uptime 2100.5 s, then 60.1 s at 2112.6 s. No restart, no jump.
7. Sea Room played to its end: session `NONE`, no notification, no bar, "Nothing is playing." Then With Cover Long started and `cmd media_session dispatch pause` paused that book (the shade transport drives the new book).
8. Audiobook playing, `gsm call`: the audiobook goes `PAUSED`. While the call rings, open the EPUB and press Read aloud: the audiobook session ends, and no voice starts (the call holds the audio focus). After the call ends nothing speaks and the audiobook does not come back. Read aloud pressed again starts the voice (one session).

### 15.6 and 4.5

The row words come from a `uiautomator` read of the chapter list: "One", "Finished"; "Two", "Playing"; "Three" with no mark. `PlayerSemanticsTest` already asserts the word on each row (three cases). Swapping the two marks in `chapterMark` fails three of its 19 cases by name. The largest-text frame is not taken (owner rule of 2026-10-08).

## Defects found, not fixed

1. A book displaced by another source restarts at the start. With Cover Long was at 36 s when the EPUB opened and at about 75 s when Sea Room started. Both times Continue listening began at 2 to 3 s. A book paused by the listener resumes correctly. The position of a displaced book is not kept (step 5 and step 7).
2. Back after a notification tap lands on Home, not on the screen the listener left (3.2).
3. `aCallEndingResumesTheVoice` fails on API 36.1 (4.1), cause not isolated.
4. Google speech synthesis crashes with SIGILL on this image. This is a limit of the image, not of the app.

## How to repeat

```bash
node scripts/corpus.mjs <dir>                       # the corpus, then add With Cover Long.m4b and one-sentence.epub
adb push <dir>/Sea Room.m4b, Harbour Lights 01.epub, With Cover Long.m4b to /sdcard/Android/data/com.mecedric.storyarc.debug/files/
pnpm build:android && adb install -r apps/android/app/build/outputs/apk/debug/app-debug.apk
node scripts/capture-android.mjs "Player > chapter marks" --out <file>.png [--dark]
node scripts/capture-android.mjs "Player > embedded cover" --out <file>.png [--dark]
adb shell cmd statusbar expand-notifications        # then screencap; collapse after
adb emu gsm call 5551234 ; adb emu gsm cancel 5551234
```

`With Cover Long.m4b` is `with-cover.m4b` looped to two minutes: `ffmpeg -stream_loop 59 -i with-cover.m4b -i with-cover.m4b -map 0:a -map 1:v -c copy -disposition:v attached_pic -f ipod out.m4b`. The fixture alone lasts two seconds. `scripts/seed-android-sources.mjs` now falls back to `run-as` when `adb root` is refused.
