# Design

## Context

See [`proposal.md`](proposal.md) for why. What the approach has to work with:

**The leak is one architectural seam, not scattered chrome.** Twenty-nine of the
thirty literals are refusal prose, and every one is produced in a
format-parsing layer that owns no string catalogue, then carried as a `String`
into a view that draws it verbatim. The census, verified against the tree on
2026-09-05:

| Where | iOS | Android |
| --- | --- | --- |
| Scanner and indexer reasons | 9 — `Formats/LibraryScanner.swift`, `PublicationIndexer.swift`, `PublicationIndexer+Building.swift` | 12 — `core/format/LibraryScanner.kt`, `PublicationIndexer.kt` |
| Refused-file alert | 6 — `App/RefusedFile.swift` | 1 — `app/OpenedFile.kt`, a name fallback; the dialog itself is localised |
| Reader open failure | 0 — no such surface | 2 — `feature/reader/ReaderViewModel.kt` |

The two render sites are `LibraryFeature/SkippedNotice.swift:83,173` and
`feature/library/SkippedNotice.kt:158,233`. Neither invents a word; both draw
what the layer handed them.

**The type is what permits the prose.** Both platforms carry the identical
mirrored shape — `PublicationIndexer.IndexError.unreadable(reason: String)` and
`IndexException.Unreadable(val reason: String)`. A free-form `String` on an error
case is an invitation to write a sentence there, and seven were written.

**The layer has no catalogue and should not get one.** `StoryArcKit/Sources/Formats`
ships no `Localizable.xcstrings`, and `pnpm strings:ios` reads one table per
module, so putting keys there would mean a second table for a module that draws
nothing.

**One of the seven reasons is already a divergence.** iOS says *it is protected
by its store's content protection*; Android says *this audiobook is protected by
its store's content protection*. The mirrored layer AGENTS.md §7 warns about has
already drifted, in the sentence a reader reads.

**Prior art is on the shelf.** Android's `RefusedFileDialog.kt` is the same alert
as iOS's `RefusedFile.swift` and is fully localised. The target shape does not
have to be invented.

## Goals / Non-goals

**Goals.** Make it impossible to write reader-visible prose in a layer that
cannot translate it; give the two apps one wording per state; leave a check
behind that fails when either rule is broken again.

**Non-goals, at the design level.** No new dependency, no new module, no change
to how either app looks or lays out. No renamed keys — this change writes values
and adds keys, so no view has to move with it. No change to what the format layer
*detects*; only to how it says so.

## Decisions

### 1. The error type carries a cause, not a sentence

`unreadable(reason: String)` becomes a closed set of cases, mirrored on both
platforms. The closed set is already visible in the code — seven reasons are
constructed in total and nothing else ever is:

*not there* · *format not recognised* · *archive password protected* ·
*archive unreadable* · *PDF unopenable* · *unsupported format (names it)* ·
*content protected*.

The view module maps a case to a key. The format layer loses the ability to hold
a sentence, which is the point.

**Why over the alternative.** The obvious cheaper fix is to give the format layer
a catalogue and localise the strings in place. Rejected: it puts reader-facing
wording in a module that draws nothing, it needs a second string table on iOS for
a module with no views, and it leaves the `String` on the case — so the next
reason written there is English again and nothing notices. Typing the boundary is
the fix that cannot regress.

**Concretely.** iOS: `String(localized:bundle:locale:)` against
`LibraryFeature/Resources/Localizable.xcstrings` with the `.storyArc` locale the
module already uses. Android: `stringResource(R.string.…)` against
`feature/library/src/main/res/values*/strings.xml` in all four locales. Both are
what the surrounding code already does; nothing new is introduced.

**Mirrored, therefore doubled.** AGENTS.md §7 names this layer the drift hotspot
and requires the two codebases to move together, unit tests included, case for
case. The case set and the key names are the same on both sides so the mirror
stays checkable by reading.

### 2. `content protected` is reconciled to Android's wording

Android names the kind of thing — *this audiobook is protected by its store's
content protection* — and iOS says *it*. The requirement's *more informative one
wins* clause settles it toward Android. Content protection only ever applies to
audio here, so naming it costs nothing and reads better in a list where each row
already carries a file name.

### 3. The Android reader failure stops rendering `cause.message`

`ReaderViewModel.kt:437,495` assigns `cause.message ?: "could not be opened"` to
what the reader is shown, so internal exception prose from anywhere in the format
layer reaches the screen — `not a pdf`, `no file descriptor for …`, `page has no
size`. It becomes a translated general refusal, per the spec's *A failure with no
sentence written for it*.

**This is a behaviour change a reader can see, and it removes information.** That
is deliberate: the information it removes was written for a maintainer, and the
diagnostic export is where a maintainer gets it. iOS has no equivalent surface,
so this one is Android-only and the handoff must say so.

**Sizing note, not a decision.** How many distinct messages are reachable through
that line is a count, not a guess, and it is a task. It does not change the
approach — one general refusal replaces all of them either way.

### 4. The gate is the type system first, a script second

A script cannot reliably tell a user-visible sentence from an internal one: the
census found **zero** bare literals in a `Text(`/`contentDescription` position on
either platform, because every leak arrived through a variable. A grep-shaped
check would have passed on all thirty.

So the enforcement splits:

- **Decision 1 is the real gate.** With no `String` on the case, the compiler
  refuses the prose. This covers the twenty-one scanner and indexer hits.
- **A script guards the residual surface** — bare literals in the small set of
  positions that draw text directly (`Text(`, `alert(`, `Button(` labels,
  `accessibilityLabel`, `contentDescription =`). That is the surface
  `RefusedFile.swift` leaked through, it is cheap to check, and it is where a new
  leak is most likely.

It ships as a Node script in `scripts/` beside `delta-drop-check.mjs` and
`partial-tasks-check.mjs`, wired into `pnpm lint`, with a `--self-test` — AGENTS.md
§5 requires a guard to be proved able to fail in the change that adds it, and
names three checks in this repository that could not.

**Known limit, stated rather than hidden.** The script cannot see a sentence that
reaches a view through a variable from a layer that is still allowed to hold one.
It is a backstop for the surface, not a proof of completeness. Saying so is the
difference between this check and the vacuous ones §5 catalogues.

### 5. Divergence is reconciled from a measured list, not by eye

629 keys pair across the two catalogues by name; 595 carry identical English; **34
do not**. That list is the work item, and it needs triage rather than wholesale
application — the census already contains at least three the platform forces
(*Reduce Motion* is the iOS setting's name, *Remove animations* is Android's;
iCloud Drive against Google Drive) and roughly nine that are placeholder syntax
rather than wording (`%lld` against `%1$d`).

**34 is a floor, not a total.** The publication page's vocabulary pairs on no key
at all — iOS composes place plus availability clause, Android ships four whole
sentences plus a wrapper — so it is invisible to a name-based comparison. It is
handled as its own item, ordered after `publication-detail` archives, because its
requirements are still in that change's delta and not yet in a main spec.

## Accessibility consequences

- **Fixing the string fixes the announcement.** Both skipped notices group with
  `accessibilityElement(children: .combine)` and its Android equivalent, so a
  screen reader today speaks the same untranslated English the screen shows.
  There is no second string to fix and no separate task; the spec states it so
  the tick has to cover it.
- **The translations are longer, and the notice is a compact banner.** German and
  Spanish renderings of *the archive is password protected* will exceed the
  English. `localization`'s *Long translations* is the one scenario STATUS.md
  records as unsettled, and Spanish — not German — is this app's measured worst
  case. Both notices need a capture at the largest text size in Spanish, not a
  reasoned assurance.
- **A general refusal must still be a refusal.** Replacing `cause.message` with
  one sentence must not produce a screen that announces nothing; the sentence
  carries the same weight in the reading order the raw text had.

## Risks / Trade-offs

- **Half a seam is worse than none.** A skipped list where some reasons are
  translated and some are not is a visible mixture in one column. → Each seam is
  one task with one validation, and the spec has a scenario for exactly this.
- **The mirrored layer drifts while being fixed.** Two platforms, one case set,
  and this layer has already produced one silent cross-platform divergence. →
  Same case names, same key names, and the existing mirrored unit tests are
  updated case for case in the same task, per AGENTS.md §7.
- **The new script becomes a vacuous check.** Three in this repository already
  did. → `--self-test` in the same change, and the task list requires watching it
  fail by name before it is trusted.
- **Removing `cause.message` removes a diagnostic somebody relies on.** → It
  survives in the diagnostic export, which is English by explicit design and is
  where a maintainer looks.
- **Reconciling 34 divergences by fiat changes wording nobody asked to change.**
  → Triage first, and a deliberate platform difference is recorded as deliberate
  rather than flattened; the spec's *a difference the platform forces* clause
  exists for this.
- **`pnpm lint` gains a check while eight changes are in flight.** A new gate
  that fails on pre-existing code blocks everyone. → The script lands only after
  the literals it would report are gone.

## Migration plan

No data migration, no persisted format, nothing to roll back at runtime — the
change is text and the types behind it. Ordering that keeps the tree green:

1. Type the boundary and localise the scanner and indexer reasons, per platform,
   each platform's mirrored tests moving with it.
2. The iOS refused-file alert, against Android's already-localised dialog.
3. The Android reader failure.
4. Triage and reconcile the 34-key divergence list.
5. Retire the two dead keys.
6. Add the script and prove it fails, once nothing it reports is left.

The publication page's reconciliation is ordered after `publication-detail`
archives and is the one item that can be deferred to a follow-up without leaving
a seam half-done — it is a divergence between platforms, not within a list.

## Open Questions

- **What is the destination holding offline-readable publications called?**
  Carried from the spec's `[NEEDS CLARIFICATION]`. iOS ships *Nothing in your
  library is on this device yet* and Android *Nothing in your library can be read
  without a connection*; direction §8.4 records the choice as an owner decision
  never taken. It changes wording only, so the approach and the task breakdown
  stand either way — but the reconciliation task for that destination cannot
  close until it is answered.
- **Does `theme.pageColour.ratio` keep its arithmetic?** Direction §5 asks for
  *Contrast %@ to 1* to become three plain bands. `reading-themes` / *Custom
  colour* requires a refused pairing be stated "with the measured ratio stated",
  and `reader-theming-and-page-transitions` already holds a MODIFIED block on
  that requirement, so a second one is the shape `pnpm delta:drop` catches. Out
  of scope here; it needs the owner, and then a delta on that change rather than
  on this one.
- **Which of the 34 divergences are deliberate?** Triage is a task in this change
  and the answer does not change the approach, but a handful will be judgement
  calls the owner may want to see — *Continue reading* against *Keep reading* on
  the home surface is the clearest.
