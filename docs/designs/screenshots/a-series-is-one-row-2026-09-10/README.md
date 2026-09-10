# A series is one row — Android, 2026-09-10

**OnePlus 7T Pro** (`f7cee850`, Android 16, API 36), against the owner's Kavita
**0.9.1.4** over the real network, dark, default text size. Halved to 720×1560.

`android-library-before.png` is build `b216d118` — the rule existed but nothing
drew it. The others are this change.

| Frame | The claim |
| --- | --- |
| `android-library-before.png` | Every issue was its own cell, under a sticky series heading. Sixty series of twenty issues is twelve hundred cells with signposts on them. |
| `android-library-after.png` | A series is one cell, named for the series, captioned with what it holds — *Blackest Night - The Flash (2010)*, *3 titles*. A publication belonging to no series is still a cell of its own. |
| `android-series-open-after.png` | Opening one lists its issues, drawn by the same cell the grid uses, with one gesture back. |

## Two defects the frames caught, both fixed here

**Kavita's `-100000`.** The server writes that as the chapter number when a
chapter has none — a collected edition, a volume with one part — and it was
reaching the shelf as a title. A number that is not a number is no title at
all, so the series' own name is used.

**A stale row could not be corrected.** The first build of the fix changed
nothing on screen: the rows came from the library cache, and `adopt` only ever
re-attributed a row it had seen before. `SourcePrecedence` answers *which of two
sources wins*, strictly — so a source lost every comparison with itself, and a
re-read could never correct what it had already written. A source now replaces
its own rows, and a row with a downloaded file still keeps the file's own
metadata over a server's description of it.

## iOS, on a simulator

`ios-library-after.png` and `ios-series-open-after.png` are an **iPhone 17 Pro**
simulator on iOS 26.2, seeded with four local comics rather than a server —
three named `Lantern Green 001..003.cbz` and one standalone — because pointing
it at the owner's Kavita would mean typing their API key into the app. The rule
does not care where a publication came from, which is the point of it.

The library lists *Lantern Green — 3 titles* and *The Third Chapter* beside it;
opening the series lists *Lantern Green #1*, *#2* and *#3*.

**The simulator caught a bug every unit test had passed.** A series cell inside
the Library split opened the *issue leading the series* instead of the series:
the split hands cells an `openPublicationRoute` closure because a value link in
its shelf column goes nowhere, and the series branch was only on the value-link
path. There is an `openSeriesRoute` beside it now, and the detail column's path
is type-erased so one column can hold both destinations.

## What these frames do not show

- **Only Kavita.** OPDS and SMB have no contributor yet.
- **Android only.** iOS has neither the rule nor the screen.
- The contributor still fetches every chapter of every series in its slice up
  front. A series row only needs the series, so that is the next thing to go.
