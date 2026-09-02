# `:core:playback`

The audiobook player: one session, the platform's media contract, and no surface.

`audio-playback` is the spec. This module decodes audio and keeps a book playing once every
screen has gone; it draws nothing, knows nothing about a library, and names no engine on any
type a surface can see — which is what makes "one player, two sources" structural rather than
intended.

## Files

| File | What it holds |
| --- | --- |
| `PlayerSource.kt` | The interface with two implementations, and `NowPlaying` — everything a surface draws and nothing that names the engine |
| `AudiobookSource.kt` | `PlayerSource` over media3: items, windows and metadata entries mapped onto parts, positions and durations |
| `Audiobook.kt` | What the format layer hands the player, and `PartLayout` — a folder of files or marks inside one |
| `AudiobookChapters.kt` | `ChapterMark` and the rules over it: an unchaptered book is one part, never an empty list |
| `PlaybackPart.kt` | `PlaybackDuration` (known, estimated, unknown), `PlaybackPosition`, `PlaybackSpeed` |
| `PlaybackTimeline.kt` | Whole-book time, out and back, so a skip crosses a part boundary. `SkipDirection` |
| `SkipIntervals.kt` | How far a skip goes, clamped to the offered range |
| `SkipButtons.kt` | Which media3 glyph an interval wears |
| `SkipPreferences.kt` | The listener's chosen intervals, where the service can read them |
| `PlaybackSession.kt` | The state table: who silenced the audio, and what the end of an interruption does |
| `PlaybackFocus.kt` | media3's focus signals read as those states |
| `PlaybackCentre.kt` | The one session object. Displaces, records, publishes |
| `PlaybackHost.kt` | The process-wide singleton the app observes, and the `MediaController` behind it |
| `PlaybackService.kt` | `MediaLibraryService`: the foreground service, the notification, resumption, the browse tree |
| `PlaybackMemory.kt` | What was playing, on disk, for a service the system started without the app |
| `PlaybackResumption.kt` | A remembered book turned into items and a start position |
| `SleepTimer.kt` | A duration or end-of-chapter, as one remaining time |

## Public API

| Entry point | For |
| --- | --- |
| `PlaybackHost.start(context, book, from, speed, chapterWord)` | Play a publication, displacing whatever was playing |
| `PlaybackHost.nowPlaying: StateFlow<NowPlaying?>` | What every surface draws. Null when nothing plays — and the compact bar is **absent** then, not empty |
| `PlaybackHost.toggle / seek / seekToPart / setSpeed / stop` | The transport |
| `PlaybackHost.skip(direction)` | Moves by the configured interval, crossing a part boundary |
| `PlaybackHost.skipIntervals` / `setSkipIntervals(intervals)` | How far, and changing it |
| `PlaybackHost.sleep` / `setSleepTimer(after)` | The sleep timer, counting down |
| `PlaybackHost.recordPosition` | Where a position goes. Set by the app once — a lambda, because this module must not know a library keeps a database |
| `PlaybackService` | Declared in this module's own manifest. The app depends on the module; the merger does the rest |

## Config

Two preferences files of its own, both because `PlaybackService` reads them and a service the
system has just started to answer the shade carousel has no scope, no database and no time —
and because this module deliberately does not depend on `:core:persistence`.

| File | Holds |
| --- | --- |
| `app.storyarc.playback.memory` | The URIs, part titles, index and offset of the book that was playing |
| `app.storyarc.playback.skip` | The chosen skip intervals, in seconds |

Neither is a reading position. That is `reading-progress`'s, stored by the app, and the two
agreeing is the app's job.

## Data flow

```
:core:format ──► OpenedAudiobook (in :app) ──► Audiobook
                                                  │
                          PlaybackHost.start ─────┘
                                │
                MediaController ├──────────────► PlaybackService ──► ExoPlayer
                                │                     │
                    PlaybackCentre                    ├─► MediaStyle notification
                          │                           ├─► lock screen, shade carousel
                    AudiobookSource                   └─► Android Auto browse tree
                          │
                     NowPlaying ──► compact bar, full player
```

The decoder lives in the service, not here, which is what lets a book carry on when the app's
process is trimmed to the service alone. `AudiobookSource` holds a `Player` — a
`MediaController` is one — so the same code drives the audio from either side of that boundary.

## Tests

```bash
pnpm gradle :core:playback:testDebugUnitTest
pnpm gradle :core:playback:lint
```

All host tests; Robolectric where a framework component is involved (`SharedPreferences`,
`Uri.parse`). **Nothing here has been heard.** The notification, the lock screen, resumption
after process death and Android Auto are asserted by instrumented tests in `:app`
(`PlayerServiceIsDeclaredTest`, `PlayerBrowseTreeTest`) and by nothing that runs on the JVM —
`pnpm build:android:tests` compiles those, which is the part that was missing before, and
`pnpm gradle :app:connectedDebugAndroidTest` is what runs them.
