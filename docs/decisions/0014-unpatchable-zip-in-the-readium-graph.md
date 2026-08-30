---
status: accepted — risk accepted
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
so there is no version to upgrade to.

The question this ADR was reopened to answer is narrower than "is it patched": **can the
vulnerable code be reached in this app at all?** A path traversal in an extraction routine
is a vulnerability only when the routine is called on an archive someone else wrote. If no
call path exists, the precondition never holds and there is nothing to exploit. That is
what was investigated, against the built artifact and the dependency sources rather than
against documentation.

### What the CVE actually is

One routine, and a specific one. The advisory text is generic, but the referenced report —
[marmelroy/Zip#245](https://github.com/marmelroy/Zip/issues/245) — and the commit that
closed it (`6940cebe`, 2023-11-23, "Protect against extracting files outside the
destination directory") both point at exactly one line of `Zip/Zip.swift`, inside
`Zip.unzipFile`:

```swift
let fullPath = destination.appendingPathComponent(pathString).path
```

`pathString` is the entry name read out of the archive. Nothing checks that the joined
path stays under `destination`, so `../../` in an entry name writes outside it. **The
vulnerability is a property of writing files to disk.** Code that reads a ZIP without
extracting it cannot express this bug.

### The package holds two modules, and only one of them is the vulnerability

This is where the earlier assessment was wrong, and the correction matters even though it
does not change the verdict.

`marmelroy/Zip` builds two targets: the Swift `Zip` module, which contains
`Zip.unzipFile`; and `Minizip`, the C ZIP reader from zlib's contrib tree. The package
exports one product, `Zip`, and depending on it pulls both.

`ReadiumShared` names `"Zip"` **to reach `Minizip`**, not to reach `Zip`:

- `Sources/Shared/Toolkit/ZIP/Minizip/MinizipContainer.swift:8` is `import Minizip`. It is
  the only `import Minizip` in the toolkit, and there is no `import Zip` anywhere in it.
- `MinizipContainer` is reached on the live path. `DefaultArchiveOpener` composes
  `ZIPArchiveOpener`, which tries `MinizipArchiveOpener()` **first** and falls back to
  `ZIPFoundationArchiveOpener()`. StoryArc's `EpubReaderOpening.swift:33` constructs
  `AssetRetriever(httpClient:)` with those defaults, so every EPUB the app opens is read
  by this C code.

So the package is not dead weight, and "nothing calls it" is false of the package. It is
true, and provably so, of the module that carries the CVE.

`MinizipContainer` performs **no filesystem writes at all** — no `createDirectory`, no
`createFile`, no `write`, no `appendingPathComponent` against a destination. It reads
entries into memory, keyed by `RelativeURL(zipEntryPath:)`. The traversal has nowhere to
land.

### Nothing calls the vulnerable module — checked, not assumed

Four independent checks, all repeated for this ADR rather than carried over.

**Source.** `grep -rn "import Zip"` returns nothing across `apps/`, `third_party/` and
`packages/`, and nothing across swift-toolkit 3.11.0's `Sources/`. No qualified use of
`Zip.unzipFile`, `Zip.quickUnzipFile` or any other `Zip` API exists in either tree.

**Static linkage.** A **release** build was made for this ADR — not only the debug build
the earlier assessment used, because dead-stripping might plausibly have removed the
module and it was worth knowing whether it does. It does not. The release binary defines
**213 `$s3Zip…` symbols**, including the real body of
`Zip.unzipFile(_:destination:overwrite:password:progress:fileOutputHandler:)` at a `T`
address, and has **zero undefined `$s3Zip…` symbols**. Zero undefined is the
machine-readable form of "present, and called by nobody".

> A trap for whoever repeats this: `nm … | grep -i zip` on the undefined symbols returns
> eight hits. All eight are `$ss12Zip2SequenceV…` — the Swift **standard library's**
> `zip(_:_:)`, module `s`. The library in question mangles as `3Zip`. Match on `$s3Zip`.

**Objective-C runtime.** This is the check the earlier assessment did not make, and it is
the one that closes dynamic reachability. `otool -o` over the release binary — the whole
Objective-C metadata region, classlist, method names, protocols — contains **no match for
"zip" at all**. The sources agree: no `@objc`, no `NSObject`, no `dynamic`, no `@_cdecl`
anywhere in `Zip/*.swift`. `NSClassFromString("Zip")` returns nil. There is no selector to
send and no class to instantiate by name.

**Dynamic Swift dispatch.** The only protocol conformance records the module emits are
`ZipCompression: Hashable/Equatable/RawRepresentable` and `ZipError: Hashable/Equatable/
Error` — stdlib protocols on Zip's own types. Nothing in the module conforms to any
Readium protocol, and it could not: the package depends on `Minizip` and nothing else, so
Readium's protocols are not in its scope. Neither Readium nor StoryArc contains a
`_typeByName` or `NSClassFromString` lookup that could resolve it. There is no
`__mod_init_func` section and no `__attribute__((constructor))` in the C sources, so
nothing in the module runs at launch.

Dead Swift code, with no Objective-C exposure, no foreign conformance and no static
initialiser, is genuinely unreachable. That is what this is.

### So the finding is reportorial, and stays that way

The residual risk is not exploitation. It is two future risks. Composition analysis of a
release build reports a high-severity CVE with no available fix and has to be re-triaged
by hand each time. And the day a Readium release, or a StoryArc file, reaches for the
module that is already linked, it inherits the traversal.

## Decision drivers

- The app's largest attack surface is a publication file someone else made
  (`SECURITY.md`). A ZIP path traversal is exactly the shape of that threat — which is
  why reachability had to be settled properly rather than assumed.
- Readium is the reflowable-EPUB engine ([ADR-0005](0005-format-and-rendering-libraries.md)),
  and is not being replaced over this.
- The repository already refuses to carry a fork of anything: every third-party edge is
  either a released package or vendored sources with a written refresh procedure
  ([ADR-0010](0010-smb-clients.md)).
- Whatever is chosen has to survive the next Readium upgrade without anyone remembering
  this document.
- A fix must not trade a risk that is provably zero for one that is not.

## Considered options

1. Accept it, guard the reachability, and record the assessment
2. Ask upstream to drop the dead target dependency
3. Fork or patch swift-toolkit
4. Shadow `Zip` with a local stub package of the same identity
5. Pin `marmelroy/Zip` to the upstream commit that fixes it
6. Move to a swift-toolkit that no longer carries the edge

### 1. Accept it, guard the reachability, and record the assessment

- Good, because the exposure is reportorial and this says so in writing with the evidence,
  so the next scanner hit is triaged in seconds rather than re-investigated.
- Good, because the SwiftLint rule `no_marmelroy_zip` fails the build the moment any
  StoryArc source imports the module, which is the only way the exposure becomes real
  from inside this repository.
- Bad, because the CVE keeps being reported against release builds, and the guard covers
  StoryArc's own sources only — a future Readium release that starts calling `Zip` would
  pass it.

### 2. Ask upstream to drop the dead target dependency

- Good, because it fixes the reporting problem for everyone at the source.
- Bad, because it is **not the one-line change the previous draft claimed.** Readium needs
  `Minizip`, and the Zip package exports no `Minizip` product — only `.library(name:
  "Zip", targets: ["Zip"])`. Dropping the edge means Readium vendors minizip itself, or
  persuades an unmaintained project to publish a second product. Neither is small, and
  neither is ours to schedule.
- Bad, because publishing an issue against another project's repository is an
  outward-facing act that needs a person to make it.

### 3. Fork or patch swift-toolkit

- Good, because it removes the module from the binary now.
- Bad, because a fork of the EPUB engine is a permanent maintenance burden taken on for a
  dependency nothing calls, and every Readium upgrade becomes a rebase.
- Bad, because it contradicts how every other dependency here is handled.

### 4. Shadow `Zip` with a local stub package of the same identity

- Good, because SwiftPM would resolve the local package over the remote one and the
  vulnerable code would genuinely leave the build.
- **Fatal, and worse than the previous draft understood.** A stub of the `Zip` product
  would have to supply a working `Minizip` too, because `ReadiumShared` imports it and
  reads every EPUB through it. The stub is not a stub; it is a silent replacement of the
  app's live EPUB reader with something Readium has never been tested against.
- Bad, because the dependency graph would contain something called `Zip` that is not Zip,
  misleading a reviewer or an SCA tool in the dangerous direction.

### 5. Pin `marmelroy/Zip` to the upstream commit that fixes it

Established for this ADR, and it works. The fix is not hypothetical and the pin is not a
fork — it is the upstream repository at an upstream commit.

- The whole difference between the released `2.1.2` and master (`bca30f6d`, 2024-02-14) is
  **two commits: the traversal fix and its test.** Six added lines in `Zip/Zip.swift`, one
  test, one fixture. `Zip/minizip/**` is untouched, so the code the app actually executes
  would be byte-identical.
- SwiftPM accepts it. A scratch package declaring swift-toolkit `exact: "3.11.0"` next to
  `.package(url: "…/Zip.git", revision: "bca30f6d…")` resolves cleanly: swift-toolkit at
  3.11.0, Zip at `bca30f6d`. The revision requirement wins over the transitive
  `from: "2.1.2"`.
- Licence is unchanged: MIT, same as 2.1.2.
- Good, because the vulnerable routine would leave the binary entirely, replaced by the
  patched one.
- Bad, because it pins to an unreleased commit of a project whose maintainer has not
  answered [issue #256](https://github.com/marmelroy/Zip/issues/256), open since January
  2024, asking whether it is still maintained. A tag is a promise; a commit on a branch is
  not. A force-push or a deleted repository breaks the build.
- Bad, because it contradicts ADR-0010's rule that a third-party edge is a released
  package or vendored sources — this would be the repository's first revision-pinned
  dependency, which is a policy change, not a bug fix.
- Bad, because it probably does not even silence the scanner: SCA tools key on a resolved
  version, and a revision pin is reported as an unknown version or resolved back to the
  range it sits in.
- Bad, because the pin needs its own guard. Nothing today would notice if the next
  swift-toolkit bump quietly dropped it and restored the vulnerable code, and
  `pnpm lockfile:ios` checks only that the app lockfile matches the manifests.
- Bad, because it buys nothing an attacker can reach. It trades a risk measured at zero
  for a supply-chain risk that is small but not zero.

### 6. Move to a swift-toolkit that no longer carries the edge

Checked, and there is no such version.

- `main` today still declares `.package(url: "https://github.com/marmelroy/Zip.git",
  from: "2.1.2")` and still names `"Zip"` in `ReadiumShared`'s dependencies.
- The newest tag of any kind is the pre-release **4.0.0-alpha.1** (2026-08-14). Its
  `Package.swift` carries the same two lines.
- swift-toolkit's manifest is `swift-tools-version:5.10` and declares no package traits
  and no conditional dependencies, so there is no build configuration that could exclude
  the module.
- `marmelroy/Zip` has published no release since 2.1.2 (2022-02-23), so there is no newer
  version for anyone to move to.
- No issue exists on readium/swift-toolkit about this dependency. Opening one is left to a
  person; acting on another project's tracker is not this repository's to do.

## Decision Outcome

**Option 1, with the guard strengthened. The finding is closed as not exploitable, and the
residual reporting risk is accepted.**

The owner asked whether exploitation is "already almost impossible with how the app
currently works". It is not almost impossible; it is impossible, and the reason is
structural rather than incidental. CVE-2023-39135 lives in `Zip.unzipFile`, a routine that
extracts an archive to disk. The release binary contains that routine and **zero undefined
references to it**, exposes **no Objective-C metadata whatsoever** for the module, emits no
conformance any foreign generic could dispatch through, and runs no static initialiser
from it. The one part of the package that does execute — the `Minizip` C reader, on every
EPUB opened — writes no files, which is the precondition the traversal needs. There is no
input a reader can be handed that reaches the vulnerable line.

What was changed: `no_marmelroy_zip` in `.swiftlint.yml` now catches every spelling of the
import rather than one. The old regex matched a bare `import Zip` alone on a line. Against
a fixture of eight reachability spellings it fired twice, missing
`@_implementationOnly import Zip`, `@preconcurrency import Zip`, `import class Zip.Zip`,
an import with a trailing comment, and both qualified call sites. The rule now fires on
all eight, and still ignores `import ZIPFoundation`, `import ZipArchive`, and comments or
string literals that merely name the ban.

Explicitly **not** options 3 or 4. A fork turns every Readium upgrade into a rebase, and
the stub is now understood to be far worse than the previous draft thought — it would
have to replace the live EPUB reader, not stub out dead code.

Explicitly **not** option 5, for now, though it is verified and available in one line. It
would replace the vulnerable routine with the patched one at no cost to any code that
runs. It is declined because the risk it removes is measured at zero and the risk it adds
is not: a revision pin on an unmaintained repository, the repository's first departure
from ADR-0010's released-package rule, an SCA report that probably does not change anyway,
and a pin nothing would notice losing. If the owner would rather hold the patched code
than the assessment, this is a small and reviewable change — it belongs in
`apps/ios/Packages/StoryArcEpub/Package.swift` beside the swift-toolkit pin, and it needs
a check that a later Readium bump cannot silently drop it.

Revisit if any of these becomes true: Readium starts calling `Zip`, which
`no_marmelroy_zip` would **not** catch and which is worth a grep whenever the pin in
`apps/ios/Packages/StoryArcEpub/Package.swift` moves; `marmelroy/Zip` publishes 2.1.3 or
later, at which point option 5 becomes an ordinary version bump with none of its
objections; a swift-toolkit release drops the edge; or the project adopts an SCA gate, at
which point the finding stops being a manual triage and becomes a build failure that has
to be answered one way or the other.

## Consequences

- Positive: the assessment is written down with the evidence and the commands that
  produced it, so the next person who sees CVE-2023-39135 in a scan does not re-derive it.
- Positive: `no_marmelroy_zip` makes the unreachability a build gate rather than a habit,
  and now covers the import spellings that would have slipped past it.
- Positive: the record no longer misdescribes which code runs. `Minizip` from this package
  reads every EPUB the app opens; that is worth knowing for its own sake, and it was
  previously credited to ZIPFoundation.
- Negative: a library with an open advisory stays in the shipped binary, and release-build
  composition analysis will keep reporting it. This is the accepted risk.
- Negative: the guard covers StoryArc's sources only. A Readium upgrade that begins using
  `Zip` would not trip it.
- Neutral, and outside this finding: the `Minizip` sources in this package are the zlib
  contrib reader dated **February 2010**, and they parse untrusted archives on the live
  EPUB path. Nothing here assessed them. They are not CVE-2023-39135 and were not in
  scope; if an archive-parsing hardening pass is ever scheduled, they belong in it.

## Links

- [ADR-0005](0005-format-and-rendering-libraries.md) — why Readium renders reflowable EPUB
- [ADR-0008](0008-ranged-reads-and-own-zip-reader.md) — why StoryArc reads ZIP itself
- [ADR-0010](0010-smb-clients.md) — the released-package-or-vendored rule
- `docs/delivery/security-review-2026-08-30.md`, rank 20
- GHSA-g454-wj9r-jpg4 / CVE-2023-39135
- [marmelroy/Zip#245](https://github.com/marmelroy/Zip/issues/245) — the report, naming
  `unzipFile`; fixed by `6940cebe`, never released
