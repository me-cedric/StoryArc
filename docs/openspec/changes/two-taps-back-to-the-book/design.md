# Design

This change writes documentation only. The design decisions are about where the
sentence goes and how it survives the sync, not about code.

## Why a separate change rather than an edit to `publication-detail`

The amendment of record lives in `publication-detail`'s delta. Adding four
bullets there would have been one file edit and no collision. It was not done for
one reason: **`publication-detail` is an active change owned by other work**, and
its `tasks.md` tracks twelve ticked tasks, nine partial and two open against a
screenshot obligation this change does not share. Reopening its delta to add a
clause about reader cost mixes a documentation-only amendment into a change that
still owes captures from a device.

The cost of the separate change is one collision entry. That cost is bounded and
is recorded below.

## Carrying the whole block, and why the order is written down

A `## MODIFIED` requirement replaces the **whole block** on archive. Two live
changes that modify the same requirement are therefore lethal to each other
unless one block contains the other.

This delta carries `publication-detail`'s block verbatim and adds to it:

| Element | Source |
| --- | --- |
| Requirement prose, first two paragraphs | `publication-detail`, word for word |
| Requirement prose, third paragraph | new — the SHALL about stating the cost |
| *Continue from a resume affordance*, first two bullets | `publication-detail`, word for word |
| *Continue from a resume affordance*, third bullet | new — one action |
| *Continue from the library*, first four bullets | `publication-detail`, word for word |
| *Continue from the library*, last two bullets | new — two actions, and where a resume affordance is offered |
| *Restart deliberately*, all three bullets | `publication-detail`, word for word |

`publication-detail`'s block therefore holds nothing this one lacks. That makes
the pair **nested** rather than disjoint, which is the only shape a recorded
order can save. The order in `.delta-drops.json` is
`["publication-detail", "two-taps-back-to-the-book"]`.

**Read the order as an instruction, not as a note.** Sync `publication-detail`
first. Its block lands in the main spec. Sync this change second. Its block
replaces that one and loses nothing, because it contains it. Reversing the two
deletes this change's whole contribution and no tool would report it, because by
then `publication-detail`'s delta is archived.

## Why the cost is stated in actions rather than in screens

"Without an intermediate screen" was the old measurement and it failed twice. It
could not describe a page whose primary action continues, and it could not be
counted. An action is countable, is what the reader spends, and is the same unit
on a phone, on a tablet and in a split view — a cover in the leading column of an
iPad split still costs one tap, and the page still costs one more.

No number is stated for a publication the app cannot open, or for one whose
source is away, or for one that must be downloaded first. Those three states draw
no *Continue* at all — `DetailActions.kt:101` lists them as `opensTheBook = false`,
and `DetailActions.swift:92` draws `EmptyView` for a refusal — so there is no
path back into a book to measure.

## What is deliberately not changed

- **`docs/openspec/specs/reading-progress/spec.md`.** A main spec is written by
  the sync step and never by hand.
- **`docs/openspec/STATUS.md`.** Its `reading-progress` row still says
  `publication-detail`'s delta does not list `reading-progress` as MODIFIED. That
  is stale as of commit `3ba316c1`. This change does not own the file, and the
  correction is named here so that whoever owns it can make it.
- **`publication-detail`'s delta, proposal and tasks.** Owned by that change.
