# Two taps back to the book

**Platforms: both.** This change writes no application code. It records a number
that the shipped apps already charge the reader and that no specification states.

## Why

`reading-progress` opens its *Resuming* requirement with a promise: the app makes
returning to where the reader stopped **the shortest path in the app**. The
requirement then measures that path in one word — "without an intermediate
screen" — and never in actions. A word is not a measurement. A reader who wants
to carry on cannot read the requirement and learn what carrying on costs.

The apps now charge two different prices for the same verb, and the difference is
the whole reason the number matters.

### What the code does today, on both platforms

| Path | iOS | Android | Actions |
| --- | --- | --- | --- |
| Cover in the library, a shelf, search or a collection | `CoverCell.swift:68` and `CoverList.swift:118` push a `PublicationRoute` | `CoverGrid.kt:432` and `CoverList.kt:199` call `onOpen`, bound to `AppHost.openPage` at `AppDestinations.kt:99` | **2** |
| Keep reading | `HomeScreen.swift:178` hands the hero `open`, which opens the book | `HomeDestination.kt:166` hands `onResume` the `resume` function, which calls `host.open` | **1** |

Both cover paths land on the publication's page. The page draws exactly one
primary action, labelled *Continue* when a position exists — `DetailActions.swift:94`
and `primaryActionOf` in `DetailActions.kt:58` — and that action opens the book at
the stored position. So the cover path is: tap the cover, tap *Continue*. Two
actions. The Keep reading path is one.

### The clause that diverges, and the clause that does not

**Line 46 of the main spec diverges.** *Restart deliberately* justifies putting
"Start from the beginning" on the long press "because the library opens a
publication when its cover is tapped". The library does not do that any more. The
reason clause rests on a premise the `publication-detail` change removed.

**Line 40 of the main spec is half true, and that half must be kept.** *Continue
from the library* says a partially read publication "opens at the stored position
without an intermediate screen". That is still exactly what Keep reading does, on
both platforms. It is no longer what a cover does. The sentence is correct about
one verb and wrong about the other, so it must be split rather than deleted.
Deleting it would remove the app's one true one-action promise.

### The amendment already exists. This change adds the number.

**Say this plainly, because it decides the shape of this change.**
`publication-detail`'s own delta at
`changes/publication-detail/specs/reading-progress/spec.md` already modifies
*Resuming*. It was written on 2026-08-31 in commit `3ba316c1`. It splits the two
verbs, keeps the one-action sentence for the resume affordance, rewrites the
cover scenario around the page, and replaces *Restart deliberately*'s dead reason
clause. That delta is correct and this change does not contradict a word of it.

What that delta does not do is say what the cover path costs. It says "the page
is the only thing between the cover and the book", which is a shape, not a price.
This change states the price, in actions, for each verb, on both platforms. The
`STATUS.md` row for `reading-progress` still says the delta "does not list
`reading-progress` as MODIFIED"; that sentence is stale by the same commit, and
this change does not own `STATUS.md` to fix it.

## The reader is one action worse off, and the owner should decide that

**This proposal does not bless the shipped behaviour.** The specification asked
for one action from the library and gets two. For a reader whose only intent is to
carry on with the book they were reading, the publication page is a screen they
did not ask for and must dismiss by acting on it.

Three facts bound the cost, and the owner needs all three:

1. **The cheaper path exists and is prominent.** Keep reading is the hero on Home
   on both platforms, and it costs one action. A reader who wants only to carry on
   has a one-action route and is not forced through the page.
2. **The page is one action, not several.** Its primary action is a single button
   that opens the book at the stored position and says *Continue* before it is
   taken. Nothing else stands between the cover and the book.
3. **The cover no longer means "read this".** It means "show me this". That was
   `publication-detail`'s deliberate purpose, and a cover that opened a full-screen
   reader had no way to answer "what is this, and where did it come from".

**The recommendation is to accept the two actions and to write the number down**,
because a promise measured in actions can be checked, and "without an intermediate
screen" could not be. If the owner instead decides that two actions is too many
from the library, the fix is a change to `publication-detail`, not to this
requirement, and this delta is the place the cost is stated either way.

## What changes

- `reading-progress` → *Resuming*: one paragraph that requires the cost to be
  stated and bounds it to a publication the app can open now, and one bullet on
  each of the two continue scenarios naming the number of actions.
- Nothing else in `reading-progress` moves. The local store, position identity,
  synchronisation and conflict resolution are untouched.
- No application code changes. No screenshot is owed.

## Relationship to `publication-detail`

Two live changes now hold a `## MODIFIED` block for `reading-progress` →
*Resuming*. `pnpm delta:drop` reports that pair, because whichever syncs second
replaces the whole block.

This block is a **superset** of `publication-detail`'s: every sentence and every
bullet of that delta is carried here word for word, and this one adds two
bullets and one paragraph. A superset is safe in one order only, so the order is
recorded in `.delta-drops.json` as
`["publication-detail", "two-taps-back-to-the-book"]`. Syncing
`publication-detail` first and this change second leaves the union in the main
spec. The reverse order would delete the two bullets and the paragraph this
change exists to add.
