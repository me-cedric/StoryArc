# StoryArc — Project Context

StoryArc is a pair of native reading apps — iOS (Swift / SwiftUI) and Android
(Kotlin / Jetpack Compose) — for comics, manga, graphic novels and ebooks.

## What it is

A reader that opens what you already own, from wherever you keep it: a folder on
the device, iCloud Drive or the Files provider of your choice, an SMB share on a
NAS, an OPDS catalogue, or a Kavita server. It caches what it finds, downloads
what you ask it to, remembers where you stopped, and syncs that back when the
source can hold it.

## Non-negotiables

1. **It must feel stock.** A person who has never opened StoryArc should be able
   to use it because it behaves the way every other app on their phone behaves.
   Platform navigation, platform gestures, platform materials, platform
   accessibility. iOS gets Liquid Glass; Android gets Material 3 Expressive. No
   shared cross-platform UI layer, ever.
2. **The artwork is the interface.** Chrome recedes, auto-hides, and never
   competes with a cover or a page.
3. **Free, no accounts, no telemetry.** StoryArc has no backend of its own. It
   talks to servers the user already runs.
4. **Offline is a normal state, not an error.** Every source can vanish; the
   library stays browsable and downloaded titles stay readable.

## Architecture in one paragraph

Two independent native codebases. They share three things and nothing else:
these specs, the design tokens in `packages/design-tokens`, and the test-fixture
corpus in `packages/test-fixtures`. Each app uses the best library its own
platform offers rather than a lowest-common-denominator shared core. See
[ADR-0001](../docs/decisions/0001-independent-native-cores.md).

## Platform floors

| Platform | Minimum | Target |
| --- | --- | --- |
| iOS | 26.0 | latest SDK |
| Android | 12 (API 31) | API 36 |

## Conventions

- Requirements are written against **user-observable behaviour**, not
  implementation. "The app SHALL resume within 2 taps", not "the app SHALL use
  SwiftData".
- Where a requirement is genuinely platform-specific, it says so explicitly.
- Anything not yet decided is an open question in the capability's spec, never a
  silent assumption.
