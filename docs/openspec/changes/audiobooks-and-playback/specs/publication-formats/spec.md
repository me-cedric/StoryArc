## MODIFIED Requirements

### Requirement: Supported formats

The app SHALL open the following formats:

| Format | Container | Notes |
| --- | --- | --- |
| CBZ | ZIP | Primary comic format |
| CBR | RAR | RAR4 and RAR5, except solid RAR4 — see below |
| CBT | TAR | |
| EPUB | ZIP | EPUB 2 and EPUB 3, reflowable and fixed-layout |
| PDF | — | Including scanned, image-only PDFs |
| Plain folder | — | A directory of ordered images treated as one publication |
| M4B | MPEG-4 | Chaptered audiobook. Chapters from the container's own markers |
| Audio folder | — | A directory of ordered audio files treated as one audiobook |
| Single audio file | — | MP3, M4A, AAC, FLAC, Opus or Vorbis as a one-part audiobook |

CB7 is **not** opened. It receives the same named refusal as any other container
the app does not read. Whether to add it is a product decision that has not been
made — see the Open Questions below.

**Solid RAR4 is not supported either**, and unlike CB7 that is a decoder limit
rather than a choice. The only RAR decoder with an OSI-approved licence does not
implement solid RAR4 at all, so no amount of downloading makes such a file
readable. Solid RAR5 *is* fully supported; it simply cannot be streamed.

**Encrypted audiobooks are not opened.** An Audible `.aax` or `.aaxc`, or any other
audio behind a content protection, is refused by name. That is a deliberate limit
and not a decoder one: StoryArc does not implement, circumvent or advise on removing
a protection, so the refusal will not change.

#### Scenario: Detecting format
- **WHEN** a publication is opened
- **THEN** the format is determined from the file's contents, not its extension
- **AND** a mis-named file — a ZIP called `.cbr` — still opens

#### Scenario: An audiobook is recognised as one
- **WHEN** a file or folder holding audio is opened
- **THEN** it is recognised from its contents as an audiobook and opens in the player rather than in a reader
- **AND** an `.m4b` and an `.m4a` holding the same audio are treated identically, because the extension is a hint and the contents are the fact

#### Scenario: A folder of audio files is one audiobook
- **WHEN** a folder holds ordered audio files
- **THEN** it is treated as a single audiobook whose parts play in that order, by the same ordering rule that makes a folder of images one comic
- **AND** a folder mixing audio and images is treated as the kind the majority of its entries are, and states which it chose

#### Scenario: An audiobook with no chapter markers
- **WHEN** an audiobook carries no chapter markers
- **THEN** it opens, and its parts — the files, or the whole of a single file — stand in for chapters
- **AND** nothing is reported as missing, because an unchaptered audiobook is a normal audiobook

#### Scenario: An encrypted audiobook is refused by name
- **WHEN** an `.aax`, `.aaxc` or other protected audio file is opened
- **THEN** the app states that the file is protected by its store's content protection and that StoryArc cannot open it, naming that as the reason
- **AND** it does not prompt for a key, an account or an activation code, and does not suggest a way around the protection
- **AND** the refusal is distinct from an unsupported container, because the format itself is supported and this particular file is locked

#### Scenario: An unsupported container is named, not merely rejected
- **WHEN** a user opens a CB7, or any other container StoryArc does not read
- **THEN** the app names the container it detected and states which formats it does support
- **AND** it never reports a generic failure, because "7-Zip is not supported" tells the user what to do and "could not open file" does not

#### Scenario: A solid RAR4 is refused before any page is shown
- **WHEN** a solid RAR4 is opened
- **THEN** the app states that the comic uses solid compression and cannot be opened, naming that as the reason
- **AND** it does not present the first page, because only the first entry of a solid archive is readable and a one-page comic that fails on the second turn is worse than a clear refusal
- **AND** the refusal is distinct from an unsupported container, because RAR *is* supported and this particular file is not

#### Scenario: A damaged archive is not reported as an unsupported one
- **WHEN** a file carries a recognised container signature but nothing parseable behind it
- **THEN** the app reports it as damaged rather than as a format it does not support
- **AND** it does not suggest converting the file, because a truncated download is not a format problem

#### Scenario: A damaged audiobook
- **WHEN** an audiobook's audio is truncated or one file of a folder cannot be decoded
- **THEN** the app plays what it can and states how much it could not, by the same rule that opens a comic missing pages
- **AND** the count is stated in the player's own controls rather than interrupting playback

#### Scenario: Encrypted or password-protected archive
- **WHEN** an archive requires a password
- **THEN** the app states that the archive is protected and does not prompt for a password, because StoryArc does not manage archive passwords

#### Scenario: Corrupt archive
- **WHEN** an archive is truncated or its index is unreadable
- **THEN** the app opens whatever pages it can read and states how many were skipped, rather than refusing the whole publication
- **AND** the count is shown in the reader's own controls, where it recedes with them,
  because it is a fact about the file rather than about the page in front of the reader
