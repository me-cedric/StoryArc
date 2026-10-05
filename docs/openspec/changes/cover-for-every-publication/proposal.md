## Why

A publication with no cover draws `CoverlessWell`: a format glyph and a format name. It is a
dead end. A reader looking at a shelf of audiobooks ripped from CDs, or comics named
`Book 03.cbz`, sees a wall of glyphs and cannot tell one from another — and the artwork is
this app's interface, by its own first principle.

Every cover StoryArc draws today comes out of the publication's own bytes. When the bytes carry
none, there is nothing a reader can do about it. This change gives them three things to do, in
the order that costs least.

## What Changes

- **A cover ladder, cheapest rung first.** Embedded artwork, then a loose cover image beside the
  file, then the server's own cover, then — only with the reader's consent — a lookup by
  identifier, and at any point the reader's own picture.
- **The reader can choose a cover from their photos or files**, on both platforms, through the
  system picker. This always works and needs no network, no key and no permission prompt.
- **An optional lookup by identifier**, off until the reader turns it on, against keyless open
  APIs: Open Library by ISBN, Cover Art Archive by MBID, Audnexus by ASIN.
- **A "find a cover on the web" hand-off** for the case no identifier can answer. The system
  browser opens an image search for the title; the reader saves a picture with the browser's
  own menu and then picks it. StoryArc downloads nothing — see the Impact note below, which is
  the reason the flow has this shape rather than the in-app one first asked for.
- **A chosen cover is stored locally, keyed by content digest**, so it survives a rename and a
  move.
- **Pushing a cover back to a server is built for the one case that works**: a Kavita reading
  list the reader owns. Every other Kavita route needs an admin, and OPDS has no write
  operation at all, so neither is offered rather than offered and refused.

## Capabilities

### New Capabilities

- `cover-art`: where a publication's cover comes from, what a reader may do when there is none,
  and what the app may and may not send anywhere to find one.

### Modified Capabilities

- `publication-formats`: cover extraction is specified there today, and the ladder adds rungs
  below and above it.
- `kavita-server`: a cover a reader sets on a reading list they own may be written back.

## Impact

**The in-app locked web view was asked for and is not what this proposes.** App Store Review
Guideline 5.2.3 bans saving media from third-party sources without the source's authorization,
and Google's terms say the same about other people's content. StoryArc's only web view today
denies all network egress (`PublicationEgress`), so a search web view would reverse that
posture for one screen. The system-browser hand-off gives the reader the same result — they
search, they choose, they keep the picture — with the download outside the app, where it is the
browser's business and not StoryArc's. `SFSafariViewController` also hides the page from the
app by design, which is the point.

- New: a cover-override store and an image directory per platform, outside the caches directory,
  because `StorageUsage.clearCache` empties that.
- `CoverLoader`, `CoverCache`, `ServerCoverCache`, `CoverlessWell` on iOS and their Android
  counterparts.
- `PublicationIndexer` on both platforms, for the embedded-artwork rung — task 16.9 of
  `close-the-audited-gaps` is that rung, and is open only on the Android Storage Access
  Framework paths.
- A network egress rule: a lookup is a new place data goes, and AGENTS.md non-negotiable 2 says
  data leaves the device only to sources the user configured. That is why the lookup is off by
  default and names its provider.
