## Purpose

Where a publication's cover comes from, what a reader may do when there is none, and what the
app may send off the device to find one. The artwork is this app's interface, so a publication
with no cover is a publication a reader cannot pick out of a shelf.

## ADDED Requirements

### Requirement: The cover ladder

The app SHALL resolve a publication's cover by trying each source in order, cheapest first, and
SHALL stop at the first that answers. A rung that needs the network SHALL NOT be tried before
every rung that does not.

#### Scenario: The publication's own bytes answer
- **WHEN** a publication is indexed and its file carries artwork — a comic's cover page, an EPUB's declared or first-spine image, a PDF's first page, an MP4 `covr`, an ID3 `APIC`, a FLAC picture
- **THEN** that artwork is the cover, and nothing is fetched

#### Scenario: A cover image sits beside the file
- **WHEN** the file carries no artwork, and a `cover`, `folder` or `poster` image sits in the same folder, or in an audiobook's own folder
- **THEN** that image is the cover, and nothing is fetched

#### Scenario: The source states a cover
- **WHEN** the publication comes from a Kavita server or an OPDS catalogue, and that source offers a cover
- **THEN** the source's cover is used, through the credential and the certificate pins that source already carries

#### Scenario: Nothing answers
- **WHEN** no rung answers
- **THEN** the coverless well is drawn, and it offers the reader a way to set a cover rather than only naming the format

### Requirement: A reader may choose a cover

The app SHALL let a reader set any picture as a publication's cover, on both platforms, without
a network request and without a permission prompt.

#### Scenario: Choosing a picture
- **WHEN** a reader asks to change a publication's cover
- **THEN** the system picker opens — `PHPickerViewController` on iOS, the photo picker on Android — and no photo-library permission is requested, because neither picker needs one
- **AND** the chosen picture is cropped to the cover shape before it is stored

#### Scenario: A chosen cover outlives a rename
- **WHEN** a publication whose cover the reader chose is renamed, or moved to another folder, and indexed again
- **THEN** the chosen cover is still its cover, because the override is keyed by the content digest rather than by a path or a per-source identifier

#### Scenario: A publication with no digest
- **WHEN** the publication is a folder of images, or a server row, neither of which carries a content digest
- **THEN** the override is keyed by that publication's stable identifier instead, and the app states that moving it loses the chosen cover

#### Scenario: Undoing the choice
- **WHEN** a reader removes a cover they chose
- **THEN** the ladder resolves the cover again from the rung below, and the stored image is deleted

#### Scenario: The chosen cover survives a cache clear
- **WHEN** the reader clears the app's cache from Settings
- **THEN** every chosen cover is still there, because a chosen cover is data the reader created and not a cache

### Requirement: Looking a cover up is the reader's choice

The app SHALL NOT request a cover from any third party until a reader turns the lookup on, and
SHALL name the provider it would ask before they do.

#### Scenario: The lookup is off until it is turned on
- **WHEN** a reader has never opened the cover-lookup setting
- **THEN** no cover request is made to any third party, and the ladder stops at the rungs that need no network

#### Scenario: Asking by an identifier the file carries
- **WHEN** the lookup is on, and the publication carries an identifier — an ISBN from an EPUB's OPF, a MusicBrainz release-group id, an Audible ASIN
- **THEN** the app asks the provider that identifier belongs to: Open Library for an ISBN, Cover Art Archive for an MBID, Audnexus for an ASIN
- **AND** it sends the identifier and nothing else: no library listing, no reading history, no device identifier

#### Scenario: Asking by a title, and confirming the answer
- **WHEN** the lookup is on and the publication carries no identifier
- **THEN** the app may search by the title and author it parsed, and SHALL show the candidates and let the reader choose
- **AND** it never silently adopts a match it is not certain of, because a wrong cover is worse than none

#### Scenario: A provider refuses or rate-limits
- **WHEN** a provider answers 403, 404, 429, or does not answer
- **THEN** the publication keeps the cover it had, the reader is not shown an error for a cover they did not ask about, and the app does not retry in a loop

#### Scenario: Every answer is cached
- **WHEN** a lookup answers
- **THEN** the result is written to disk and the same publication is never looked up twice, because a provider that asks not to be crawled is entitled to that

### Requirement: Finding a cover on the web is a hand-off

Where no provider can answer, the app SHALL help the reader search the web without downloading
anything itself.

#### Scenario: The hand-off
- **WHEN** a reader asks to find a cover on the web
- **THEN** the system browser opens an image search for that publication's title — `SFSafariViewController` on iOS, a Custom Tab on Android — and the reader saves a picture with the browser's own menu
- **AND** the reader then sets that picture as the cover through the system picker

#### Scenario: The app downloads nothing
- **WHEN** the reader is searching in that browser
- **THEN** StoryArc reads nothing from the page, captures no screenshot, injects no script, and receives no image: the browser performs the save, and the app learns of the picture only when the reader picks it

### Requirement: Writing a cover back to a source

The app SHALL offer to write a cover back to a source only where that source accepts one from
the reader who is signed in, and SHALL NOT offer it anywhere else.

#### Scenario: A Kavita reading list the reader owns
- **WHEN** a reader sets a cover on a Kavita reading list they own
- **THEN** the app may offer to write it to the server, and SHALL say that this changes the cover for everyone who can see that list

#### Scenario: A Kavita series, chapter, collection or library
- **WHEN** a reader sets a cover on any other Kavita entity
- **THEN** no write is offered, because those routes need the administrator role and most readers are not administrators on someone else's server

#### Scenario: An OPDS catalogue
- **WHEN** a reader sets a cover on a publication from an OPDS catalogue
- **THEN** no write is offered, because OPDS has no write operation in either version 1.2 or version 2.0, and the cover stays on this device
