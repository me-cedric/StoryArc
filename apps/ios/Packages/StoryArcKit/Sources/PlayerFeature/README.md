# `PlayerFeature`

The player's surfaces: a bar that rests above the navigation control, the player it opens
onto, and its three sheets.

`audio-playback` is the spec. Every view here reads a `PlayerCentre` and writes back to it. It
holds no engine and no state beyond which sheet is open — which is what makes "opening the
full player never restarts, reloads or repositions the audio" true by construction rather than
by care: there is nothing in this target that *could* restart anything.

Apart from [`Playback`](../Playback/README.md) because that target must stay free of SwiftUI
and `DesignSystem`. The Android mirror is `PlayerScreen.kt` and `CompactPlayerBar` in
`:app` and `:core:designsystem`.

## Files

| File | What it holds |
| --- | --- |
| `PlayerDock.swift` | The compact bar for `tabViewBottomAccessory`: what is playing, play/pause, and the way back |
| `PlayerSheet.swift` | `playerSheet(isPresented:centre:)` — the full player's *presentation*, hosted by the shell rather than by the bar that opens it |
| `FullPlayerView.swift` | The player: artwork, publication, chapter, position, the transport, and the three ways into the sheets |
| `PlayerSheets.swift` | `ChapterListView`, `SpeedSheet`, `SleepTimerSheet`, `SkipIntervalsSheet` |
| `PlayerArtwork.swift` | The shared coverless well at the player's shape, and `PlayerArtworkImage` — the same view rendered at 512 pt for the lock screen |
| `PlayerLabels.swift` | Every announcement and stated value as a **decision**, never as prose |
| `PlayerText.swift` | Those decisions turned into `Text`, where the localised keys are literals a gate can read |

**Why the labels are split across two files.** `scripts/ios-strings.mjs` proves every key
resolves in all four languages by reading `Text("…")` and `String(localized: "…")` out of the
source, so a sentence assembled in code is a sentence that gate cannot see. And `swift build`
copies an `.xcstrings` without compiling it — measured, not assumed — so `String(localized:)`
answers with the key itself on the host, and a host test asserting English prose would be
asserting a lookup that cannot work where it runs. `PlayerLabels` therefore returns values with
tests over them; `PlayerText` turns each into words.

## Public API

| Entry point | For |
| --- | --- |
| `PlayerDock(centre:isShowingPlayer:onReturn:)` | The compact bar. `onReturn` is how a read-aloud session gets back to its reader |
| `View.playerSheet(isPresented:centre:)` | Presents the full player from the shell's `TabView`, which lives as long as the app does |
| `FullPlayerView(centre:)` | The player itself |
| `ChapterListView`, `SpeedSheet`, `SleepTimerSheet`, `SkipIntervalsSheet` | Each takes the centre and nothing else |
| `PlayerArtwork(format:)` | The coverless treatment at the player's shape |
| `PlayerArtworkImage.png(format:)` | The same view as bytes, for `MPMediaItemPropertyArtwork` |
| `PlayerLabels` | The stated values, so a surface never invents one |

**The presentation is the shell's, and that is a fix rather than a preference.** `PlayerDock`
used to host the player's `.sheet` on a view inside `if let bar = centre.compact`, so pressing
any transport control rebuilt the host and tore the presentation down — a skip-back tap
dismissed the player. It could not be fixed by wrapping the dock in a stable container:
`audio-playback` requires the bar to be *absent* rather than present and empty, so the dock's
body must keep producing nothing when there is nothing to draw, and a host that is stable
cannot also be a host that sometimes does not exist.

## Config

One resource catalogue, `Resources/Localizable.xcstrings`, in all four languages. No store, no
preferences, no defaults: everything a listener configures is `PlayerCentre`'s and is kept by
the app.

## Data flow

```
PlayerCentre ──► CompactPlayer ──► PlayerDock ──► playerSheet ──► FullPlayerView
     ▲                                                                │
     └──────────────── toggle / skip / scrub / setSpeed / … ◄──────────┘
                                                                      │
                                            ChapterList, Speed, Sleep, Skip sheets
```

One arrow in and one arrow out. A view that took a `Publication` instead of a `PlayerCentre`
would have to start something in order to draw anything, which is the shape this target avoids.

## Tests

```bash
pnpm test:ios                                        # the whole package, on the host
swift test --filter PlayerFeatureTests               # from apps/ios/Packages/StoryArcKit
pnpm build:ios:tests                                 # the only gate that compiles UITests/
```

`PlayerLabelsTests` covers every stated value and announcement. The layout claims are not
assertable from a host test — a tab bar cannot be one — so they are captures under
`docs/designs/screenshots/after-2026-09-01-ios-player/` and `…-ios-player-artwork/`, and the
accessibility audits are `UITests/PlayerAuditTests`, which walks six surfaces and calls
`performAccessibilityAudit` on each. **Nothing under `apps/ios/UITests` is compiled by
`pnpm test:ios` or `pnpm build:ios`** — `pnpm build:ios:tests` is the only gate that reads it.
