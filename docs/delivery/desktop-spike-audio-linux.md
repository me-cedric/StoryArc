# Desktop audio and speech on Linux: GStreamer and speech-dispatcher

**Task 4.12 of `desktop-clients`, lane L. Run on 2026-10-17 in the Ubuntu 24.04 container of
`container-build.sh` (arm64, GTK 4.14.5, GStreamer 1.24.2, speech-dispatcher 0.12 with espeak-ng)
under cage, with no sound device.** Confidence labels follow ADR-0005. Every row marked **Proven**
was run by a test named here; the command is at the end.

The question, from [`design.md`](../openspec/changes/desktop-clients/design.md) Decision 5b, which
assumed both engines: does GStreamer play, seek and report a chapter, and does speech-dispatcher
speak a sentence, on the floor the Linux app targets. The exit the task set: a chapter plays, seeks
and reports its position, and a sentence speaks, or the gap is written down.

## Choices

| Part | Choice | Why |
| --- | --- | --- |
| Playback | `gstreamer` 0.25.4 and `gstreamer-play` 0.25.0 (MIT OR Apache-2.0): `GstPlay` over playbin, in `apps/desktop-linux/src/audio.rs` | GstPlay carries play, pause, seek, rate, position and duration and reports them on a bus; it needs GStreamer 1.20 and Ubuntu 24.04 ships 1.24. Same `glib` 0.22 as `gtk4` 0.11. |
| Speech | SSIP over the speech-dispatcher socket, a small client in `apps/desktop-linux/src/speech.rs`, no crate | The protocol is a few text lines; libspeechd would add a C dependency for the same four calls. The client spawns the daemon the way libspeechd does when the socket is absent. |
| Controls | GDBus, in `apps/desktop-linux/src/mpris.rs` (task 4.13) | GTK already carries it; no `zbus` in the app. |

## What ran

| Case | Result | Evidence |
| --- | --- | --- |
| A chapter plays | **Proven** | `audio::tests::a_chapter_plays_seeks_and_reports_its_position_on_a_null_sink`: `id3-chapters.mp3` (three two-second chapters) reaches `Playing` on a `fakesink` that keeps the clock; the duration reads 6 s. |
| It seeks | **Proven** | The same test seeks to 2.5 s, into chapter Two, and the position reads 2.4 s or more within five seconds. |
| It reports its position | **Proven** | `PlayerEvent::Position` arrives on the GLib main loop; a pause holds the position. The rate takes 1.5. |
| The MP3 decoder is found before a file is offered | **Proven** | `AudioPlayer::can_decode` asks the registry for `mpg123audiodec`; the app refuses a file by name when the decoder is missing rather than failing in the pipeline. |
| A sentence speaks | **Proven, to BEGIN** | `speech::tests::a_sentence_speaks_or_the_gap_is_named`: the daemon answers `230 OK RECEIVING DATA`, queues the message, lists 13,362 synthesis voices (every espeak-ng variant), and sends `701 BEGIN` for the message. |
| The sentence ends | **Proven, on a null output** | With the daemon's default audio output and no sound device, `702 END` never arrived within the ten-second read timeout: the module waits on an output that does not finish. With `AudioOutputMethod "libao"` and libao's `null` driver, which `headless-proof.sh` writes into the walk's `HOME`, `702 END` arrived for the message, so the engine runs a sentence from BEGIN to END. |
| The rate is taken | **Proven** | `SET SELF RATE 10` answers OK. |

The engine's state, position and duration reach the window and the controls from one place
(`audio.rs`), so the mini player and MPRIS never disagree.

## The gap, written down

1. **Speech output on a host with no sound device.** speech-dispatcher's modules write to an audio
   output and report END only when it finishes. The container has none, so the daemon's default
   output never finished and END came only through libao's null driver. A desktop has PipeWire or
   PulseAudio, which is the daemon's default; a real session owes hearing the sentence and the
   pause and resume of one (`PAUSE SELF`, `RESUME SELF`, which answer OK here but cannot be heard).
2. **Chapter marks.** The design keeps chapter parsing in the core, and the core has no audiobook
   chapter reader yet (ID3 `CHAP` frames, the MP4 `chpl` atom). GStreamer exposes them as a TOC,
   which `GstDiscoverer` reads, but reading them there would put publication parsing in the app.
   Until the core reads them, the Linux player's Next and Previous step through a folder's parts and
   a one-file audiobook has none; the mini player shows no chapter list.
3. **Embedded covers.** The ID3 `APIC` frame and the MP4 `covr` atom are not extracted; the mini
   player and MPRIS show a loose `cover`, `folder` or `poster` image beside the file, as the cover
   ladder does, else nothing. The core's cover ladder owes the embedded rung on the desktops.
4. **Something else takes the audio.** GstPlay does not know about another application's playback.
   PipeWire and PulseAudio cork a stream when a call starts; the app does not yet read the cork.
   A real session owes the test with a second player.
5. **Headphones removed.** No event reaches the app; PipeWire moves the stream to the speakers.
   A real session owes it; the phones' rule (pause) needs a device watcher the spike did not build.
6. **Flatpak.** Playback needs `--socket=pulseaudio` (already in the design's finish arguments).
   speech-dispatcher's socket lives under `XDG_RUNTIME_DIR/speech-dispatcher/`, outside the sandbox:
   the manifest will need `--filesystem=xdg-run/speech-dispatcher` and the host's daemon running,
   or the control is absent in the Flatpak. Not built; the Flatpak has not been built since wave 1.
7. **FLAC and Ogg** are checked for a decoder (`flacdec`, `oggdemux`) and not played by a test; the
   corpus has none.

## What a real sound device still owes

Hearing the chapter and the sentence; speech END, pause and resume; another player taking the
audio; headphones removed; the system's own volume and the player's rate on a desktop; and the
Flatpak's two sockets. These are host walks at the end of the waves, with the Linux conformance
walk of task 4.22.

## Reproduce

```bash
# The gate: tests and clippy in the floor container, with the pinned PDFium fetched into the volume
apps/desktop-linux/scripts/container-build.sh ubuntu-24.04 --clippy

# The engine tests for real: under cage, with a session bus, a null sink and libao's null driver
apps/desktop-linux/scripts/headless-proof.sh "audio speech"
```
