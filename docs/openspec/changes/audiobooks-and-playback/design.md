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

**Android has neither.** No compact bar, no media session, no service. The read-aloud
session ends with the reader.

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
| Chapters | `AVAsset.loadChapterMetadataGroups(bestMatchingPreferredLanguages:)`, falling back to file order for a folder |
| Session | `AVAudioSession` category `.playback`, mode **`.spokenAudio`** — the mode exists for exactly this and gets the right ducking and route behaviour |
| Compact bar | `tabViewBottomAccessory`, already there as `ReadAloudDock`, generalised |
| Full player | A `.sheet` from the accessory, per the platform's expand behaviour |
| Now playing | `MPNowPlayingInfoCenter` + `MPRemoteCommandCenter`, already wired for read-aloud |
| Speed without pitch | `AVPlayer.rate` with `audioTimePitchAlgorithm = .timeDomain`, which is the spoken-word algorithm |
| Interruption | `AVAudioSession.interruptionNotification`, honouring `.shouldResume` — the rule already implemented for read-aloud |
| Route change | `AVAudioSession.routeChangeNotification` with `.oldDeviceUnavailable` → pause |

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
