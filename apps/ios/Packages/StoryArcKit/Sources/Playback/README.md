# `Playback`

The player's model: one session, two sources, and nothing a view can see the engine through.

`audio-playback` is the spec. This target holds what playing a book *is* — the state, the
place, the speed, the skip intervals, the sleep timer — and the platform contract that a
running session needs. It draws nothing: `PlayerFeature` does that, and the split is a
build-level fact rather than a convention, because `Formats` depends on this target for
`AudiobookPart` and a parser has no business linking SwiftUI.

The mirror is Android's [`:core:playback`](../../../../../android/core/playback/README.md),
which pins the same session table and the same three duration cases.

## Files

| File | What it holds |
| --- | --- |
| `PlaybackSource.swift` | The protocol with two implementations, and the two places they may differ. **No `kind`, no `isNarrated`, nothing a view can switch on** |
| `NarratedSource.swift` | `PlaybackSource` over `AVPlayer`: items, chapter marks and rates mapped onto parts, positions and speed |
| `SpokenParts.swift` | The read-aloud side of the same seam. The engine is `StoryArcEpub`'s; this is the shape it fills |
| `SpokenBook.swift` | The book being played, `SpokenLabel`, and `CompactPlayer` — everything the bar draws |
| `Audiobook.swift` | What the format layer hands the player: a part is a mark inside a file or a whole file of a folder |
| `PlaybackPart.swift` | A part, and `PlaybackTime` — position with a total, or position without one |
| `PlaybackControls.swift` | `PlaybackSpeed`, clamped to the 0.5×–3× range `design.md` records as a product decision |
| `PlaybackTimeline.swift` | Whole-book time, out and back, so a skip crosses a part boundary. `SkipIntervals`, `SkipDirection`, `SkipUnit` |
| `SpeechRate.swift` | The mapping from a stated speed to the units a synthesised utterance takes |
| `PlaybackSession.swift` | The state table: who silenced the audio, and what the end of an interruption does |
| `PlayerCentre.swift` | The one session object. Begins, displaces, records, publishes |
| `PlayerPosition.swift` | What a session writes down, and when |
| `PlayerSkip.swift` | How far a skip moves, and who is told when it changes |
| `PlayerSleep.swift` | The sleep timer's own transitions, and the only thing that moves them |
| `PlayerInterruption.swift` | What the *platform* does to a session: a call, a route lost, audio taken for good |
| `SleepTimer.swift` | A duration or end-of-chapter, as one remaining time |
| `PlaybackAudioSession.swift` | `AVAudioSession` at `.spokenAudio`, and the notifications the file above acts on |
| `NowPlaying.swift` | `MPNowPlayingInfoCenter` and `MPRemoteCommandCenter`, fed by the one centre |
| `PlaybackPlatform.swift` | The four moments the platform half needs, as a protocol — which is what makes the rest host-testable |

Each of `PlayerPosition`, `PlayerSkip`, `PlayerSleep` and `PlayerInterruption` is an extension
of `PlayerCentre` in a file of its own. `PlayerCentre.swift` sits against SwiftLint's 400-line
cap and the cap keeps pointing at a real seam: the centre owns *what is playing*, and each
control it offers owns its own rule.

## Public API

| Entry point | For |
| --- | --- |
| `PlayerCentre.begin(_:source:)` | Play a book, displacing whatever was playing and recording its place first |
| `PlayerCentre.compact` | Everything the bar draws, or `nil` — and the bar is **absent** then, never present and empty |
| `PlayerCentre.toggle() / pause() / skip(_:) / scrub(to:) / play(part:) / setSpeed(_:)` | The transport. `pause()` is apart from `toggle()` because a pause control must never mean play |
| `PlayerCentre.setSkipIntervals(_:)` / `setSleepTimer(_:)` | The two configurable controls |
| `PlayerCentre.interrupt() / resumeAfterInterruption() / routeLost() / lostAudio()` | What the platform does to a session |
| `PlayerCentre.onRecord` | Where a position goes — a closure, because this target must not know that `reading-progress` keeps a store |
| `PlayerCentre.onRecallSpeed` / `onRememberSpeed` / `onRememberSkip` / `onArtwork` | The four things the app supplies |
| `PlaybackSession` | The table itself, usable without a centre |

## Config

One resource catalogue, `Resources/Localizable.xcstrings`, holding one string: the name of a
part the container did not name. A model target carrying a catalogue is unusual here, and the
reason is that `audio-playback` requires the compact bar and the lock screen to say the *same*
thing — "Part 3" has to be one answer, not two.

No store of its own. The speed, the skip intervals and the position are all the app's to keep;
this target asks for them and hands them back.

## Data flow

```
Formats ──► Audiobook ──┐
                        ├──► NarratedSource ──┐
StoryArcEpub ──► SpokenSource ────────────────┤
                                              ▼
                                        PlayerCentre ──► PlaybackPlatform
                                              │              ├─► AVAudioSession
                                              │              ├─► MPNowPlayingInfoCenter
                                              │              └─► the sleep timer's clock
                                              ▼
                                    CompactPlayer, PlaybackTime ──► PlayerFeature
```

The wall clock is on the platform's side of that line deliberately: a thirty-second fade
asserted in real time is thirty seconds of a unit test, so the whole of the sleep timer's
behaviour is `tickSleepTimer(by:)` and a test moves time by calling it.

## Tests

```bash
pnpm test:ios                                  # the whole package, on the host
swift test --filter PlaybackTests              # from apps/ios/Packages/StoryArcKit
```

Every test here runs on the host with no simulator, which is the reason the session table
lives in this target rather than beside the read-aloud engine in `StoryArcEpub`.

**Two things no host test reaches, and neither is asserted anywhere else.** An audio session
cannot be interrupted from one — `PlaybackAudioSession` raises the notifications and everything
downstream of them is `PlayerInterruptionTests` — and **none of this has been heard**. No call
has been taken, no headphones pulled out, and no book listened to on a device.
