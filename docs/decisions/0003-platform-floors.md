---
status: accepted
date: 2026-08-24
deciders: Cédric Meyer
---

# ADR-0003 — iOS 26 and Android 12 as the minimum versions

## Context and problem statement

The two platforms pull in opposite directions here.

On iOS, the design language changed. Liquid Glass, the new tab and toolbar
behaviour, and scroll edge effects are iOS 26 APIs. Supporting iOS 18 means
writing every piece of chrome twice — once in the new material system and once
in the old one — and testing both. For an app whose entire premise is "it should
feel like it shipped with the OS", supporting the previous OS's look is
self-defeating.

On Android, the design language also changed, but Compose ships Material 3
Expressive as a library, not as an OS feature. It renders the same on Android 12
as on the newest release. The only thing that genuinely needs a recent OS is
**dynamic colour**, which arrived in Android 12 (API 31). Below that, Material
You has to fall back to a static palette.

`compileSdk` and `targetSdk` are both 37: Compose UI 1.12, which the current BOM
pins, refuses to be consumed by a project compiling against anything lower.

## Considered options

1. iOS 18 floor, chrome written twice.
2. iOS 26 floor, one material system.
3. Android floor below API 31.
4. Android API 31 floor.
5. One matched floor on both platforms.

### iOS 18 floor, chrome written twice

- Good, because it reaches devices that have not moved to iOS 26.
- Bad, because every piece of chrome exists in the new material system and in
  the old one, and both need testing.
- Bad, because shipping the previous OS's look defeats the premise of the app.

### iOS 26 floor, one material system

- Good, because there is one visual path and no `if #available` branch for design.
- Bad, because device reach drops until iOS 26 adoption climbs.

### Android floor below API 31

- Good, because it reaches older devices, and Compose renders Material 3
  Expressive identically that far back.
- Bad, because dynamic colour arrived in API 31. Below it, Material You falls
  back to a static palette.

### Android API 31 floor

- Good, because dynamic colour works on every supported version.
- Good, because it still covers four major versions with one visual path.
- Bad, because Android 11 and older are dropped.

### One matched floor on both platforms

- Good, because one number is easier to state.
- Bad, because the platforms need the floor for unrelated reasons. Matching them
  raises one floor for no requirement.

## Decision Outcome

| Platform | Minimum | Target | Reason for the floor |
| --- | --- | --- | --- |
| iOS | **26.0** | latest SDK | Liquid Glass is an OS-level material. There is no honest fallback. |
| Android | **API 31** (Android 12) | **API 37** | Dynamic colour. Below API 31 there is no wallpaper-derived scheme. |

The floors are asymmetric on purpose. They are set by what each platform
actually requires, not by a wish for them to match.

## Consequences

- **iOS:** no `if #available` branches for design. One material system, one
  visual path, one set of screenshots per appearance. The cost is device reach,
  which recovers on its own as iOS adoption climbs.
- **Android:** four major versions of reach with one visual path, because
  Compose renders Expressive identically across them. The single conditional is
  `dynamicColorScheme`, which is available on every supported version.
- **Testing matrix:** iOS is tested on the current and previous iPhone and iPad
  classes. Android is tested at API 31 and at the current API level, which is
  where behavioural differences actually live (storage, notifications,
  foreground services).
- Predictive back, edge-to-edge enforcement and photo-picker behaviour differ
  across the Android range. These are behavioural, not visual, and are covered
  by the API 31 and current-API test devices.

## Revisit when

- iOS 27 ships and iOS 26 adoption makes a floor bump free.
- Android 12 falls below a few percent of the install base, at which point the
  floor moves to whatever version the next capability actually needs.
- A Compose release raises the required `compileSdk` again — that is a routine
  bump of `compileSdk`/`targetSdk`, not a change to the `minSdk` floor.

## Links

- Spec: [`native-experience`](../openspec/specs/native-experience/spec.md) — the
  platform behaviour these floors buy.
- Related decisions: [ADR-0001](0001-independent-native-cores.md) makes an
  asymmetric floor possible, because neither app constrains the other.
- Contract: `AGENTS.md` §2 — iOS floor 26.0, Android floor API 31, target 37.
