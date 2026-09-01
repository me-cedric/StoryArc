# Design — audiobooks, and one player for everything that speaks

## Where the guidance came from

The same 2026-08-31 research pass described in
[`quiet-shell-and-search/design.md`](../quiet-shell-and-search/design.md), plus a
pass over `androidx.media3` at the versions actually on the classpath — checked by
unzipping the cached AARs, not by reading release notes.

## What already exists, and is most of the work

**iOS has the surface.** `AppShell.swift` already puts `ReadAloudDock` in
`tabViewBottomAccessory`, and `ReadAloudCentre` already owns a speech session that
outlives the reader — `read-aloud-beyond-the-reader` did that. What is missing is a
second source feeding the same dock, a full player behind it, and the controls.

**Android has less, and this paragraph used to overstate it.** It said "no compact bar, no
media session, no service" and "the read-aloud session ends with the reader". Only the first
was true. `feature/epubreader/ReadAloudService.kt` is already a `mediaPlayback` foreground
service holding a framework `android.media.session.MediaSession` with a `MediaStyle`
notification, and `ReadAloudHost` is a process-wide singleton whose session outlives the
screen that started it.

That does not change the work — a hand-rolled framework session is not the media3
`MediaSessionService` this change needs, and the two cannot both own the notification — but
a plan that misdescribes its own starting point sends an implementer looking for something
that is already there.

So the platforms are at different starting points, and the Android task list is
strictly longer. That is platform obligation, not scope creep, and it is in the plan
from the start.

## The player's model, shared by both platforms

One protocol/interface with two implementations — a narrated file and a synthesised
voice — and one session object the surfaces observe. The surfaces never learn which
implementation is behind them; that is what makes "both sources look the same" a
structural property rather than a promise.

| Concept | Meaning for a narrated audiobook | Meaning for read-aloud |
| --- | --- | --- |
| Part | A chapter marker, or a file | A resource in the publication's reading order |
| Position | An offset in time | The sentence being spoken, mapped to a locator |
| Duration | Known from the container | Unknown; estimated from characters and rate, and never presented as exact |
| Speed | Playback rate | Speech rate |

**Duration is where the abstraction is thinnest, and the spec is written around it**:
the compact bar states the chapter, not a countdown, and the scrub control is offered
where a duration is known. A read-aloud session shows position without a total rather
than inventing one.

## iOS

| Thing | Decision |
| --- | --- |
| Decoding | `AVFoundation` — `AVURLAsset` + `AVPlayer`. M4B is MPEG-4 audio and needs nothing extra |
| Chapters | `AVAsset.loadChapterMetadataGroups(bestMatchingPreferredLanguages:)` — **with the asset's own locales, not `["en"]`**. See below |
| Session | `AVAudioSession` category `.playback`, mode **`.spokenAudio`** — the mode exists for exactly this and gets the right ducking and route behaviour |
| Compact bar | `tabViewBottomAccessory`, already there as `ReadAloudDock`, generalised |
| Full player | A `.sheet` from the accessory, per the platform's expand behaviour |
| Now playing | `MPNowPlayingInfoCenter` + `MPRemoteCommandCenter`, already wired for read-aloud |
| Speed without pitch | `AVPlayer.rate` with `audioTimePitchAlgorithm = .timeDomain`, which is the spoken-word algorithm |
| Interruption | `AVAudioSession.interruptionNotification`, honouring `.shouldResume` — the rule already implemented for read-aloud |
| Route change | `AVAudioSession.routeChangeNotification` with `.oldDeviceUnavailable` → pause |

### The chapter call takes the asset's locales, not the reader's

The method above is right and **the obvious argument is wrong**, which is worth a paragraph
because the failure is silent. Measured on 2026-09-01 against the corpus:

- `availableChapterLocales` → `["und"]`
- `loadChapterMetadataGroups(bestMatchingPreferredLanguages: ["en"])` → **0 groups**
- the same call with the asset's own identifiers → 3 groups

Both chaptered fixtures declare their titles under the undetermined locale, which is what
most real audiobooks do — a chapter title is the publisher's, not a translation. Asking for
English gets nothing, and nothing is indistinguishable from an unchaptered file: a
three-chapter book becomes one unnamed part and no error is raised anywhere. Mutation-checked
by restoring the obvious argument.

### The speech-rate mapping, and a premise of mine that was wrong

The delegate route works and is what shipped. **One thing I asserted when writing it up was
false, and the truth is a worse hazard rather than a smaller one.**

I wrote that `AVSpeechUtteranceMinimumSpeechRate`, `…Default` and `…Maximum` "are not linearly
spaced and a naive lerp puts 1× in the wrong place". Measured on 2026-09-01 they are
`0.0`, `0.5`, `1.0` — **evenly spaced**. So the first clause was simply wrong.

The conclusion survives for a different reason. A single line from 0.5×–3× onto 0.0–1.0 puts
**1× at 0.2**, far below the platform's own default of 0.5 — so a listener who never touched
the speed control would get a voice slower than the system speaks at everywhere else. The
mapping is therefore two lines meeting at the default: 0.5×–1× onto min–default, 1×–3× onto
default–max. `SpeechRateTests` asserts 1× is *not* where the single line puts it, and its
mutation check produces exactly `0.2`.

Recorded because the wrong reason would have led somebody to a lookup table for a curve that
is not curved, and away from the anchoring that actually matters.

### A crash that only a device could find

`EngineFactory` is a bare `() -> TTSEngine`, and Readium builds its engine from a `lazy var`
inside its own task. An inline closure inherits `@MainActor`, so the first utterance tripped
`swift_task_checkIsolated` and the process died on `EXC_BREAKPOINT`. **`pnpm check` exits 0 on
it** — a type-checked closure with the wrong isolation is not a compile error. The fix is a
`nonisolated` method reference rather than a closure.

Worth stating as a general fact about this project's gates: the compile-and-unit-test gate
cannot see actor isolation at a boundary a library crosses on its own schedule.

### Two tasks turned out to be blocked rather than merely unfinished

**Read-aloud's speed control: the block is real and there is a fourth way out, which is
the one to take.**

Readium 3.11.0's `PublicationSpeechSynthesizer.Configuration` carries a language and a voice
and **no rate** — `AVTTSEngine.swift:131`, the line that would apply one, is commented out
upstream. `audio-playback` requires every control the player offers to work or be absent, so
wiring read-aloud into a surface with a speed control would break the spec the day it landed.
All of that stands.

The three ways out named in tasks.md were: let a source declare it offers no speed; replace
Readium's engine with our own `AVSpeechSynthesizer`; or carry a patched dependency. The first
takes the feature away from the reader, the second reimplements tokenisation and locator
mapping we already get for free, and the third is a fork to maintain.

**None of them is necessary.** Readium provides two extension points for exactly this, both
public:

- `PublicationSpeechSynthesizer.init(engineFactory:)` — the engine is injected, defaulting to
  `{ AVTTSEngine() }`.
- `AVTTSEngineDelegate.avTTSEngine(_:didCreateUtterance:)`, whose own doc comment reads
  *"You can customize additional properties of the utterance."*

The commented-out lines are not an oversight; they are upstream saying **the caller sets
this now**. So the app supplies an `AVTTSEngine` with a delegate that applies the session's
speed to each `AVSpeechUtterance` as it is created, and keeps Readium's tokenisation, its
locators and its highlight mapping untouched.

**Decided: take the delegate.** No fork, no reimplementation, no feature withdrawn, and the
API is used the way its author documented. The mapping from the player's 0.5×–3× onto
`AVSpeechUtterance.rate` is ours, because Readium's own `rateMultiplierToAVRate` is private —
it belongs beside `PlaybackSpeed`, with a test pinning the endpoints and the default.

With that, read-aloud can drive the player and tasks 4.2 and 6.2 are unblocked.

**A truncated single file cannot be caught at index time.** `truncated.m4b` was cut with
`+faststart`, so its `moov` is intact and `AVURLAsset` reports the full six seconds, all
three chapters, and `isPlayable == true` — which is exactly what made it a good fixture for
"plays what it can". The folder case is countable at index time; the single-file case needs
the player to notice the item failing during playback. Task 2.5 is split accordingly.

## Android

| Thing | Decision | Why |
| --- | --- | --- |
| Decoding | `androidx.media3:media3-exoplayer` | Decodes every format in the table natively |
| Session | `androidx.media3:media3-session`, a real `MediaSessionService` | This is a platform contract, not styling. A player without it is broken, not unpolished |
| Service declaration | `foregroundServiceType="mediaPlayback"`, both `FOREGROUND_SERVICE` permissions | Required since API 34 |
| Notification | media3's automatic `MediaStyle` notification | Hand-rolling it is how the shade and the lock screen fall out of step |
| Resumption | `MediaSession.Callback.onPlaybackResumption` returning the saved position | What makes the notification-shade carousel work after process death |
| Android Auto | `MediaLibraryService` + `automotive_app_desc.xml` | An audiobook player that cannot be driven from a car is missing its best use |
| Version | **media3 1.11.0**, declared explicitly in the version catalog | See the note below. Readium already puts 1.10.0 on the runtime classpath, so this is a bump plus a declaration, not a new dependency |
| Compact bar | **Hand-composed row** in `NavigationSuiteScaffold`'s `content` slot | See below |
| Progress line | Flat `LinearProgressIndicator` | Material cautions the wavy variant *"may not be as visible"* at small sizes and says linear indicators *"shouldn't be used in any elements smaller than 40dp"* |
| Rows | `ListItem` | The guided row for icon + heading + supporting line |

### The media3 version, checked rather than taken on trust

The research pass reported that M4B chapter marks are "absent at 1.10.0". That is
true of MP4 and **not** true in general, and the difference decides how much of the
format table works before the bump. Checked on 2026-08-31 by unzipping the cached
`media3-common-1.10.0.aar`, `media3-container-1.10.0.aar` and
`media3-extractor-1.10.0.aar` and reading the class list:

- **ID3 chapters already work at 1.10.0.** `ChapterFrame` and `ChapterTocFrame` are
  both present in `androidx.media3.extractor.metadata.id3`. So a folder of chaptered
  MP3s — the common library-service export — needs no bump at all.
- **MP4 chapters do not.** No class in any of the three artifacts is named for a
  chapter atom, `BoxParser` disassembles with no reference to `chap` or `chpl`, and
  `media3-common` carries none of those strings across its 388 classes. M4B is the
  format that needs 1.11.0.

`1.11.0` is released and stable — confirmed against Google's Maven metadata for
`androidx.media3:media3-common`, which also lists a `1.10.1` between the two.

**What this changes in the plan.** Nothing is blocked on the bump: task 2.1's
detection, task 2.3's unchaptered case and the whole MP3-folder path work at 1.10.0.
The bump buys M4B's own chapter marks and nothing else, so if it ever turns out to
drag Readium's transitive media3 somewhere unwelcome, the fallback is a chaptered-M4B
gap rather than no audiobooks.

### Why the compact bar is hand-composed

Material's own guidance points at the standard bottom sheet — its bottom-sheets page
names *"an audio player in a music app"* as the example. **The shipped API cannot
deliver it.** `BottomSheetScaffold` has a `topBar` slot and **no `bottomBar` slot**, so
its peek height anchors to the window bottom and the peek row would sit *behind* the
navigation bar. The guideline is right and unfollowable at 1.5.0-alpha26, so the row is
composed by hand and the drag-to-expand sheet is deferred to its own change.

**Two wrong turns are recorded here because nothing in the build will stop them.**
`HorizontalFloatingToolbar` compiles with no opt-in, and `BottomAppBar` compiles with
no deprecation warning — yet toolbars and navigation bars *"should not be shown at the
same time"*, and the baseline bottom app bar is *"no longer recommended"*. Neither is
the answer.

**`MiniController` is rejected deliberately, not overlooked.** It exists at media3
1.11.0, and it is `@UnstableApi`, was compiled against material3 1.4.0 through a
compose-bom constraint, and defaults its controls to previous / play-pause / next —
which is wrong for spoken word. The 1.11.0 bump is taken for the chapter metadata; the
row is ours.

## The position of a listener: a third case, and the two rules it must not break

`§7` is blocked on `ReadingPosition`, which today is exactly two cases — `page(index:of:)`
and `reflowable(progression:locator:)`. An audiobook is neither. Settled here so both
platforms add the same thing:

```
case listening(part: Int, offset: TimeInterval, of: TimeInterval?)
```

**Three decisions inside that signature.**

`part` is an index into the publication's parts, and the *name* is not stored — a chapter
title belongs to the file, and a position that carried a stale copy of it would disagree with
the book after a re-download.

`offset` is seconds into that part, not into the whole publication. A folder audiobook's
parts can be re-ordered or replaced one at a time, and a whole-publication offset silently
moves when an earlier part changes length.

**`of` is optional, and that is the load-bearing part.** A read-aloud session has no true
duration — `PlaybackDuration.Estimated` exists on both platforms precisely so an estimate can
never be presented as exact — so a position taken from one has no total to divide by.
`fraction` must therefore answer for a position with no total, and the honest answer is the
part index over the part count, not a guess refined by an estimate.

**Two existing rules this must not break.**

`fraction` is the currency the whole progress merge deals in, and `matches` compares by it.
So a listening position must produce a fraction on the same 0…1 scale, or ADR-0006's merge
table stops working for audiobooks — a remote position would never equal the local one it was
stored from.

And the store keeps `positionData` as **JSON of the enum**, which is what lets `StoryArcCore`
stay free of SwiftData. A record written before this case existed decodes unchanged, because
the new case never appears in it; the reverse is not true, and does not need to be — there is
no older build in anybody's hands.

Android mirrors the case in `:core:model` and its own store, as it mirrors the other two.

## Where the two platforms deliberately differ

| | iOS | Android | Why not the same |
| --- | --- | --- | --- |
| The bar's material | Floating glass capsule above the tab bar | Full-width `surfaceContainer`, sharing the navigation bar's container colour so the two read as one bottom assembly | Material has no glass and its bottom region is full-bleed. Copying the inset capsule would import iOS's visual language into a Material surface with no Material rule behind it — which is what [ADR-0001](../../../decisions/0001-independent-native-cores.md) exists to prevent |
| Reach beyond the app | Lock screen, Control Centre | Lock screen, **notification-shade carousel, playback resumption after process death, Android Auto** | Android's media contract is genuinely larger |
| What's in the compact bar | Play/pause and a way in | Seek-back / play-pause / seek-forward | media3's own defaults (`DEFAULT_SEEK_BACK_INCREMENT_MS = 5000`, `DEFAULT_SEEK_FORWARD_INCREMENT_MS = 15000`) are wrong for spoken word in the other direction, and the three compact notification slots should carry the same three controls |

## The product decisions, labelled as such

Neither Material nor Apple publishes guidance on these. They are ours, and the delta
must not cite a guideline for them:

- **Skip increments.** 15 seconds back, 30 seconds forward, both configurable. Back is
  shorter because the reason to skip back is "I missed that sentence" and the reason to
  skip forward is "I know this part".
- **The end-of-chapter sleep timer.** A music player has no reason to offer it. A book
  player does, and it is the option a listener falling asleep actually wants.
- **Naming the chapter, not the file.** `01 - track.mp3` is not what a listener is in
  the middle of.
- **Speed range.** 0.5× to 3×, the range spoken-word listeners actually use.

## Not started here

- **EPUB 3 media overlays**, and any alignment of a narrator's audio to the text. A
  separate problem with a separate spec.
- **A drag-to-expand now-playing sheet on Android**, blocked on `BottomSheetScaffold`
  gaining a bottom-bar slot or on a hand-built anchored sheet. The full player is a
  destination until then.
- **DRM.** `.aax`/`.aaxc` is refused by name and that will not change.
