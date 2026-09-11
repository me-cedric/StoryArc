# Design

The issue rows are a join on the device. This page states what is joined, where
the join lives, and what the join cannot cover.

## What the server gives, and what it withholds

Measured against Kavita's own source at tag v0.8.7,
`API/Data/Repositories/SeriesRepository.cs`:

| Group in the response | Matched on | Usable here |
| --- | --- | --- |
| `series` | the series name | yes, and it carries the numeric series id |
| `chapters` | `TitleName`, `ISBN`, `Range` | yes, but a chapter holds no series name |
| `files` | the file path | no: filled for an administrator only, and `MangaFileDto` carries no `seriesId` and no `chapterId` |

So a query naming a series finds the series and none of its issues. The join
supplies the issues.

## What is joined

| Field of the issue row | Taken from |
| --- | --- |
| the row's words | `Publication.displayTitle`, written by `KavitaNaming` |
| the series to open | the numeric id on the server's own series hit |
| the chapter's identity | the digits after `chapter:` in the publication's remote id |

The publication and the series hit are matched on the series name, because
`KavitaContributor` writes `series` from the same `KavitaSeries.name` the server
answers a series hit with. An exact match is correct here; a looser one would
draw one series' issues under another's name.

## Where the join lives

One pure function per platform, in the module that already holds `KavitaFind`,
with the same name and the same shape on both.

- **iOS.** `Sources/StoryArcCore/KavitaIssues.swift`, Swift 6, iOS 26.1.
  A new file rather than a new function in `KavitaFind.swift`, because that file
  is 397 lines and the Swift cap is 400.
- **Android.** `core/model/src/main/kotlin/app/storyarc/core/model/KavitaIssues.kt`,
  Kotlin, minSdk 31. A new file, so the twin carries the same name, per ADR-0001.

The finder on each platform holds the source's publications as search input, the
way it holds the term. The view that knows the library sets them; every view
below it already carries the finder, so nothing else is plumbed.

## Duplicate rows, and why the hit id is not enough

`KavitaHit.id` is `kind:seriesId:chapterId:title`. Two producers can name one
chapter: the server writes `displayName`, the join writes `displayTitle`, and
the two differ. An id-level dedupe would therefore pass both, and the search
list is keyed on that id — Compose refuses two rows with one key, and SwiftUI
draws one of them. The join therefore dedupes on kind, series id and chapter id,
and drops its own row when the server already sent that chapter.

## What the reader sees

No new view and no new string. A joined row is a `CHAPTER` hit, so it files
under the existing Chapters heading. It carries a series id and no download id,
so it draws as openable and opens its series, which is what a chapter hit from
the server does today.

## Accessibility consequence

The new rows are text in an existing list, read by VoiceOver and TalkBack with
the heading above them. Nothing is conveyed by colour alone. The dim colour of
an inert row keeps its existing meaning, and a joined row is never inert.

## Open Questions

- **A tapped issue opens its series, not the file.** Opening the file needs a
  `KavitaChapter`, and the join holds a `Publication`. The series route adds no
  code and lands the reader one tap away.
- **The join covers the slice the library holds.** `KavitaContributor` reads a
  first slice of a server, so a series past that slice contributes no issues
  even when the server matched it. The scenario says so.
