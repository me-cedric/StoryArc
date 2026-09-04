## Purpose

The page a publication has. What it is, what the reader can do with it, and — in
one line at the bottom — where it lives.

This capability is the seam. [`library-browsing`](../library-browsing/spec.md)
presents every source as one library and states that origin is invisible on the
shelf; that only works because origin is *here*. This is the one surface that
presents a file on the device, an entry in a catalogue, a chapter on a server and
a file on a share identically, and then says which of them this one is.

It is also the app's only screen between the shelf and the reader, so everything
that is not reading lives here: downloading, adding to a shelf, marking read,
and the rest of the series.

## ADDED Requirements

### Requirement: Reaching a publication's page

A publication's page SHALL be reachable from every surface that shows a
publication, and SHALL be distinguished from resuming, which opens the book
directly.

#### Scenario: From a cover
- **WHEN** a reader chooses a cover in the library, in a shelf, in search results or in a collection
- **THEN** the publication's page opens within the destination they were already in
- **AND** going back returns them to exactly where they were, with scroll position, filters and selection intact

#### Scenario: Resuming does not come here
- **WHEN** a reader chooses a publication from Keep reading, or any other affordance that offers to resume
- **THEN** the book opens at the recorded position, without this page in between
- **AND** the page remains reachable from that publication's cover elsewhere

#### Scenario: The same page for every kind of publication
- **WHEN** the page opens for a file on the device, a cached catalogue entry, a chapter on a server, or a file on a share
- **THEN** it has the same composition, the same actions in the same places, and the same information in the same order
- **AND** nothing but the provenance line differs

#### Scenario: A publication that is no longer there
- **WHEN** the page is opened for a publication the library can no longer place — a stale shortcut, a removed source, a deleted file
- **THEN** the reader is returned to the surface they came from with a plain sentence saying it is gone
- **AND** they are not left on an empty page

### Requirement: What the page shows

The page SHALL present the publication's cover, its title, its series and year
where declared, its description where one exists, and the rest of its series.

#### Scenario: The cover leads
- **WHEN** the page opens
- **THEN** the cover is the largest thing on it, shown whole rather than cropped, and the title sits with the series and the year as one block

#### Scenario: Other issues in this series
- **WHEN** the publication declares a series the library holds more of
- **THEN** the rest of that series is offered as a shelf, in volume and chapter order, marked with what has been read and what is on the device
- **AND** each entry leads to its own page

#### Scenario: Metadata the publication does not carry
- **WHEN** a publication declares no series, no year, or no description
- **THEN** those lines are absent rather than shown empty or filled with a placeholder
- **AND** the page's composition holds together with only a cover and a title

#### Scenario: No cover art
- **WHEN** a publication has no cover, or its cover cannot be decoded
- **THEN** the page uses the app's own placeholder and stays legible, with no derived colour taken from it
- **AND** the title is never rendered over an image that failed to load

### Requirement: One primary action

The page SHALL offer exactly one primary action — to read, or to continue where
the reader stopped — and SHALL keep every other action secondary.

#### Scenario: Reading from here
- **WHEN** a reader takes the primary action
- **THEN** the book opens: at the start if it has not been read, at the recorded position if it has
- **AND** the action's wording says which of those will happen before it is taken

#### Scenario: Everything else
- **WHEN** a reader wants to download it, remove its download, add it to a shelf, mark it read or unread, or remove it
- **THEN** each is available from this page without competing with the primary action
- **AND** an action that does not apply is absent, not shown disabled without explanation

#### Scenario: Downloading from here
- **WHEN** a reader downloads the publication from this page
- **THEN** progress is shown on this page, and the primary action stays usable, because [`offline-downloads`](../offline-downloads/spec.md) allows reading while downloading
- **AND** when it completes the page states it is now readable with no network, without the reader refreshing anything

#### Scenario: The primary action cannot be honoured
- **WHEN** the publication is neither on the device nor currently reachable
- **THEN** the primary action states what it needs in plain language rather than failing when taken
- **AND** the download action is offered in its place, queued for when the source returns

### Requirement: Where it came from

The page SHALL carry exactly one line naming where the publication lives and
whether it can be read right now, and this SHALL be the only place on the browse
path where origin is named.

#### Scenario: What the line says
- **WHEN** the page is shown
- **THEN** one line, quietly typeset at the foot of the information, says both where the publication lives — on this device, or in a named library the reader added — and whether it can be opened now
- **AND** it names the library by the name the reader gave it

#### Scenario: What the line never says
- **WHEN** that line is composed
- **THEN** it never names a protocol, a transport, a server product, a file path, a URL or an identifier
- **AND** no other surface on the browse path — the home surface, the library, the on-device destination, shelves — states origin at all
- **AND** search results are the single exception, and only where more than one place could have answered the query, per [`library-browsing`](../library-browsing/spec.md): a search row is the choice itself, since a row a library supplied need not lead to this page at all, so the seam has nowhere else to be named

#### Scenario: The same publication in two places
- **WHEN** the library holds the same publication from more than one source, or a copy is on the device and the library it was fetched from is still configured
- **THEN** the line names the one this page will open, and says the publication is also available elsewhere
- **AND** the reader can see which copy they are about to read before they read it
- **AND** a copy on the device is always the one this page will open, so it is the place the line names and every other place is the second one
- **AND** a second place whose source has been removed is not named, per *Its source has been removed*

#### Scenario: Its source has been removed
- **WHEN** the publication's source has been removed but the download is still on the device
- **THEN** the line says it is on this device, and does not name a library that no longer exists
- **AND** the publication stays readable, per [`offline-downloads`](../offline-downloads/spec.md)

### Requirement: Colour taken from the cover

The page's background SHALL be derived from the publication's own cover, and the
derived colour SHALL be adjusted until it clears the contrast floor in the design
tokens rather than used as it comes out of the image.

#### Scenario: The wash
- **WHEN** the page opens for a publication with a cover
- **THEN** the background carries a colour derived from that cover, so the screen belongs to the book
- **AND** the cover itself is not tinted, recoloured or dimmed by it

#### Scenario: Contrast is not negotiable
- **WHEN** a derived colour would put any text or control below the contrast floor the design tokens define
- **THEN** it is adjusted in lightness until it clears the floor, however far that is from the cover's own colour
- **AND** the floor is never lowered to keep a colour

#### Scenario: Chrome does not take it
- **WHEN** the derived colour is applied
- **THEN** it reaches the page's content surfaces only
- **AND** navigation, toolbars and any floating chrome stay as [`native-experience`](../native-experience/spec.md) requires, so chrome does not change hue as a reader moves between publications

#### Scenario: A cover that yields nothing usable
- **WHEN** a cover is monochrome, nearly white, nearly black, or cannot be sampled
- **THEN** the page falls back to the app's own accent and stays legible
- **AND** it does not render a wash so faint or so dark that the screen looks broken

#### Scenario: High contrast and reduced transparency
- **WHEN** the system asks for increased contrast or reduced transparency
- **THEN** the wash is replaced by a plain surface rather than being softened
- **AND** nothing on the page depends on the wash to be readable or to be found
- **AND** where a platform offers only one of the two settings, that one answers the whole scenario and the app does not invent the other: Android ships contrast stops and no transparency switch, so its contrast branch is the whole of its obligation here

### Requirement: The page on a large screen

In a wide window the page SHALL be presented beside the library rather than over
it, and SHALL survive the window changing size.

#### Scenario: Two panes
- **WHEN** a reader chooses a cover in a wide window
- **THEN** the page appears beside the library, which stays visible and usable
- **AND** choosing another cover replaces the page's contents without the library scrolling or losing its place

#### Scenario: The pane before anything is chosen
- **WHEN** a wide window is opened and no publication has been chosen
- **THEN** the second pane says so in one sentence rather than showing an arbitrary publication or an empty rectangle

#### Scenario: The window narrows
- **WHEN** the window narrows below what two panes need
- **THEN** the page the reader was looking at fills the window, and going back returns to the library
- **AND** widening the window again restores both panes, with the same publication shown

#### Scenario: Going back
- **WHEN** a reader uses the platform's own back affordance from the page
- **THEN** they return to the surface they came from, and on Android the gesture previews that return as the system requires
