# Windows audio and speech spike: `MediaPlayer` and `SpeechSynthesizer`

**Task 4.18 of `desktop-clients`. Written 2026-10-17 on a Mac, from vendor documentation; no call
below has run on Windows.** Decision 5b of [`design.md`](../openspec/changes/desktop-clients/design.md)
names both engines as Assumed. This page is the design the Windows player and read-aloud code
(tasks 4.19 and 4.20) is written to, the calls it makes, and what a Windows host still has to
measure before the assumption is closed. Confidence labels follow ADR-0005: **Known** is read in
Microsoft Learn, **Inferred** is a consequence the text does not state, **Open** waits for the host.

## Exit criterion

The task's exit is the Linux spike's (4.12): a chapter plays, seeks and reports its position, and
a sentence speaks, or the gap is written down. On paper both engines meet it. The host walk at the
end of the waves runs the eleven measurements in the last section and records them here.

## Narrated audio: `Windows.Media.Playback.MediaPlayer`

| Need (from `audio-playback`) | Call | Confidence |
| --- | --- | --- |
| Play a file, a chapter of a file | `MediaPlayer.Source = MediaSource.CreateFromStorageFile(file)` or `CreateFromUri`; `Play()`, `Pause()` | Known |
| Position and duration | `PlaybackSession.Position`, `NaturalDuration`; `PositionChanged` fires about four times a second | Known |
| Seek | set `PlaybackSession.Position`; `CanSeek` says whether the source allows it | Known |
| Speed without a pitch change | `PlaybackSession.PlaybackRate`; `MediaPlayer.AudioCategory = MediaPlayback` keeps the pitch at a changed rate | Known (rate), Inferred (pitch: the category is documented as "preserves pitch" for speech and media playback) |
| Keep playing with every window hidden | A `MediaPlayer` owned by the app, not by a window; `AudioCategory.Media`; nothing ties playback to a visible element | Known |
| An M4B with chapter markers | `MediaPlaybackItem` exposes `TimedMetadataTracks`; chapter atoms arrive as a `ChapterCue` track (`TimedMetadataKind.Chapter`) | Known |
| A folder of files as one book | `MediaPlaybackList` of one item a file, `AutoRepeatEnabled = false`; `CurrentItemChanged` gives the part boundary | Known |
| Fade for the sleep timer | `MediaPlayer.Volume` 0 to 1, set every tick of the countdown | Known |
| Something else takes the audio | No interruption event exists on desktop. `Windows.Media.Audio.AudioStateMonitor.CreateForRenderMonitoring(MediaCategory.Media)` raises `SoundLevelChanged` with `Muted` or `Low` when the system ducks or silences the stream, and `Full` when it may resume | Known (the monitor), Inferred (that a desktop call or another player produces it) |
| Headphones removed | `Windows.Media.Devices.MediaDevice.DefaultAudioRenderDeviceChanged`; the app pauses when the default render device changes while playing and does not resume by itself | Inferred |
| Media keys and the system overlay | `MediaPlayer.CommandManager.IsEnabled = false`, then the app drives `MediaPlayer.SystemMediaTransportControls` itself (task 4.19) | Known |

**What the player code assumes.** One `MediaPlayer` for the process, made the first time something plays
and kept until quit. The `PlaybackModel` of `StoryArc.Interop.Playback` holds the session state the iOS
`PlaybackSession` holds (playing, paused by the listener, paused by an interruption), the speed, the
skip intervals and the sleep countdown, and the Windows code feeds it the engine's events. A
`SoundLevelChanged` to `Muted` is `Interrupted()`; back to `Full` is `InterruptionEnded(mayResume: true)`;
a pause the listener made is never undone this way (spec: "Something else takes the audio").

## Read aloud: `Windows.Media.SpeechSynthesis.SpeechSynthesizer`

| Need (from `ebook-reader`, Reading aloud) | Call | Confidence |
| --- | --- | --- |
| Is there a voice at all | `SpeechSynthesizer.AllVoices`; an empty list means the read-aloud control is absent and nothing says it failed | Known |
| Speak a sentence | `SynthesizeTextToStreamAsync(sentence)` gives a `SpeechSynthesisStream`; `MediaSource.CreateFromStream(stream, stream.ContentType)` on the same `MediaPlayer` | Known |
| Highlight the sentence being spoken | `Options.IncludeSentenceBoundaryMetadata = true` and `IncludeWordBoundaryMetadata`; the cues come as a `TimedMetadataTrack` of `SpeechCue` on the `MediaPlaybackItem` | Known |
| Speed | `Options.SpeakingRate`, 0.5 to 6.0, where 1.0 is the voice's own pace; the player's 0.5× to 3× maps onto it one to one | Known (range), Inferred (that 1.0 is what a listener hears as normal, as on iOS the default rate is) |
| The voice follows the language | `SpeechSynthesizer.Voice` set to a voice whose `Language` matches the publication's, else the default voice | Known |
| Carry on into the next chapter | The queue is the app's: the sentence list of the next reading-order item is extracted in the web view (the renderer's locator and the chapter text) and spoken in turn; speech is synthesised one sentence ahead | Inferred |
| End of the publication | The queue runs out: the session ends, the transport entry leaves (task 4.19) | Known |
| Audio taken | As for narrated audio: the same `MediaPlayer`, the same monitor | Inferred |

**Where the sentences come from.** The renderer (`apps/desktop-web/epub`) has no read-aloud
message yet; the Windows read-aloud model takes the sentences of the chapter being shown from
the chapter's text through the core's `storyarc_epub_resource` and a sentence split in C#, and
moves the renderer with a `go` to the sentence's locator when a sentence boundary falls on a
new page. That split is the part most likely to be replaced once the bundle gains a
`read-aloud` message shared by the three desktops.

## What the player code does not do, by decision

- No `MediaPlayerElement`: there is no video, and the element ties playback to a window.
- No `BackgroundMediaPlayer`: it is the Windows 8 model and is retired; a desktop app keeps playing while minimised without it.
- No `SpeechSynthesizer.SynthesizeSsmlToStreamAsync`: the publication's text is plain by the time the app sees it, and SSML would mean escaping it.

## What a Windows host still has to measure

1. `PlaybackRate` 0.5, 1.0, 2.0 and 3.0 on an M4B: is the pitch held at each, and is 3.0 accepted or clamped.
2. A seek across a chapter boundary in one M4B lands in the right chapter and `PositionChanged` reports it within a second.
3. A `MediaPlaybackList` over a folder of MP3s continues into the next file without a gap long enough to notice.
4. `AudioStateMonitor.SoundLevelChanged` fires when another player starts, when a Teams call rings, and when the system volume is muted; which of the three gives `Muted` and which `Low`.
5. `DefaultAudioRenderDeviceChanged` fires when a Bluetooth headset disconnects, and how long after.
6. `SpeechSynthesizer.AllVoices` on a clean Windows 11 24H2 install: which voices and languages are present, and whether the list is empty on a machine with speech features removed.
7. Sentence and word cues arrive on the `MediaPlaybackItem` and line up with the audio within 100 ms.
8. `SpeakingRate` 0.5 and 3.0 are audible and intelligible; whether 1.0 matches what Narrator calls its normal rate.
9. The German, French and Spanish voices pick up for a publication in that language with no English accent.
10. A sentence longer than 15 s synthesises without a timeout.
11. Playback continues with every window minimised and with the lock screen up, and the keys of the lock screen's media overlay move it (task 4.19).

Each row is recorded in this file with the date, the machine and the answer, and the Assumed label
on Decision 5b changes to Known or to a named gap.

Sources read on 2026-10-17: Microsoft Learn, `Windows.Media.Playback.MediaPlayer`, `MediaPlaybackSession`,
`MediaPlaybackItem.TimedMetadataTracks`, `MediaPlaybackList`, `Windows.Media.Audio.AudioStateMonitor`,
`Windows.Media.Devices.MediaDevice`, `Windows.Media.SpeechSynthesis.SpeechSynthesizer`,
`SpeechSynthesizerOptions`, and "Integrate with the System Media Transport Controls".
