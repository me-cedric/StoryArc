## Context

Covers already resolve from the publication's own bytes, through `CoverLoader` into
`CoverCache`, keyed by `Publication.id` and pixel size. A server row falls back to a Kavita
chapter-cover fetch or an OPDS thumbnail. Everything else reaches `CoverlessWell`, which draws
a glyph and the format's name and offers nothing.

So the ladder's bottom rungs exist. This change adds a rung above them (a lookup), a rung
beside them (the reader's own picture), and makes the well an entry point instead of a dead end.

## Goals / Non-Goals

**Goals.** A reader can always get a cover. The cheapest source wins. Nothing leaves the device
until they say so.

**Non-Goals.** Matching a library automatically and in bulk. Scraping. A metadata editor —
this change sets a picture, not a title, an author or a series.

## Decisions

### The override is keyed by content digest

`contentDigest` survives a rename and a move. The alternatives do not: `stableID` breaks when a
file moves, a folder publication carries no digest at all, and a re-added server mints a fresh
`Source` UUID, so every row under it changes identity. A reader who reorganises their files
should not lose the covers they chose, and reorganising files is the normal life of a library.

Where there is no digest — a folder of images, a server row — the override falls back to the
stable identifier and the app says plainly that moving it loses the choice. A silent loss would
be worse than a stated limit.

### The image does not live in the caches directory

`StorageUsage.clearCache` empties the caches directory, and a cover the reader chose is not a
cache: nothing can recreate it. It goes in the app's own data directory, and it is included in
the export this project is specifying separately.

### The lookup asks keyless providers, and asks for one thing

Open Library (ISBN), Cover Art Archive (MBID) and Audnexus (ASIN) need no API key and no owner
account, which is what keeps this feature from becoming an owner task. Google Books was
considered and rejected: it needs a key the owner must create, and its terms require a
"powered by Google" logo and a link to the Google Books page beside every result, which puts
another brand on StoryArc's publication page.

Each request carries one identifier. Not the library, not a device identifier, not a history.
That is the whole of what leaves the device, and the setting that enables it says so.

### A title search needs the reader to confirm

An identifier is exact. A title is not: *Book 03* matches thousands of things. Audiobookshelf
solved this by asking the reader, and that is the honest answer here too. The app shows the
candidates it found and the reader picks. It never adopts an uncertain match on its own,
because a confidently wrong cover is worse than a glyph.

### The web search is a hand-off, not a web view

This is the one place this change departs from what was asked for, so the reason is recorded at
length.

App Store Review Guideline 5.2.3 bans saving media from third-party sources without that
source's authorization. An in-app web view that captures an image, whether by screenshot or by
reading the element's `src`, is StoryArc performing that save. The system browser performing it
is the reader using their browser, which is what every person does already.

`SFSafariViewController` hides its page from the host app by design, so the app cannot read it
even if a later edit tried to. That is a feature here, not a limit.

It also keeps one security posture. StoryArc's only web view today — the EPUB reader — denies
all network egress through `PublicationEgress`. A second web view that exists to load Google
would be the opposite rule on the same app, and two rules about the same primitive is how a
security property quietly stops being true.

### Writing back is offered where it works, and nowhere else

Kavita has six cover-upload routes. Five need the administrator role. Only the reading-list
route admits a normal reader, and only for a list they own. OPDS has no write operation in
1.2 or 2.0 — not a missing feature, an absent concept.

So the app offers the write on a reading list the reader owns, warns that it changes the cover
for everyone who sees that list, and offers nothing anywhere else. An action that exists and
answers 403 teaches a reader that the app is broken.

## Risks / Trade-offs

**A cover found on the web is still someone's artwork.** The app stores it on the device for
the reader's own copy, and never republishes, uploads or shares it — except to a Kavita reading
list the reader chose to write to, which the app warns about in those words.

**Open Library rate-limits ISBN lookups** to 100 requests per IP per five minutes. A reader
importing a large library could hit it. The cache, the one-identifier-per-publication rule, and
backing off rather than retrying are what keep this polite; a bulk "fetch every missing cover"
action is deliberately not part of this change.

**The hand-off is more taps** than an in-app capture: search, save, return, pick. That is the
cost of not building the thing the guidelines describe.

## Migration Plan

None. Every publication keeps the cover it resolves today; the ladder only adds rungs beneath
and above what already runs.

## Open Questions

None blocking. The owner asked for an in-app locked web view; this proposes the hand-off
instead and states why at length above. If the owner still wants the in-app capture after
reading that, it is their call to make, and the spec's *the app downloads nothing* scenario is
the one that would have to change.
