---
status: accepted
date: 2026-08-24
deciders: Cédric Meyer
---

# ADR-0004 — Desktop strategy: documented now, built later

**Accepted as planning only. No implementation.**

## Context and problem statement

StoryArc is a mobile app first. Desktop is wanted eventually, on macOS, Windows
and Linux. Deciding the desktop stack now — before either mobile app ships — is
premature; leaving it entirely undecided is worse, because mobile decisions
would be made in ignorance of what desktop later needs.

This ADR records the direction and the reasoning. **No desktop code is written
until both mobile apps have shipped a 1.0.**

## Considered options

| Target | Option | Verdict |
| --- | --- | --- |
| macOS | Multiplatform SwiftUI target inside `apps/ios` | **Chosen.** Reuses the iOS core wholesale. |
| macOS | Mac Catalyst | Rejected. Produces an iPad app in a window, which fails the native-feel requirement. |
| Windows | WinUI 3 via the Windows App SDK | **Assumed**, pending a spike. The platform vendor's own toolkit. |
| Windows | Avalonia | Runner-up. Draws every pixel itself, so one look everywhere — the wrong trade here, but it would also cover Linux. |
| Windows | .NET MAUI | Rejected. Renders through WinUI 3 anyway, so it adds a layer without adding a capability. |
| Linux | GTK4 + libadwaita | **Open.** Native on GNOME, but a third implementation in a third language. |
| Linux | Avalonia | **Open.** One implementation shared with Windows, at the cost of not looking like a GNOME app. |

## Decision Outcome

Three targets, three answers, because they are genuinely three different
problems.

### macOS — SwiftUI, sharing the iOS codebase

Not a separate app. `apps/ios` becomes a multiplatform SwiftUI target: the same
feature packages, with Mac-specific navigation, a real menu bar, multiple
windows, and AppKit interop where a desktop control has no SwiftUI equivalent.
This is the one desktop target that costs a fraction of a new app, because it
reuses [ADR-0001](0001-independent-native-cores.md)'s iOS core wholesale.

Mac Catalyst is rejected: it produces an iPad app in a window, which fails the
native-feel requirement on the desktop it is trying to feel native on.

### Windows — WinUI 3 via the Windows App SDK

**Assumed, pending a spike.** WinUI 3 is Microsoft's own framework for native
Windows desktop apps, giving the current Fluent controls and modern windowing
directly rather than through an abstraction. For an app whose whole premise is
looking stock on each platform, using the platform vendor's own toolkit is the
consistent choice.

The runner-up is **Avalonia**, which draws every pixel itself via Skia rather
than delegating to native widgets. That is the right trade for an app that wants
one identical look everywhere — and the wrong trade for StoryArc, which wants to
look different on each platform on purpose. Avalonia's real advantage is that it
would also cover Linux from the same codebase, which is why it stays on the
table until the spike settles it.

.NET MAUI is rejected: on Windows it renders through WinUI 3 anyway, so it adds
an abstraction layer without adding a capability StoryArc needs.

### Linux — GTK4 + libadwaita, or Avalonia

**Open.** Two coherent answers, and the choice depends on the Windows outcome:

- **GTK4 + libadwaita** is what looks native on GNOME, which is where most
  desktop Linux users are. It means a third implementation in a third language
  (Rust or Vala), which is the expensive answer.
- **Avalonia** shares one implementation with Windows. It will not look like a
  GNOME app, but Linux users tolerate that far more readily than macOS or
  Windows users would.

If the Windows spike picks Avalonia, Linux follows for nearly free and the
question closes. If it picks WinUI 3, Linux is a separate decision to be made on
its own merits.

## Consequences

- macOS is the cheapest desktop target and should be first.
- Windows and Linux are net-new implementations of the connector, parsing,
  download and sync layers, in a language neither mobile app uses. That is the
  real cost of desktop, and it is the reason desktop waits.
- The OpenSpec capability specs are already platform-neutral, so a desktop
  implementation has a written contract to build against from day one.
- Each desktop target gets `apps/desktop-<platform>/README.md` describing scope
  and open questions, so the intent survives without any code.

## Open questions

1. Does WinUI 3's rendering hold a finger-tracked page curl at 120 Hz? The page
   curl is the reader's signature interaction and a bad one is worse than none.
2. Can a Linux GTK4 build carry the same format support without re-solving
   EPUB and PDF rendering from scratch?
3. Is a desktop app the right shape at all, or does a self-hosted web reader
   against the same sources serve desktop users better for less?

## Revisit when

Both mobile apps have shipped 1.0. Not before.

## Links

- Scope per target: `apps/desktop-macos/README.md`,
  `apps/desktop-windows/README.md`, `apps/desktop-linux/README.md`.
- Related decisions: [ADR-0001](0001-independent-native-cores.md) — macOS shares
  the iOS codebase through SwiftUI, not through a cross-platform core.
- Specs: the capability specs in [`docs/openspec/specs/`](../openspec/specs) are
  platform-neutral, so a desktop target has a contract from day one.
