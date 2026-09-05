# One vocabulary, in four languages

## Why

StoryArc ships in English, French, German and Spanish, and a reader in French is
today shown thirty English sentences the localisation gate is structurally unable
to see — every one of them a refusal, which is the moment a reader most needs to
be told something they understand. Separately, the two apps have drifted into two
dialects: thirty-four paired keys carry different English on iOS and Android, and
the publication page's vocabulary pairs on no key at all, because one platform
composes a sentence from clauses and the other ships whole sentences.

Both problems are the same subject — the words a reader is shown — and both have
been deferred to "the vocabulary slice" by four other changes for weeks. This is
that change.

**Platforms: both.** Every item below exists on iOS and on Android, and the two
halves of the second problem are by definition cross-platform.

## What this is *not*, and the evidence

The slice this change opens is [`ui-revamp-2026-08.md`](../../../designs/ui-revamp-2026-08.md)
§5, sequenced at §7 as slice **A**: a value-only pass over Tier A and Tier B plus
the `publication` rename. **That pass has already landed, incrementally, inside
the slices that owned the screens.** Counted from the catalogues on 2026-09-05:

| §5 block | Status today |
| --- | --- |
| Tier B — 12 rows | **12 of 12** already at the specified replacement on iOS; 11 of 12 on Android, where `catalogue_error_http` carries the new wording but dropped the reason phrase the iOS value still has. That one row is in the divergence list below, not outstanding here |
| Tier A — 29 rows | ~25 at the specified replacement on both; 4 diverged or superseded |
| The `publication` rename ("the largest single rename in the pass") | **Done.** No iOS catalogue value contains the word; Android's three occurrences are two comments and one key *name* whose value reads *Titles* |
| "Also in the readers" — 6 rows | 5 of 6 done on both platforms |

So this change does **not** re-do §5. Proposing to rewrite values that already
read *Online library*, *Not answering*, *Add books* and *Size on this device*
would spend the whole change on work that shipped. What is left of §5 is residue,
and it is the smallest part of what follows.

**The slice's own note says it is atomic or it is broken**, on the grounds that a
value pass over 25 string files fails the build on any missing locale. That
argument was about the pass above, and events have answered it: the pass landed a
few rows at a time across at least five changes, and both platforms stayed in
step on 595 of the 629 keys that pair. The argument does not transfer to the work
that remains, which has a different shape — see *Sizing* below.

## What changes

- **Every sentence a reader can see becomes a translatable string.** Thirty
  English literals across six files stop being prose written in a
  format-parsing layer and become catalogue entries in all four languages. They
  are the skipped-publication reasons, the refused-file alert, and one Android
  reader failure that renders a raw internal exception message.
- **One state gets one name, on both platforms.** Where iOS and Android say
  different things about the same state, they are reconciled to one wording.
  This includes the publication page's availability, refusal and "this one is
  gone" vocabulary, which the two apps model differently — iOS composes two
  clauses, Android ships four whole sentences — and which
  [`publication-detail`](../publication-detail/tasks.md) task 3.5 hands here
  explicitly.
- **The browse path's plain-words rule becomes a requirement.** §5's rule —
  technical vocabulary is banned where a reader browses and required where they
  set up a NAS — currently exists only in a design document, which is why the
  values it specifies landed without anything holding them there. A requirement
  keeps the next feature from reintroducing *OPDS catalogue*.
- **The gate learns to see a sentence that never became a key.** `pnpm lint`
  runs `strings:ios`, which checks that every *key* resolves in four languages.
  It cannot see a literal, which is exactly how thirty of them shipped. A check
  that can fail on one is added, and — per AGENTS.md §5 — proved able to fail in
  this same change.
- **Two retired strings leave the catalogues.** `catalogue.strip.hint` /
  `catalogue_strip_hint` is drawn nowhere on either platform; the strip that
  used it is gone.

## Capabilities

**New capabilities:** none.

**Modified capabilities:**

- `localization` — the capability whose stated purpose is already "a constraint
  on how every string, date, number and layout is written". It gains the
  one-state-one-name rule, the plain-words rule, and a sharpened completeness
  requirement that a gate can enforce against literals rather than only against
  keys.

No other capability's requirements change. `publication-formats` already
requires a refusal to name its reason and does not care what language it is in;
what was missing was the language, and that is `localization`'s subject.
`localization` carries no delta in any of the eight in-flight changes, so this
change collides with none of them.

## Non-goals

- **Re-running §5's Tier A and Tier B value swap.** It has landed. Evidence in
  the table above.
- **`theme.pageColour.ratio`.** §5 asks for *Contrast %@ to 1* to become three
  plain bands. That contradicts a shipped requirement — `reading-themes` /
  *Custom colour* says a refused pairing is stated "with the measured ratio
  stated" — and `reader-theming-and-page-transitions` already holds a MODIFIED
  block on that same requirement, which is the two-changes-one-requirement shape
  `pnpm delta:drop` exists to catch. Left alone until the owner settles it.
- **Naming the third destination.** *Downloads* versus *On this device* is
  direction §8.4 and an owner decision, not a wording clean-up. It is also
  already shipped inconsistently, and that inconsistency is recorded as an open
  question rather than resolved here.
- **Key renames.** This change writes values and adds keys. A key whose *name*
  is misleading is renamed by the slice that rewrites the view using it, per §5's
  own mechanics rule.
- **The settings search index.** `SettingsSearch.swift` and `SettingsGroup.kt`
  index English terms only, so a French reader typing *icône* finds nothing. It
  is a real localisation gap and it is not a drawn sentence; it wants its own
  change.
- **Kavita age-rating labels and the diagnostic export.** Both are deliberately
  untranslated, both say so in their own comments, and both should stay that way.
- **Any UI or layout change.** No screen gains, loses or moves a control.

## Impact

**iOS.** `App/RefusedFile.swift`, `StoryArcKit/Sources/Formats/LibraryScanner.swift`,
`PublicationIndexer.swift`, `PublicationIndexer+Building.swift`, and the
catalogues in `LibraryFeature` and `App`.

**Android.** `core/format/…/LibraryScanner.kt`, `core/format/…/PublicationIndexer.kt`,
`feature/reader/…/ReaderViewModel.kt`, `app/…/OpenedFile.kt`, and the
`strings.xml` sets for `app`, `feature/library` and `feature/reader` in all four
locales.

**Repository.** One new check in `scripts/`, wired into `pnpm lint`, with a
`--self-test` alongside the two that already have one.

**Sequencing.** The publication page's vocabulary is specified in
`publication-detail`'s delta, and `publication-detail` is a capability that does
not yet exist under `docs/openspec/specs/`. This change therefore states the
one-state-one-name rule generally rather than naming that page's sentences, and
the reconciliation itself is task-ordered after that change archives.

## Sizing, honestly

**One change, several commits — not one commit, and not several changes.**

The atomic units are the seams, not the pass:

- **The scanner and indexer reasons (21 of the 30 literals) are atomic per
  platform.** Both `SkippedNotice` surfaces render whatever the layer hands
  them, in a list where each reason sits beside its own publication's name.
  Converting half of them leaves a list that is half French and half English in
  the same column, which is worse than a list that is honestly all English.
- **The refused-file alert (6 literals, iOS) is its own unit**, and Android's
  equivalent is already localised, so the target shape is on the shelf.
- **The Android reader failure is its own unit**, and it is the largest hidden
  one: it renders `cause.message`, so internal exception prose reaches the
  reader from anywhere in the format layer. Sizing it needs the count of
  reachable messages, which is a task, not a guess.
- **The dialect reconciliation is not atomic at all.** It is per state, and a
  state whose two platforms agree is strictly better than one where they do not,
  whatever else is still outstanding. It can land a state at a time.

So the "atomic or broken" note is honoured where it still applies — inside a
seam — and does not bind the change as a whole. What would leave the app
speaking two dialects is stopping half way through *one seam*, and the task list
is ordered so that no seam is left open.
