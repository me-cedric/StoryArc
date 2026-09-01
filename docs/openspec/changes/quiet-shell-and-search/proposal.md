# One bar, a search page, and a word about what changed

## Why

StoryArc's shell works and does not read like the app it is competing with. Three
things give that away, and a reader meets all three in the first ten seconds.

**Search is a shape-shifting field rather than a place.** iOS draws it as
`Tab(role: .search)`, which morphs the tab into a text field in place — a device
run on 2026-08-31 confirmed that is what the role does, and the finding is in
[`ui-revamp-2026-08.md`](../../../designs/ui-revamp-2026-08.md). It is clever and it
is not what a reader expects: the bar changes under their thumb, and there is
nowhere to *land*. Every app a reader already knows treats search as a destination
with a page behind it — a page that can suggest something before a single letter is
typed. Android has the same problem from the other end: its search is a field
belonging to the library screen, so searching is something you do *to* the shelf
rather than a thing the app offers.

**Nothing is offered before the query.** Both platforms show an empty result area
until a reader types. A search page is the one screen in a reading app that can say
"you were reading this", "you have never opened these", "this series has a next
volume" — and ours says nothing.

**A reader who updates learns nothing.** The app has shipped page curl, five
typefaces, six reading themes, OPDS, Kavita, SMB and a reading position that
survives a rename, and it has never once told anybody. There is no changelog surface
at all.

## What changes

**One bar with search on it.** iOS keeps three reading destinations and gains Search
as a fourth, drawn like the others and leading to a page. The search *role* goes; the
bar stops changing shape. Android's navigation gains the same destination, drawn the
way Material's own guidance draws one — which is not necessarily the way iOS draws
it, and design.md settles that per platform.

**A search page that suggests before it is typed into.** At rest it offers what the
reader might want: something to continue, something never opened, a next volume, a
recent series. Once focused it offers what they asked for before — recent queries,
clearable — and then results as they type. The merged local-and-server ranking that
landed in `library-browsing` is unchanged; this is the screen it renders on.

**A scope the reader can see.** Search spans a device, folders, OPDS catalogues,
Kavita servers and SMB shares. Today that is invisible until results arrive. The page
states what it is searching and lets a reader narrow it to what is on the device —
which is the one narrowing a reader on a train actually wants.

**What's new, once, after an update.** A screen listing what changed in the version
just installed, dismissible, never blocking, and never shown twice for the same
version. On a first ever launch it does not appear at all: somebody who has never
used the app has nothing to catch up on.

## Platforms

**Both.** Every requirement here holds on iOS and on Android, and the two will not
look alike: the shell is the surface where platform idiom matters most, and
[ADR-0001](../../../decisions/0001-independent-native-cores.md) forbids one drawing
the other's answer. Where the platforms diverge deliberately — a floating capsule
against an edge-to-edge bar, a role against a destination — design.md names the
divergence and the guidance behind each side.

## Non-goals

- **No store, no catalogue browsing on the search page.** Apple's search page sells
  books. Ours has nothing to sell and will not pretend to: every suggestion comes
  from what the reader already has or has already configured.
- **No recommendation engine, no ranking model, no telemetry.** Suggestions are
  computed on the device from the reading history that already exists locally.
  Nothing about what a reader searches for leaves the device, per
  [`project.md`](../../project.md).
- **No new search *behaviour*.** Matching, grouping by match kind and the local/server
  merge all shipped and are asserted; this change moves them onto a page and adds
  what surrounds them.
- **Not the reader.** Decluttering the reader's chrome, the compact progress display
  and the theme sheet are [`quiet-reader`](../quiet-reader/proposal.md).
- **Not audiobooks.** A playback surface in the shell is
  [`audiobooks-and-playback`](../audiobooks-and-playback/proposal.md). This change
  leaves room for it and adds nothing.
- **No voice input.** Apple's field carries a microphone. Dictation is the keyboard's
  job on both platforms and needs nothing from us.

## Capabilities

- **`library-browsing`** — search moves to a page; the page states its scope and
  offers suggestions and recent queries.
- **`navigation-shell`** — search becomes a destination; the bar stops changing shape.
  **This change builds that and no longer carries the delta for it.** The requirement was
  reconciled into
  [`one-library-three-destinations`](../one-library-three-destinations/specs/navigation-shell/spec.md)
  on 2026-09-01, because that change is what creates the capability's main spec and a
  MODIFIED delta needs one to merge into. See §4b of this change's tasks.
- **`settings-and-about`** — what changed in this version, shown once.

**A dependency worth stating plainly, and the clause below turned out to be false.**
`navigation-shell` and `home-screen` have no main spec: they are new capabilities that
[`one-library-three-destinations`](../one-library-three-destinations/proposal.md)
introduces and has not synced. So two active changes carried a `navigation-shell`
delta, whichever synced first would create the main spec, and the two deltas must not
contradict each other. This one adds a destination and removes a role; ~~it touches no
requirement that change wrote~~. If that stops being true, the two must be reconciled
before either syncs, not after.

**It touched one.** Both deltas named *Reaching search*, so the trigger this paragraph
sets was met the day the delta was written. `openspec validate` does not catch a MODIFIED
delta whose target exists in no main spec, so nothing said so. Reconciled on 2026-09-01 by
moving the newer statement — this change's, which is the one the app implements — into the
change that creates the capability. §4b of the task list records it.
