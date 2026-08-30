# Settings and About screens

## Why

`settings-and-about` is fully specified and entirely unbuilt. That has stopped
being a gap in coverage and become the thing five other pieces of work are
waiting on:

| Held item | Waiting for |
| --- | --- |
| `reader-theming-and-page-transitions` 5.1–5.5 | somewhere to choose an appearance, so the four modes and Natural are not dead code |
| the same change, 4.6 | the setting the spec names — "the volume buttons **where enabled in settings**" |
| the same change, 3.10 | a surface for the *global* reading default; the per-series half already works |
| the same change, 3.11 | a surface to set a custom colour for comics, so the matte around a page has a value to take |
| `format-scope-and-libraries` 6.1 | the acknowledgements screen the five bundled OFL notices require |

Every one of those is built or nearly built behind the setting that would let a
reader reach it. Two of them — the volume buttons and the appearance modes —
would be *worse* than absent if shipped without one: volume keys that silently
stop changing the volume, and an appearance no one can select.

The other reason is the licences. `packages/fonts` ships five OFL notices inside
both apps because the licence requires the text to travel with the files. What
the licence *also* requires is that it be shown, and `reading-themes` says so
too. The files are in the bundle; nothing displays them.

## What changes

Nothing about the capability's requirements — they are already written and this
change does not modify them. What changes is that they exist.

### Built: `settings-and-about`

All four requirements, on both platforms:

- **Appearance.** System, Light and Dark, plus the OLED Dark that
  `reader-theming-and-page-transitions` adds, applying without a restart and
  leaving the reading theme alone.
- **Organisation.** Seven groups — Sources, Appearance, Reading, Downloads and
  storage, Language, Privacy, About — each summary row stating its current value,
  and search across them.
- **Privacy.** The screen that states no account, no backend, no analytics, no
  crash reporting; individually clearable cache, history and downloads, each with
  what it removes and what it frees; and a diagnostic export shown before sharing
  with every credential, token and hostname redacted.
- **About.** Version and build, the author, the repository, the licence, the
  statement that the app is free with no paid tier and no advertising, one
  optional Ko-fi link that never nags, acknowledgements with every third-party
  licence in full, and a problem report that pre-fills the version and device
  class and no personal data.

### Consequence for the held items

This change does not implement them — they stay with their own changes — but it
is what lets them be finished. Each held task names this change rather than
guessing at a date.

## Scope and order

Two requirements have hard dependencies on things that do not exist yet, and this
change is explicit about them rather than discovering them halfway:

- **Sources** is a group whose contents belong to `sources`, `network-share`,
  `opds-catalogue` and `kavita-server`. Only the group and its summary row are in
  scope here; the rows inside it arrive with the connectors.
- **Downloads and storage** likewise depends on `offline-downloads`. The group
  and the *clearable cache* row are in scope, because the cache exists; download
  management is not.

Everything else is buildable today.

## Non-goals

- No account, no sync settings, no telemetry toggles. There is nothing to toggle:
  the privacy screen's whole point is that the app has no backend to opt out of.
- No theming of the settings screens themselves beyond the design system. They
  are a list of rows on each platform's own list component.
- No settings *export*. The diagnostic export is a bug-report artefact, not a
  backup format, and calling it one would invite it to be used as one.
