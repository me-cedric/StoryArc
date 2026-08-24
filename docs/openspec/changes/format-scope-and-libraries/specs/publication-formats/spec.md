## MODIFIED Requirements

### Requirement: Supported formats

The app SHALL open the following formats:

| Format | Container | Notes |
| --- | --- | --- |
| CBZ | ZIP | Primary comic format |
| CBR | RAR | RAR4 and RAR5 |
| CBT | TAR | |
| EPUB | ZIP | EPUB 2 and EPUB 3, reflowable and fixed-layout |
| PDF | — | Including scanned, image-only PDFs |
| Plain folder | — | A directory of ordered images treated as one publication |

CB7 is **not** supported. It is rare, and it is the worst streaming case — solid
blocks mean one page can require decompressing everything around it. It receives
the same named refusal as any other unsupported container.

#### Scenario: Detecting format
- **WHEN** a publication is opened
- **THEN** the format is determined from the file's contents, not its extension
- **AND** a mis-named file — a ZIP called `.cbr` — still opens

#### Scenario: An unsupported container is named, not merely rejected
- **WHEN** a user opens a CB7, or any other container StoryArc does not read
- **THEN** the app names the container it detected and states which formats it does support
- **AND** it never reports a generic failure, because "7-Zip is not supported" tells the user what to do and "could not open file" does not

#### Scenario: Encrypted or password-protected archive
- **WHEN** an archive requires a password
- **THEN** the app states that the archive is protected and does not prompt for a password, because StoryArc does not manage archive passwords

#### Scenario: Corrupt archive
- **WHEN** an archive is truncated or its index is unreadable
- **THEN** the app opens whatever pages it can read and states how many were skipped, rather than refusing the whole publication

## ADDED Requirements

### Requirement: Streaming capability per format

Ranged reads are not uniformly possible, so the app SHALL know which formats can
be read remotely and SHALL be honest when one cannot.

| Format | Remote reading |
| --- | --- |
| CBZ, EPUB | Streams. Index at the end, entries stored independently |
| PDF | Streams. Cross-reference table at the end |
| CBT | Streams once an index is built by hopping headers |
| CBR, non-solid | Streams |
| CBR, solid | **Cannot stream.** Every file before the target must be decompressed |
| Plain folder | Each page is its own file, so trivially |

#### Scenario: Opening a streamable publication from a remote source
- **WHEN** a user opens a streamable publication on a network share or a server
- **THEN** the first page renders without the whole publication being transferred

#### Scenario: Opening a solid archive from a remote source
- **WHEN a** publication cannot be read with ranged reads
- **THEN** the app says the format has to be downloaded before it can be read, states the size, and offers to download it
- **AND** it does not begin streaming badly and leave the user watching a stalled page

#### Scenario: A solid archive already downloaded
- **WHEN** a publication that cannot stream is already available offline
- **THEN** it opens directly with no notice, because the constraint was never about the format being readable

#### Scenario: Streaming capability is known before the first page is requested
- **WHEN** a publication is indexed
- **THEN** whether it can be read remotely is recorded with it, so the library can warn before a user taps rather than after
