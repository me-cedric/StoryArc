# Every library answers, and the shelf has an owner — 2026-09-04

The 2026-09-02 sweep: "*Your libraries* lists four sources; all four read `0 titles`, while
the shelf next door holds fourteen publications, and all four sit on *Connecting* — including
`Comics on this iPhone`, which is a local folder with nothing to connect to."

| File | What changed |
| --- | --- |
| `ios-settings-sources.png` | Five rows. Four say **Not answering**; none says *Connecting*. The fifth is new: **On this device — 20 titles, Available**. |
| `ios-settings-source-detail.png` | One source's page, unchanged in layout, now stating a state it was asked for. |
| `-dark` twins | The same two in the dark appearance. |

Compare against `../ios-sweep-2026-09-02/ios-settings-sources.png`, same walk, same device.

## Two defects, one frame

**Nothing on this path ever asked.** Source state is deliberately never persisted — it
describes a network, and a state read from disk is a claim about the past — so every source
loads as `connecting` and something has to answer. The only thing that did was the *library*
screen's `.task`. A reader who opened Settings without visiting the Library tab was therefore
shown the state the registry loads with, on every row, indefinitely: two of those rows pointed
at hosts that were plainly not running, and said *Connecting* about them.

The screen that shows a state now asks for it, through `.testConnection` — the action
`sources` already gives this screen.

**A local folder has no network to wait for.** `sources` gives every source the same four
states, and the app read that as licence to leave a folder in the one that means *waiting for
an answer*. `FileManager` answers on the spot: the folder is readable, or it is not. The
resolver that existed walked past local folders by design, so a folder whose security-scoped
bookmark did not restore sat on *Connecting* for the life of the process — which is exactly
what a probe that never resolves looks like.

Folders are resolved synchronously now, before any network is touched. `Comics on this
iPhone` is a folder whose bookmark is stale on this device, so it reads **Not answering** —
grey, per the second non-negotiable, and its cached contents stay browsable. An unreachable
folder keeps the moment it *went*, so "No answer since …" cannot drift to *just now* on every
appearance.

**And the shelf belonged to nobody.** `source(of:)` matched a folder to a source by locator.
The app's own Documents folder — where a file lands when it arrives through Files, AirDrop or
another app's Open-in — is not a source the reader added, so every publication found there was
attributed to `nil`. The code called that "the honest answer". The first half was right and
the conclusion did not follow: the alternative to attributing a publication to the *wrong*
library is not attributing it to *none*. An unattributed row is invisible to the per-source
count, so four libraries reported nothing beside a shelf of fourteen and no screen in the app
could say where the fourteen came from.

They are filed under **On this device** — the source that already means *in storage the app
owns*, which is what the Documents folder is. A reader cannot tell those bytes from an
imported copy and should not have to.

## The trap that fix walks past

`refreshImports()` prunes rows whose imported copy has been deleted, keyed on the import
store's own records. The Documents folder is not in those records, so the naive change would
have swept the entire Documents shelf off the screen on the next appearance — a far worse bug
than the one being fixed. Rows whose file sits in the app's own storage are now exempt from
that prune, and the source is dropped only when nothing is filed under it by *either* route.
`LocalSourceStateTests` pins both halves.

## Still true, and deliberately

The three servers read `0 titles`. That is the *cached* item count `sources` asks for, and a
catalogue's contents are browsed rather than folded into the shelf — so nought is the correct
answer for a server nothing has been downloaded from, and it now sits beside *Not answering*
rather than beside *Connecting*, which is what made it read as a lie.
