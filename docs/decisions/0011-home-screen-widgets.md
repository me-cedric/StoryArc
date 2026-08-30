---
status: accepted
date: 2026-08-30
deciders: Cédric Meyer
---

# ADR-0011 — Home-screen widgets wait for a shared snapshot, and for a signing team

**Accepted as a deferral. No widget code is written, and no widget dependency is
added, until the two prerequisites below are met.**

## Context and problem statement

[`native-experience`](../openspec/specs/native-experience/spec.md) names widgets
among the system affordances StoryArc must use rather than invent:

> the system one is used — share sheet, document picker, context menu, haptics,
> quick actions, widgets, Handoff on iOS, and predictive back on Android

Quick actions and Handoff are now built. Widgets are the remaining name on that
list, and they are the one that is not a few lines of platform vocabulary over
logic the app already has. Both platforms need **new build machinery** — a
second Xcode target on iOS, a new dependency and a manifest receiver on Android
— and, more importantly, both need something the app does not currently produce:
**a small, self-contained description of "what am I reading" that a second
process can read.**

That last point is the whole of this decision. A quick action needed nothing new
because the system stores the menu and hands the app back an identifier; the app
itself does the work, in its own process, with its own stores. A widget is not
the app. It is a separate renderer with its own lifetime, woken by the system
when the app is not running, and everything StoryArc knows is behind a door it
cannot open.

### What a widget cannot reach today

| What a widget would show | Where it lives now | Why the widget cannot read it |
| --- | --- | --- |
| The publication being read | `ProgressStore`, a SwiftData store in the app container / a Room database in the app's data directory | On iOS an extension sees only its own container and any **App Group** container. The store is in neither. |
| The cover | `LibraryCache`, in the caches directory, keyed by publication and pixel size | Same door on iOS; on Android it is readable, but it is a cache the system may evict between the app's last run and the widget's next refresh. |
| The file itself | A security-scoped bookmark, or a SAF tree grant | Neither travels. A bookmark resolves in the process that made it; a SAF grant belongs to the app, not to a `RemoteViews` host. A widget does not need to *open* a book — but it does need to stop pretending it could. |

None of this is a reason not to have widgets. It is the reason a widget is a
data problem before it is a UI problem, and the reason "add WidgetKit" is not
the first step.

### The second blocker, iOS only

An App Group is an entitlement, and an entitlement needs a provisioning profile
that grants it. `project.yml` says, in its own words, that there is no
development team yet, and signs ad-hoc — which is exactly the configuration that
already cost this project a working keychain once, silently, on every simulator
build anyone had run. A widget extension built without a real team would either
fail to launch or read an empty container, and it would do so quietly.

## Decision drivers

- The spec names widgets; it does not say when.
- A widget that shows a stale or empty book is worse than no widget: it is the
  app claiming to know something it does not.
- ADR-0001 forbids a shared implementation, so this is two widgets, not one —
  and therefore twice the machinery for the same promise.
- No backend, no account (`AGENTS.md` §2). Whatever a widget reads is on the
  device and was put there by the app.
- Nothing here has been seen on a device. A widget is *only* visible on a device.

## Considered options

1. Build both widgets now
2. Build one widget now, the other later
3. Defer both, and record why — with the prerequisites named
4. Build the shared snapshot now and the widgets later

### 1. Build both widgets now

- Good, because the spec's list would be complete.
- Bad, because it front-loads the machinery and leaves the data problem to be
  solved twice under deadline: an App Group and a migration of the progress
  store on iOS, a Glance dependency and a refresh policy on Android.
- Bad, because `androidx.glance` would join a Compose graph already pinned to a
  **material3 1.5.0 alpha** for `MaterialExpressiveTheme`. `glance-material3`
  carries its own material3 constraint, and a resolution conflict there would be
  paid for by every module, not just the widget.
- Bad, because none of it could be verified. There is no simulator or emulator
  in this loop, and a widget has no unit-testable surface worth the name — its
  whole behaviour is "what does the home screen draw when the app is not
  running".

### 2. Build one widget now, the other later

- Good, because it would prove the shape once before paying for it twice.
- Bad, because it is exactly the asymmetry this repository exists to avoid: two
  apps that answer the same promises. A widget on one platform and not the other
  is a capability row that reads "partial" for a reason nobody can act on.

### 3. Defer both, and record why

- Good, because it is honest, and because the prerequisites are real work that
  can be scheduled on its own.
- Good, because the quick-action work just landed already covers the *commonest*
  reason a reader wants a widget — "get me back into my book from the home
  screen" — through an affordance that needs no second process and no shared
  container.
- Bad, because a named spec affordance stays unbuilt, and `native-experience`
  keeps a gap in its STATUS row.

### 4. Build the shared snapshot now and the widgets later

- Good, because the snapshot is the hard half and is testable without a device.
- Bad, because a snapshot with no reader is dead code, and the Active File Rule
  exists to stop exactly that. Its shape should be decided by the widget that
  consumes it, not guessed at a release early.

## Decision Outcome

We chose **option 3: defer both, with the prerequisites written down.**

Because the blocking work is not widget work. It is a shared snapshot and an iOS
signing team, and neither is made easier by having a half-built extension target
in the tree while it happens. And explicitly **not** option 1, because building
the widgets first would mean solving the container problem twice, in a hurry,
with no device to check either answer on — and **not** option 4, because a
snapshot nothing reads is a file the next agent has to guess the purpose of.

### The prerequisites, named

1. **A shared reading snapshot.** One small record — publication identifier,
   display title, series, fraction read, and a cover already decoded to a
   widget-sized image — written by the app whenever the reading position
   changes, and read by nothing else. Small enough to be a single file, so that
   a widget's read is a file read rather than a database open. It is the same
   fact `QuickActions.offered(continuing:hasDownloads:)` already computes, and
   the pure part of it belongs beside that in `StoryArcCore` / `core:model`,
   mirrored and unit-tested on both platforms.
2. **On iOS: an App Group, and a development team to provision it.** The
   snapshot and the widget-sized cover go in the group container; the SwiftData
   store and the caches directory do not move. The team is not optional — see
   the keychain incident recorded in `project.yml`.
3. **On Android: a Glance version resolved against the pinned material3 alpha,**
   checked before the dependency is added rather than after.
4. **A device or an emulator.** A widget's only surface is a home screen. This
   decision may be revisited by anyone who has one; it should not be implemented
   by anyone who does not.

### Consequences

- **Positive.** `native-experience` keeps one honest gap instead of two
  half-built extension targets, and no dependency is added for a feature nobody
  can look at.
- **Positive.** The reader is not left with nothing: the home-screen quick
  actions offer continue-reading by name, the library and downloads, and they
  survive the app being killed because the system stores them.
- **Negative.** A named affordance in the spec stays unmet, and the STATUS row
  for `native-experience` stays `partial` for that reason among others.
- **Negative.** Readers who expect a cover on their home screen do not get one,
  and the app gives no hint that it ever will.
- **Neutral / follow-up.** The snapshot in prerequisite 1 is worth writing
  whether or not widgets follow: a Live Activity, a complication, a Glance tile
  and an Assistant answer all want the same record, and each of them is a second
  process too.

## Links

- Spec: [`native-experience`](../openspec/specs/native-experience/spec.md) —
  "System integration"
- Related decisions: [ADR-0001](0001-independent-native-cores.md) (two widgets,
  not one), [ADR-0003](0003-platform-floors.md) (WidgetKit and Glance are both
  available at the floors), [ADR-0006](0006-progress-storage-and-sync.md) (the
  identity the snapshot would carry)
