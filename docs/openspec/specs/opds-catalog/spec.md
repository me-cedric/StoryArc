# opds-catalog Specification

## Purpose

Browsing and reading from OPDS catalogues — the open standard most self-hosted
library servers speak, including Calibre-Web, Komga, Kavita, and Ubooquity. OPDS
is the interoperability floor: if a server speaks it, StoryArc reads it.

## Requirements

### Requirement: OPDS protocol support

The app SHALL support OPDS 1.2 (Atom) and OPDS 2.0 (JSON), detecting the version
from the response rather than requiring the user to declare it.

#### Scenario: Adding a catalogue
- **WHEN** a user enters a catalogue URL
- **THEN** the app fetches the root feed, detects the OPDS version, and shows the catalogue title as confirmation before saving

#### Scenario: Version detection fails
- **WHEN** a URL returns something that is not an OPDS feed
- **THEN** the app says what it received — an HTML page, a redirect, a 404 — instead of reporting a generic failure

#### Scenario: HTTP authentication
- **WHEN** a catalogue responds with a 401
- **THEN** the app prompts for credentials, supporting HTTP Basic and Bearer tokens
- **AND** stores the secret per the credential rules in [`sources`](../sources/spec.md)

#### Scenario: Self-signed certificate
- **WHEN** a catalogue presents a certificate the system does not trust
- **THEN** the app refuses the connection by default and explains why
- **AND** offers to pin that specific certificate after showing its fingerprint and an explicit warning

### Requirement: Feed navigation

The app SHALL present navigation feeds as browsable sections and acquisition
feeds as publication grids, following facets and pagination.

#### Scenario: Browsing a navigation feed
- **WHEN** a feed contains navigation links
- **THEN** each is shown as a section the user can enter, with its title and, where the feed provides one, its item count

#### Scenario: Grouped feed
- **WHEN** an OPDS 2.0 feed divides itself into named groups
- **THEN** each group is shown under its own title, rather than merged into one run of
  entries
- **AND** a group that carries a link to its own feed offers a way into the rest of it
- **AND** a group the feed left unnamed is shown as part of the page, because there is no
  title to head it with

#### Scenario: Paginated feed
- **WHEN** an acquisition feed provides a `next` link
- **THEN** the app loads further pages as the user scrolls, without a visible "load more" control

#### Scenario: Facets
- **WHEN** a feed exposes facets such as language, format, or sort order
- **THEN** they appear as filters in the browsing UI described in [`library-browsing`](../library-browsing/spec.md)

#### Scenario: Search
- **WHEN** a catalogue advertises an OpenSearch description
- **THEN** searching within that source queries the server rather than filtering locally
- **AND** a catalogue without search falls back to filtering the cached catalogue, and says so

### Requirement: Acquisition

The app SHALL open or download a publication using the acquisition link the feed
provides, choosing the best supported format when several are offered.

#### Scenario: Publication detail
- **WHEN** a user chooses a publication in a catalogue
- **THEN** the app shows what the feed says about it — its cover at a size worth looking at,
  its title, authors, series and description — and every acquisition the catalogue offers,
  with the format the app would take marked as the one a single press opens

#### Scenario: Multiple formats offered
- **WHEN** an entry offers both EPUB and PDF
- **THEN** the app selects EPUB for reflowable reading and lets the user choose another format from the publication detail screen

#### Scenario: No supported format
- **WHEN** an entry offers only formats StoryArc cannot read
- **THEN** the entry is listed but marked unreadable, naming the formats offered

#### Scenario: Borrowing and indirect acquisition
- **WHEN** an entry uses an indirect acquisition link, such as an OPDS-LCP or borrow flow
- **THEN** the app states that the acquisition type is not supported rather than failing silently

## Open Questions

- LCP-protected publications require the Readium LCP library and a content
  provider agreement. Out of scope for 1.0; the spec records the refusal path
  above so the behaviour is defined rather than accidental.
