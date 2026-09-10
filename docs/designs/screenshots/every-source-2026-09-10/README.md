# Every source is the library — 2026-09-10

The library, Home and a source's own screen, photographed on a OnePlus 7T Pro
(`f7cee850`, 1440 × 3120) against the owner's own Kavita server —
`kavita.cedricmeyer.eu`, 127 titles read of more — with two local comics
beside them. Change: `every-source-is-the-library`, tasks 6.3 to 6.6.

**The control is `../servers-in-the-library-2026-09-10/android-library-before.png`**,
the same phone before any of this: local files only, and a configured server
that put nothing on the shelf. That absence is the whole point of the change,
so it is not repeated here.

## The library

| Frame | Theme | Text |
| --- | --- | --- |
| `android-library-light.png` | light | default |
| `android-library-dark.png` | dark | default |
| `android-library-light-largest.png` | light | 200% |
| `android-library-dark-largest.png` | dark | 200% |

A server's publications and the device's own files in one grid, in one sort
order, drawn by one cell. Nothing on a cover says which source it came from —
`library-browsing` forbids it, and the frames are where that is checked.
`02 - Green Lantern Corps · 3 titles` is a series cell: one row for a series
however many issues it holds.

## More from this library

`android-library-more-from.png` — the foot of the same shelf.

*More from mecedric · kavita.cedricmeyer.eu*. It is drawn because that source
held something back, and only then: a shelf where every source gave everything
draws nothing there. `ios-library-light.png` is that case, and so is a useful
second control — the simulator's library is local fixtures only, and the foot
of its shelf is empty.

## A count that does not pretend to be a total

| Frame | What it shows |
| --- | --- |
| `android-sources-list-partial.png` | *Available · At least 127 titles* |
| `android-source-detail-partial-light.png` | *In your library — At least 127 titles* |
| `android-source-detail-partial-dark.png` | the same, dark |

The server holds more than 127. The app read sixty series of it, which is what
`KavitaContributor.firstSlice` is, and both screens now say *at least* rather
than stating a slice as a total. The list row and the detail screen are
photographed together on purpose: they used to disagree, because only the
detail screen was changed first.

## Home

| Frame | Theme | Text |
| --- | --- | --- |
| `android-home-light.png` | light | default |
| `android-home-dark.png` | dark | default |
| `android-home-light-largest.png` | light | 200% |
| `android-home-dark-largest.png` | dark | 200% |
| `android-home-recently-added.png` | light | default, scrolled |

*Recently added* holds `Green Lantern Corps Quarterly`, which is on the server
and not on the phone, beside two comics that are. Same shelf, same cell, same
size. Keep reading holds the two part-read local comics — the server's
publications have no reading position on this device yet, which is the honest
reason a server row is not in that row and not a fault to fix.

## iOS

`ios-library-light.png`, `ios-library-dark.png` — iPhone 17 Pro simulator.

**No server, so no server rows.** The simulator has the project's local
fixtures and nothing else, and the owner's server key is not on it. What these
frames are good for is the negative: the same grid, the same series cell
(`Lantern Green · 3 titles`), and no *more from this library* at the foot,
which is what the rule says for a library that holds everything its sources
gave.

What is therefore **not** shown on iOS: a remote row in the grid, the partial
count, and the affordance. `SourceSliceTests`, `MoreFromTheLibraryTests` and
`StillBeingReadTests` assert those on that platform; no frame proves them, and
this paragraph is the record of that rather than a gap left silent.

## Not shown on either platform

**The still-being-read line.** It says a source has not answered yet, so it is
on screen for as long as the server takes to reply — a few seconds against
this server, and gone before a screenshot lands. `StillBeingReadTest` and
`StillBeingReadTests` assert the rule; the line's wording is in the four
`strings.xml` files and the `xcstrings` catalogue.
