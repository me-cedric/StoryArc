# Say which book, and stop making the reader guess an icon

## Why

A design review on 2026-09-01 looked at both apps and found five things. Four are real, one
was a misreading, and this change is the four. Each was checked against the code before it was
written down here.

**A failure that names nothing.** `LibraryStates.swift` and `LibraryScreen.kt` show
*"%lld couldn't be opened"* — a bare count, floating over the shelf, gone by itself after six
seconds. It names no publication, offers no action, and appears on Library, Search and
Downloads alike. A reader learns that something is wrong and has no way to find out what.
`publication-formats` has spent considerable effort making every refusal *named* — a solid
RAR4 says it is solid, a CB7 says it is 7-Zip, a locked audiobook says it is protected — and
then the library aggregates all of that into a number.

**The player draws a headphones glyph over its own rule.** `FullPlayerView`'s coverless state
is an SF Symbol. Its comment claims that is "the same placeholder the library draws", and it is
not: the library draws `CoverlessWell`, which sets the title as artwork. So the one surface
where a reader stares at the artwork for an hour is the one surface that does not use it — and
the lock screen inherits the glyph.

**Six unlabelled icons in a row.** `LibraryToolbar.swift` puts six `ToolbarItem`s in
`.primaryAction`: select, scope, show, sort, filter, add. Similar weight, similar size, no
labels. The review counted five and undercounted.

**The Home hero is a poster with no controls.** The card is 4:5 at up to 420pt, so on a phone
it is about half the viewport, and it carries a kicker, a title and one line. No progress
indicator, no author — the kicker is series-or-publisher — and no explicit resume action; the
card itself is the target. And when the line reads *"1 page left"* the publication is
effectively finished, which is the one state the surface has nothing to offer for.

## What changes

**A failure names its publication and leads somewhere.** One that fails names it. Several
become a notice a reader can open to a list of them, with what went wrong per publication in
the words `publication-formats` already produces. The notice stops being a timed toast,
because a self-dismissing message about a durable problem is a message designed to be missed.

**The player asks `CoverlessWell`,** like every other surface, and the lock screen gets the
same artwork rather than a glyph.

**The toolbar keeps two controls and a menu.** Sort and filter are already menus; show and
scope join them. Select stays, because it changes mode rather than presenting a choice.

**The hero earns its size.** Progress becomes visible, the resume action becomes explicit, and
a publication with nothing meaningful left offers to finish it or to start the next in the
series instead of offering to re-open its last page.

**Two smaller things named in the same review.** Android's sort chip reads *"Title"*, which
looks like a filter value rather than an ordering; it says what it is. And the iOS player's
close button gives way to the sheet's own grabber, because a sheet already has a way out and a
second one is furniture.

## Platforms

**Both**, except the toolbar and the player's close control, which are iOS-only — Android's
library already uses menus for the same choices, and its player is a destination rather than a
sheet, so it needs a back affordance and has no grabber to defer to.

## Non-goals

- **No change to what a refusal says.** `publication-formats` already words every one of them.
  This changes where they are shown and whether a reader can reach them, not their text.
- **No new failure states.** Nothing here makes the app refuse more.
- **The hero is not being removed.** The review's suggestion was a shorter card, not none: it
  is the surface's one resume affordance and `home-screen` requires it.
- **Not the accent.** The review's first item is the brand accent, and it belongs to
  [`brand-identity-and-app-icons`](../brand-identity-and-app-icons/design.md), which now
  carries it — including the reversal it caused.
- **No Android Home hero.** The review reported it missing; it is not. See below.

## What the review got wrong, and why it is recorded rather than quietly dropped

**Android Home does have a continue-reading hero.** `HomeScreen.kt` builds one — a single card
when there is one publication, a carousel when there are several — and places it first, above
*Recently added*. It is conditional on there being something in progress
(`if (surface.keepReading.isEmpty()) return`), exactly as iOS is
(`if !keepReading.isEmpty`). The review saw a device with nothing in progress.

Writing that down matters more than it looks: "Android is missing the hero" is a plausible
brief that would have sent somebody to build a second one.

## Capabilities

- **`library-browsing`** — the failure notice, and the toolbar's shape.
- **`audio-playback`** — the player's artwork.
- **`home-screen`** — the hero's content. **It has no main spec**, being introduced by
  `one-library-three-destinations`, which has not synced; the delta is written and will merge
  when that change does, the same dependency `quiet-shell-and-search` records for
  `navigation-shell`.
