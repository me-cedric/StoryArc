# Licences

One inventory of everything StoryArc ships that someone else wrote, and the licence
text each entry needs.

## Why it is here rather than in each app

The same reason [`packages/fonts`](../fonts/README.md) and
[`packages/test-fixtures`](../test-fixtures) are shared: two copies of a list drift,
and this one has a legal consequence when it does. BSD and Apache both require the
notice to travel with the *binary*, not only with the repository — so both apps stage
this directory and their acknowledgements screens read it.

## What is here

| File | What it is |
| --- | --- |
| `notices.json` | The inventory. Name, version where it matters, licence identifier, where it came from, and why it is in the app. |
| `texts/<identifier>.txt` | The licence text, one file per identifier, from [SPDX's own list](https://github.com/spdx/license-list-data). |

`notices.json` is the source of truth. Every `licence` value names a file in `texts/`,
and the acknowledgements screen shows the text for whichever entry a reader taps.

## Adding a dependency

1. Add an entry to `notices.json`. `why` is not decoration — a dependency whose reason
   nobody can state is a dependency to remove.
2. If its licence is not already in `texts/`, fetch it from SPDX by identifier:
   ```bash
   curl -sL https://raw.githubusercontent.com/spdx/license-list-data/main/text/MIT.txt \
     -o packages/licences/texts/MIT.txt
   ```
3. Check whether the licence needs the *copyright holder's* notice as well as the
   licence body. BSD and MIT do; the SPDX text carries a `<year> <owner>` placeholder
   for exactly that, and the holder belongs in the entry rather than in the text.

## What this does not cover

Platform SDKs. Apple's frameworks and the Android platform are not redistributed by
this app and carry their own terms with the operating system.

## The audit

[`THIRD_PARTY_NOTICES.md`](../../THIRD_PARTY_NOTICES.md) at the repository root is the
human-readable version, generated from this inventory. It is what
[`third_party/libarchive/VENDORING.md`](../../third_party/libarchive/VENDORING.md)
points at.
