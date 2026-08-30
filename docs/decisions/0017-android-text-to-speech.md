---
status: accepted
date: 2026-08-30
deciders: Cédric Meyer
---

# ADR-0017 — Android reads a book aloud with the platform engine and no new dependency

## Context and problem statement

[`ebook-reader`](../openspec/specs/ebook-reader/spec.md) asks for reading aloud:
speech that begins at the reader's current position, a highlighted sentence, a
page that follows the voice, playback that survives the app being backgrounded,
and platform media controls carrying the publication title with play, pause and
sentence skip.

iOS was never in doubt. Readium's swift-toolkit — pinned at 3.11.0 and already in
`StoryArcEpub` — ships `PublicationSpeechSynthesizer`, `AVTTSEngine` and
`TTSVoice` inside `ReadiumNavigator`, the module the EPUB navigator already comes
from. Nothing is added; the type is imported.

Android carried a written belief that it *would* need a new artifact: Readium's
kotlin-toolkit publishes `readium-navigator-media-tts`, and this repository does
not depend on it. A new dependency here is an ADR rather than a judgement call,
so the belief was checked before it was acted on.

## What was established, and how

Three facts, each read out of an artifact on this machine rather than out of
documentation.

1. **`readium-navigator:3.3.0` contains no TTS.** Unpacking the cached AAR and
   listing `classes.jar` gives ten packages — `epub`, `image`, `pdf`, `pager`,
   `preferences`, `html`, `input`, `util`, `extensions`, `databinding` — and no
   `media` package at all. The belief was right that far.

2. **`readium-navigator-media-tts:3.3.0` exists and would cost more than
   itself.** Its POM on Maven Central pulls `readium-navigator-media-common`,
   `androidx.media3-session`, `media3-common-ktx`, `kotlinx-serialization-json`
   and `com.jakewharton.timber` — a logging library, into an app whose contract
   says there is no logging anywhere in either app's sources.

3. **`readium-shared:3.3.0` already carries everything the walk needs, and
   `readium-streamer:3.3.0` already installs it.** `classes.jar` in the shared
   AAR contains `ContentService`, `DefaultContentService`, `TextContentTokenizer`
   and `HtmlResourceContentIterator`. Disassembling `EpubParser` from the streamer
   AAR shows it constructing `DefaultContentService.createFactory(...)` with an
   `HtmlResourceContentIterator.Factory` and passing it into the publication's
   `ServicesBuilder`. Every EPUB this app opens therefore answers
   `publication.content(from:)` today, with no change to how it is opened.

So the missing piece was never text extraction and never sentence
tokenization — both are present. It was the *navigator integration*: a
`TtsNavigator` and a media3 session. And `android.speech.tts.TextToSpeech` has
been in the platform since API 4.

## Decision

**Android reads aloud with `readium-shared`'s content service and the platform's
own `TextToSpeech`. No new dependency is added.**

Concretely:

| Job | Android | iOS |
| --- | --- | --- |
| What to say, and where it is in the book | `readium-shared` content iterator + `TextContentTokenizer` (`SpokenSentences`) | `PublicationSpeechSynthesizer` |
| Saying it | `android.speech.tts.TextToSpeech` | `AVSpeechSynthesizer`, via `AVTTSEngine` |
| Highlighting the sentence | `DecorableNavigator`, group `spoken` | `DecorableNavigator`, group `spoken` |
| What a pause means | `ReadAloudSession` | `ReadAloudSession` |
| Staying alive when backgrounded | foreground service, type `mediaPlayback` | `UIBackgroundModes: audio` |
| Lock-screen controls | `MediaSession` + `Notification.MediaStyle` | `MPNowPlayingInfoCenter` + `MPRemoteCommandCenter` |

The two halves are deliberately not the same shape. The decision that *is*
mirrored is the one that goes wrong — what a pause means, and therefore whether a
finished phone call starts the book again — and it lives in `ReadAloudSession`,
asserted fourteen times a side without a speaker.

## Alternatives considered

### Add `readium-navigator-media-tts`

Would have given a `TtsNavigator` and a media3 `MediaSessionService`, which is
more robust than the foreground service written here: media3 owns the player, so
playback survives the activity being destroyed rather than only the app being
backgrounded.

Refused. It brings four transitive artifacts for one screen, one of them a
logging library this project's contract forbids in its own sources; it moves the
app onto media3, a dependency nothing else here needs; and the part it replaces —
walking content and tokenizing sentences — is already present and already paid
for. The robustness it buys is real and is named in "Consequences" below rather
than pretended away.

### Refuse read-aloud on Android and ship it on iOS alone

Refused. The spec asks for it, both apps are deliberate mirrors, and the
established facts show no obstacle. A one-platform capability needs a reason, and
"nobody checked" is not one.

### Write our own sentence tokenizer over `publication.get(href).read()`

Refused. `java.text.BreakIterator` splits sentences, but the hard part is not the
split — it is producing a `Locator` for each sentence that the navigator can
highlight and navigate to, across resource boundaries, out of HTML that has to be
stripped first. `HtmlResourceContentIterator` does exactly that and is already on
the classpath. Reuse before adding.

## Consequences

**Good.** No new artifact, no new licence, no new attack surface, and the APK
does not grow. The voice is the device's own, so a reader hears the voice they
installed and the languages they downloaded, and nothing about the book leaves
the device to be spoken. The engine is built on the first press rather than at
open time, so a reader who never presses play pays nothing for it.

**Bad, and named.** The controller lives in the activity, because the walk needs
Readium's `Publication` and a `Publication` cannot be handed to a service through
an `Intent`. The foreground service keeps the *process* alive, which is what
backgrounding needs; it does not keep the *activity* alive. If Android destroys
the reader activity — a configuration change the activity does not declare, or
memory pressure severe enough to take a foreground-service process — playback
ends. `readium-navigator-media-tts` would not have that limitation. Revisit this
if a reader reports the voice stopping while another app is in front.

**Also named.** `TextToSpeech` cannot resume part-way through an utterance, so a
pause resumes at the start of the sentence it interrupted rather than in the
middle of it. One sentence heard twice is the deliberate choice; half a sentence
lost was the alternative.

**Verification owed.** The facts above were established from artifacts. Whether
the lock-screen transport actually appears, and whether the voice survives a
locked screen, is a device question and is recorded honestly in
[`STATUS.md`](../openspec/STATUS.md) rather than assumed here.
