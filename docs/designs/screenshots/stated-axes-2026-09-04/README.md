# The controls state the axis they narrow by — 2026-09-04

Four findings from the 2026-09-02 sweep, all one mistake: a control that names the wrong axis,
or names none. Compare each frame against its twin in `../ios-sweep-2026-09-02/`.

| File | What changed |
| --- | --- |
| `ios-library-narrowed-to-nothing.png` | *"Nothing in your library came from Attic NAS."* It said *"…is on this device yet"* — the reader narrowed by **library** and was answered about the **device**. |
| `ios-search-results.png` | The *Everywhere · On this device* control is on the results now, and the three *didn't answer* lines are one sentence with one *Try again*. |
| `ios-library-filtered.png` | The View menu draws the availability axis instead of `ellipsis.circle`, and the funnel carries the count — **1** — beside it. |
| `ios-library-filter-menu-active.png` | The same toolbar with the menu open, so the drawn count can be read against the groups producing it. |
| `ios-add-share-sheet.png` | *Connect* is a control, not a fifth field. |
| `ios-add-catalogue-sheet.png`, `ios-add-kavita-sheet.png` | The same, on the two sheets that used `.borderedProminent`. |
| `ios-library-grid.png` | The unnarrowed shelf, as the control for the two filtered frames. |
| `ios-search-at-rest.png` | **Not a fix. Evidence of a defect** — see below. |
| `-dark` twins | The search results, the filtered shelf, its menu, and the share sheet in the dark appearance. |

## Narrowing to one library

`library-empty.scope` now reads *"Nothing in your library came from %@."* in all four
languages. `library-browsing` keeps availability and source apart with some care, and the
sentence answering one named the other; the neighbouring `library.empty.onDevice` keeps *on
this device*, and `StatedAxisTests` asserts both so a later edit cannot fix one by breaking
the other.

## The search results

Two changes in one frame.

**The scope is stated.** `library-browsing`: "**WHEN** the search screen is open **THEN** it
states whether it is searching everything or only what is on the device." The segmented control
was on the at-rest screen and in the field's own `.searchScopes` bar — which the platform draws
only while the field is *active* — and nowhere on the results. One `SearchScopeStatement` is
mounted on both faces now, so the two cannot drift.

**A search that mostly failed says so once.** Three unreachable servers produced three *didn't
answer* rows with three *Try again* buttons under two results: on a device away from home the
notices outnumbered the answers. One row names them all — *"StoryArc Test Catalogue, Attic NAS,
and ada · 127.0.0.1 didn't answer"* — through a locale-aware list, so no new string was needed
and the existing *%@ didn't answer* reads correctly for one name or for three. Its *Try again*
retries every one of them, because the reader is retrying the search rather than a server.

## The toolbar

The View menu decides availability, layout, sort and direction, and drew `ellipsis.circle`
whenever the shelf showed everything. `library-browsing` asks the availability choice to be
"visible while it is active", which that satisfied in one of its two states — and taught the
reader that the glyph means *downloaded* rather than *availability*. It draws the axis in both
states now, using the two symbols the picker rows inside it already draw.

The active filter count was spoken to VoiceOver and never drawn, so one filter looked exactly
like six. It is drawn beside the funnel and still spoken. The comment it replaced said a menu
label "cannot carry" a badge — true of `.badge(_:)`, and not of the label's own content.

## The add-a-library forms

*Connect* was a full-width grey capsule the same colour, height and corner as the fields above
it. Two separate causes with one appearance: `.borderedProminent` renders grey while
**disabled**, which is the state a reader meets it in on an empty form, and the share sheet's
button had no style at all, so a `Form` drew it as a list row — a white capsule exactly like the
four field groups.

All three use `.glassProminent` with `.controlSize(.large)` and `.tint(theme.accent)` — the trio
`DetailActions` already uses for *Read*. `design.md` §5 keeps chrome glass untinted so it picks
up what is behind it, and the prominent variant is the one meant to carry a tint; `.tint` on
plain `.glass` tints the *material* and `GlassIsUntintedTests` fails the build over it.

**Photographed disabled**, which is how a reader first meets it and what the sweep complained
about. No walk fills these forms, so the enabled accent state has no frame here.

## A defect found while taking these, and not fixed

**The search field is gone from the at-rest search screen.** `ios-search-at-rest.png` here has
no field; `../ios-sweep-2026-09-02/ios-search-at-rest.png` has one, drawn under the title. Same
walk, same simulator, same iOS 26.5 runtime. The accessibility hierarchy confirms it: no
`searchFields` element exists anywhere while the screen is at rest. It reappears once a term is
set — `ios-search-results.png` shows it holding *Harbour* — so a reader who arrives at the tab
with nothing typed has no way to type.

**It is not caused by anything in this branch.** The walk fails identically on an unmodified
checkout of `main`'s `LibraryFeature` and `SettingsFeature`, established by reverting those two
directories and re-running. Nothing moved under `.searchable`, which is still on
`LibrarySearchSurface`, so the change is beneath the app — most likely the SDK the app is now
compiled against, since iOS 27 runtimes have appeared on this machine since the sweep.

It belongs to `navigation-shell` rather than to `library-browsing`, and the fix is a decision
(adopt the platform's search-tab role, or pin the field) rather than an edit, so it is recorded
here rather than absorbed into this change.

`SweepSearchTests`' own landmark was that field, which is why every search walk failed. It is
the scope statement now — stronger rather than weaker, because that control belongs to the
search surface alone and, since this change, is on **every** state of it.
