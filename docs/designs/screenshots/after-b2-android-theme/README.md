# Android's theme, after slice B2 — 2026-08-30

Five captures from the slice that wired `MaterialTheme.shapes`, gave Android chrome
Material's own type scale, and applied the colour rule the codebase had been declaring and
not using. Slice B2 of [`ui-revamp-2026-08.md`](../../ui-revamp-2026-08.md) §7.1.

The type scale is the visible one and it is deliberate: a 57 sp Android display beside a
34 pt iOS one is what nativeness costs, and §8.6 of the direction document flags it as a
decision rather than an accident.
