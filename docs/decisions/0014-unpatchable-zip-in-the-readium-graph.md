---
status: proposed
date: 2026-08-30
deciders:
---

# ADR-0014 — An unpatchable ZIP library ships inside the iOS binary, and nothing calls it

## Context and problem statement

The iOS app links [marmelroy/Zip](https://github.com/marmelroy/Zip) 2.1.2. It is not a
dependency StoryArc declares: `readium/swift-toolkit` names `"Zip"` as a target
dependency of `ReadiumShared` (`Package.swift:27` and `:42`), and StoryArcEpub consumes
`ReadiumShared`, so the module travels with it.

Zip 2.1.2 carries **CVE-2023-39135** (GHSA-g454-wj9r-jpg4): a crafted archive entry name
gives a path traversal on unzip. The advisory's vulnerable range is `<= 2.1.2`, and its
`first_patched_version` is **null** — 2.1.2 has been the newest tag since February 2022,
so there is no version to upgrade to. This is not a stale pin; it is a library with an
open advisory and no maintainer response.

Three things were established rather than assumed:

- **Nothing in Readium calls it.** In swift-toolkit 3.11.0's `Sources/`, `grep -rn
  "import Zip"` and `grep -rn "quickUnzip|unzipFile|Zip\.unzip"` both return nothing.
  The ZIP reading Readium actually performs goes through
  `readium/ZIPFoundation` 3.0.1, which carries the CVE-2023-39138 containment fix.
- **Nothing in StoryArc calls it.** No source under `apps/ios/` imports `Zip`, and
  [ADR-0008](0008-ranged-reads-and-own-zip-reader.md) replaced ZIPFoundation with the
  app's own ranged-read ZIP reader for CBZ, so there was never a reason to.
- **It is nonetheless in the shipped Mach-O.** A simulator build of the app was
  inspected: `StoryArc.app/StoryArc.debug.dylib` defines 259 `$s3Zip…` symbols,
  including `Zip.unzipFile(_:destination:overwrite:password:progress:fileOutputHandler:)`
  itself. There are **zero undefined `$s3Zip…` symbols**, which is the machine-readable
  form of "present, and called by nobody".

So the risk today is not exploitation — there is no path from a publication to
`Zip.unzipFile`. The risk is two future ones: any composition analysis of a release build
reports a high-severity CVE with no available fix and has to be re-triaged by hand every
time, and the day a Readium release, or a StoryArc file, reaches for the module that is
already linked, it inherits a path traversal on attacker-supplied entry names.

Removing the dependency would be the real fix. The edge is declared by upstream, so
removing it is not something this repository can simply do.

## Decision drivers

- The app's largest attack surface is a publication file someone else made
  (`SECURITY.md`). A ZIP path traversal is exactly the shape of that threat.
- Readium is the reflowable-EPUB engine ([ADR-0005](0005-format-and-rendering-libraries.md)),
  and is not being replaced over this.
- The repository already refuses to carry a fork of anything: every third-party edge is
  either a released package or vendored sources with a written refresh procedure.
- Whatever is chosen has to survive the next Readium upgrade without anyone remembering
  this document.

## Considered options

1. Accept it, guard the reachability, and record the assessment
2. Ask upstream to drop the dead target dependency
3. Fork or patch swift-toolkit
4. Shadow `Zip` with a local stub package of the same identity

### 1. Accept it, guard the reachability, and record the assessment

- Good, because the exposure is reportorial today and this says so in writing, so the
  next scanner hit is triaged in seconds rather than re-investigated.
- Good, because the SwiftLint rule `no_marmelroy_zip` fails the build the moment any
  StoryArc source imports the module, which is the only way the exposure becomes real
  from inside this repository.
- Bad, because the CVE keeps being reported against release builds, and the guard covers
  StoryArc's own sources only — a future Readium release that starts calling `Zip` would
  pass it.

### 2. Ask upstream to drop the dead target dependency

- Good, because it fixes the problem for everyone, permanently, at the source.
- Good, because the change is trivially small — one line of `Package.swift` — and the
  evidence that nothing uses it is easy for a maintainer to confirm.
- Bad, because the timeline is not ours, and publishing an issue against another
  project's repository is an outward-facing act that needs a person to make it.

### 3. Fork or patch swift-toolkit

- Good, because it removes the module from the binary now.
- Bad, because a fork of the EPUB engine is a permanent maintenance burden taken on for a
  dependency nothing calls, and every Readium upgrade becomes a rebase.
- Bad, because it contradicts how every other dependency here is handled.

### 4. Shadow `Zip` with a local stub package of the same identity

- Good, because SwiftPM would resolve the local package over the remote one and the
  vulnerable code would genuinely leave the build.
- Bad, because the dependency graph would then contain something called `Zip` that is not
  Zip. A reviewer, an SCA tool, or the next maintainer would be misled — in the more
  dangerous direction, since the graph would look clean.
- Bad, because it silently diverges from what Readium was tested against.

## Decision Outcome

**Not yet decided — this ADR exists to put the choice in front of a person.**

The recommendation is **option 1 now, option 2 alongside it**: keep the guard and the
written assessment, and open an upstream issue asking that the unused `"Zip"` target
dependency be dropped from `ReadiumShared`. Opening that issue is a public act on another
project's tracker, so it is left for a maintainer to do rather than done automatically.

Explicitly **not** option 3 or option 4. Neither buys anything a caller can reach today,
and both cost more than the exposure: a fork turns every Readium upgrade into a rebase,
and a same-identity stub makes the dependency graph lie about itself, which is worse than
a graph that is honestly uncomfortable.

Revisit if any of these becomes true: Readium starts calling `Zip`; a patched Zip release
appears; or the project adopts an SCA gate, at which point the finding stops being a
manual triage and becomes a build failure that has to be answered one way or the other.

## Consequences

- Positive: the assessment is written down with the evidence that produced it, so the
  next person who sees CVE-2023-39135 in a scan does not re-derive it.
- Positive: `no_marmelroy_zip` in `.swiftlint.yml` makes the unreachability a build gate
  rather than a habit.
- Negative: a known-vulnerable, unmaintained library stays in the shipped binary, and
  release-build composition analysis will keep reporting it.
- Neutral: the guard covers StoryArc's sources only. A Readium upgrade that begins using
  `Zip` would not trip it, so `import Zip` in swift-toolkit is worth a look whenever the
  pin in `apps/ios/Packages/StoryArcEpub/Package.swift` moves.

## Links

- [ADR-0005](0005-format-and-rendering-libraries.md) — why Readium renders reflowable EPUB
- [ADR-0008](0008-ranged-reads-and-own-zip-reader.md) — why StoryArc reads ZIP itself
- `docs/delivery/security-review-2026-08-30.md`, rank 20
- GHSA-g454-wj9r-jpg4 / CVE-2023-39135
