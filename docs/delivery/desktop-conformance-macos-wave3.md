# macOS conformance walk — wave 3

Task 3.16 of `desktop-clients`. Every scenario of the capabilities wave 3 lane M names, run
against the Mac app at the head of `lane/macos-wave3` on 2026-10-17 (macOS 27.0.1, Xcode 27.1,
the ad-hoc signed sandboxed build), with the result it gave. `xcodebuild test` passes 206 tests
in 53 suites, the capture suites skipped as they are unless asked for. The scenarios are read
from the specs by name, so a scenario added to a spec later is missing here until the walk
runs again. For `desktop-experience`, only the requirements the wave 3 tasks name are listed.

| Result | Means |
| --- | --- |
| pass | A named test in `apps/desktop-macos/Tests` asserts it inside the running app. |
| seen | A wave 3 frame (`docs/designs/screenshots/desktop/macos/wave3/`) or the app's code shows it; nothing asserts it. The evidence column says which. |
| **fail** | It does not hold on the Mac today. Each one is a missing piece, listed below. |
| later | Not on the Mac in wave 3, as named. |
| n/a | Dropped on a desktop by `design.md` Decision 9, or another system's scenario. |
| not walked | Built, mostly in StoryArcKit, and not exercised by a Mac walk, for the reason given. |

Totals: pass 60, seen 31, fail 1, later 23, n/a 4, not walked 71, of 190 scenarios (2026-10-18: the source
window, source rename and order, and the *All Shelves* window turned 17 failures; 18 before).

**What the walk is.** The walks run inside the app as `StoryArcMacTests` (`WindowWalks`), as
in wave 2: the fixture comics are copied into the container and scanned as the app's one
folder. Wave 3 adds walks against the repository's mock servers: the OPDS and Kavita mocks
(`scripts/opds-server.mjs`, `scripts/kavita-server.mjs`, run here on ports 4748 and 4747,
because macOS's AirPlay receiver holds port 5000) and the Samba share of
`scripts/smb-server.sh`, plain and with `smb encrypt = required`, run from the same
configuration in containers on 4745 and 4746 (signing in as `reader`), because Samba is not
installed on this Mac. The ports reach the walks as `TEST_RUNNER_STORYARC_*_PORT`, as
`Tests/MockServers.swift` says. A quit and a relaunch end the test host, so the download walk
asserts restoration on the saved queue, as the wave 2 walk did for windows.

**What the walks measured** (`ConformanceLog`, the container's `tmp/conformance/wave3.log`):

- sync at quit to a slow place: gave up after 5.05 seconds, and the quit went on;
- sync to a share: synced in 0.08 seconds;
- quit during a download: paused at 97 bytes with a resume token; the relaunch finished it;
- metered mid-download: held on metered, a download by hand ran, resumed on unmetered;
- shelf on Home: `AXButton` "Walk Shelf, 2 books";
- added catalogue *All publications*: 14 publications; *Members only*: 11;
- added Kavita server `ada · 127.0.0.1`: 14 publications;
- share `127.0.0.1/Comics`: 15 publications, SMB 3.1.1, encrypted;
- the encryption-required share: connected, SMB 3.1.1, encrypted;
- Bonjour discovery: one host on the walk's network, no advice shown;
- storage: downloads 300 000 bytes to 0 after their clear, covers 48 373 to 8. The reading
  records read 1 588 672 bytes before and 1 633 992 after their clear: the walk asserts that
  the records are gone, and the store's file is reopened and written again by the walks
  around it, so its size alone does not show the clear.

**Encryption, against the task's text.** Task 3.10 expected the `Smb` package to have no SMB 3
encryption and a share that requires it to fail by name. The vendored client of ADR-0019
encrypts, so the encryption-required mock connects encrypted, and the row says so. The walk
accepts either outcome and never a read in the clear; it saw *encrypted*.

**Wave 3 on this branch**, each with its commit: sources, the add sheets, Bonjour and the
metered rule (`03d8dfe8b`); downloads with the quit prompt and resume at launch (`0fc8f10fb`);
sync at start and quit (`d28523d43`); the diagnostic export and storage (`b775936ab`);
collections and reading lists (`c633edfd9`).

## The failures, in one list

- `kavita-server` · *Searching from the library, scoped to one server*: The Mac's library search reads the library alone; a server is searched only from its source window.

**The 3.15a gaps that are not failures.** A bulk download states its count but not its size,
because a catalogue entry gives no size before its download starts; the Downloads page counts
the size as each one begins. A bulk mark writes the Mac's progress store and does not push to
Kavita. The grey offline edit is a tested rule that no Mac screen reaches yet, because server
lists are not shown.

## sources

Source: `docs/openspec/specs/sources/spec.md`.

| Requirement | Scenario | Result | Evidence or reason |
| --- | --- | --- | --- |
| Source registry | Adding the first source | pass | `SourcesWalkTests` adds a catalogue, a Kavita server and a share, each of which joins the library; frame `settings-sources-*.png` |
| Source registry | Reordering sources | seen | A row's menu offers *Move Up* and *Move Down*, which call `LibraryModel.move`; `SourceOrderTests` holds the first and last places. |
| Source registry | Renaming a source | pass | `SourcesWalkTests` *An OPDS catalogue is added…* renames the source and reads the new name from the registry; the source window's *Rename* sheet makes the same call. |
| Source registry | Removing a source | pass | `SourcesWalkTests` removes each source it adds, and its books and its keychain item go with it; the confirmation says downloads and positions stay (`SourcesTab`) |
| Credential storage | Storing a secret | pass | `SourcesWalkTests` *A catalogue behind a sign-in asks for it, and the secret goes to the keychain only*; `MacCredentialStoreTests` |
| Credential storage | Secret appears in a diagnostic | pass | `DiagnosticExportTests` *Every credential, token and host is redacted, as on a phone* (StoryArcKit's `DiagnosticRedactionTests` pass unchanged, 15 of 15) |
| Credential storage | Reading a secret | pass | `MacCredentialStoreTests` *A secret saved on the chosen path reads back, and leaves with its source* |
| Connection state | Source becomes unreachable | pass | `SourceRowTests` *An unreachable source is grey and keeps its place* |
| Connection state | Credentials rejected | pass | `SourceRowTests` *A refused sign-in asks for the sign-in and offers to reconnect* |
| Connection state | Automatic recovery | not walked | Connection state and its retry are StoryArcKit's `SourceRegistry`; the rule is StoryArcKit's, tested there, and the Mac calls it unchanged; no Mac walk drives it. |
| Connection state | Retry policy | not walked | the rule is StoryArcKit's, tested there, and the Mac calls it unchanged; no Mac walk drives it. |
| Metadata cache | Opening the library offline | not walked | The metadata cache is StoryArcKit's; the rule is StoryArcKit's, tested there, and the Mac calls it unchanged; no Mac walk drives it. |
| Metadata cache | Refreshing a source | seen | A row's *Refresh* calls `MacSources.refresh(_:)`; no walk asserts what changed. |
| Metadata cache | What a cached catalogue may not hold | not walked | the rule is StoryArcKit's, tested there, and the Mac calls it unchanged; no Mac walk drives it. |
| Metadata cache | A cached catalogue under storage pressure | not walked | the rule is StoryArcKit's, tested there, and the Mac calls it unchanged; no Mac walk drives it. |
| Metadata cache | Publication disappears from a source | not walked | the rule is StoryArcKit's, tested there, and the Mac calls it unchanged; no Mac walk drives it. |
| Metadata cache | A source that answered nothing | not walked | the rule is StoryArcKit's, tested there, and the Mac calls it unchanged; no Mac walk drives it. |
| Metadata cache | Cover caching | pass | `StorageWalkTests` measures and clears the cover cache on its own |
| Source health visibility | Diagnosing a source | seen | The row states its state in grey and, for a share, what its session negotiated (`SourceRowTests`); there is no per-source detail page. |
| Source health visibility | A source the app has read only part of | not walked | No Mac screen states a partial read; StoryArcKit keeps the state. |
| Refresh visibility | A refresh nobody asked for | not walked | No Mac walk watches a background refresh. |
| Refresh visibility | A refresh the user asked for | seen | *Refresh* on a row; no walk asserts the feedback. |
| Refresh visibility | A refresh that finished | not walked | Not asserted on the Mac. |
| Refresh visibility | A refresh that failed | seen | A failed refresh leaves the row grey with its state (`SourceRowTests`). |
| Refresh visibility | A refresh of one source from its own screen | seen | The source window's toolbar carries *Refresh* for that source alone. |
| Refresh visibility | Nothing to say | not walked | Not asserted on the Mac. |

## network-share

Source: `docs/openspec/specs/network-share/spec.md`.

| Requirement | Scenario | Result | Evidence or reason |
| --- | --- | --- | --- |
| SMB connection | Adding a share | pass | `SourcesWalkTests` *A share is reached, states what its session negotiated, and its comics join the library* (SMB 3.1.1 mock, 15 publications); frame `source-share-*.png` |
| SMB connection | Browsing to a subfolder | not walked | The share's comics join the library as a whole; the Mac offers no folder browser for a share. |
| SMB connection | SMB 1 only server | not walked | StoryArcKit's `Smb` refuses SMB 1 by name; no SMB 1 mock exists. |
| SMB connection | Encrypted transport | pass | `SourcesWalkTests` *A share that requires encryption is never read in the clear: encrypted, or refused by name* (the encrypted mock connected encrypted, SMB 3.1.1); `SourceRowTests` for what the row says |
| Disconnect and reconnect | Connection drops while reading | not walked | Not walked on the Mac; the reconnect is StoryArcKit's. |
| Disconnect and reconnect | Device sleeps and wakes | not walked | The Mac was not put to sleep in this session. |
| Disconnect and reconnect | Network changes | not walked | Not walked on the Mac. |
| Disconnect and reconnect | Reconnection fails repeatedly | seen | The row turns grey and offers *Reconnect* (`SourceRowTests`). |
| Streaming reads | Opening a large archive | not walked | Streaming reads are StoryArcKit's; no large archive is opened from a share by a Mac walk. |
| Streaming reads | Metered connection | pass | `MeteredPolicyTests`; `DownloadsWalkTests` *A link turning metered mid-download pauses what the rule holds, and an unmetered one resumes it* |
| Discovery | Discovering hosts | pass | `SourcesWalkTests` *Bonjour discovery runs and either lists shares or stays quiet; the address field is always there* (it found one host on the walk's network) |
| Discovery | Local network permission denied | seen | The sheet keeps the address field whatever discovery finds; `NSLocalNetworkUsageDescription` is in the Info.plist. The permission was not denied in this session. |

## kavita-server

Source: `docs/openspec/specs/kavita-server/spec.md`.

| Requirement | Scenario | Result | Evidence or reason |
| --- | --- | --- | --- |
| Kavita connection | Adding a server | pass | `SourcesWalkTests` *A Kavita server confirms the account, and its series join the library* (14 publications); frame `source-kavita-*.png` |
| Kavita connection | Pasting a full OPDS URL | seen | The sheet says a pasted Kavita OPDS address carries the key; `KavitaConnection` (StoryArcKit) parses it. No Mac walk pastes one. |
| Kavita connection | Session token expires | not walked | the rule is StoryArcKit's, tested there, and the Mac calls it unchanged; no Mac walk drives it. |
| Kavita connection | API key revoked | seen | A refused key leaves the row asking for the sign-in (`SourceRowTests`). |
| Library structure | Browsing a Kavita source | not walked | the source window (`SourceWindow`, from a row's *Browse* in Preferences > Sources) hosts StoryArcKit's `KavitaBrowserView`; the Kavita walk does not open it. |
| Library structure | Series with volumes and loose chapters | not walked | the rule is StoryArcKit's, tested there, and the Mac calls it unchanged; no Mac walk drives it. |
| Library structure | A group Kavita numbers with a sentinel | not walked | the rule is StoryArcKit's, tested there, and the Mac calls it unchanged; no Mac walk drives it. |
| Library structure | Continue point | not walked | the rule is StoryArcKit's, tested there, and the Mac calls it unchanged; no Mac walk drives it. |
| Metadata | Server metadata differs from file metadata | not walked | the rule is StoryArcKit's, tested there, and the Mac calls it unchanged; no Mac walk drives it. |
| Metadata | Keeping a chapter on the device | not walked | Not walked against the Kavita mock on the Mac. |
| Metadata | Reading a downloaded Kavita title offline | not walked | Not walked on the Mac. |
| Server-side collections and reading lists | Viewing server collections | not walked | The *All Shelves* window hosts StoryArcKit's `ShelvesView`, which lists server collections beside local ones; no Mac walk reaches a server shelf. |
| Server-side collections and reading lists | Adding to a server reading list | not walked | As above: `ShelvesView` lists the server's reading lists. |
| Server-side collections and reading lists | Mixing sources in one list | not walked | As above. |
| Progress synchronisation | Progress pushed | not walked | the rule is StoryArcKit's, tested there, and the Mac calls it unchanged; no Mac walk drives it. |
| Progress synchronisation | Progress pulled | not walked | the rule is StoryArcKit's, tested there, and the Mac calls it unchanged; no Mac walk drives it. |
| Progress synchronisation | Marking read state | not walked | The Mac's bulk mark writes the local store only; the push to Kavita is not wired on the Mac. |
| Server-side search | Searching a Kavita source | not walked | the source window (`SourceWindow`, from a row's *Browse* in Preferences > Sources) hosts StoryArcKit's `KavitaBrowserView`, whose search asks the server. |
| Server-side search | Searching from the library, scoped to one server | **fail** | As above. |
| Server-side search | Searching while the server is unreachable | not walked | As above; the browser's unreachable state is StoryArcKit's. |

## opds-catalog

Source: `docs/openspec/specs/opds-catalog/spec.md`.

| Requirement | Scenario | Result | Evidence or reason |
| --- | --- | --- | --- |
| OPDS protocol support | Adding a catalogue | pass | `SourcesWalkTests` *An OPDS catalogue is added, named by its own feed, and its books join the library* (14 publications); frame `source-catalogue-*.png` |
| OPDS protocol support | Version detection fails | not walked | the rule is StoryArcKit's, tested there, and the Mac calls it unchanged; no Mac walk drives it. |
| OPDS protocol support | HTTP authentication | pass | `SourcesWalkTests` *A catalogue behind a sign-in asks for it, and the secret goes to the keychain only* (11 publications) |
| OPDS protocol support | Self-signed certificate | not walked | The pin flow is StoryArcKit's `OpdsTrust`; the mock serves plain HTTP on the loopback, so no walk meets a certificate. |
| Feed navigation | Browsing a navigation feed | seen | `SourcesWalkTests` opens the source window on the mock's acquisition feed and finds an entry by name; no walk follows a navigation feed. |
| Feed navigation | Grouped feed | not walked | the source window (`SourceWindow`, from a row's *Browse* in Preferences > Sources) hosts StoryArcKit's `CatalogueBrowserView`; no walk opens a grouped feed. |
| Feed navigation | Paginated feed | seen | `RemoteEntry.resolve` follows `next` links to find an entry; there is no paged view. |
| Feed navigation | Facets | not walked | As above. |
| Feed navigation | Search | not walked | As above: the catalogue browser carries its own search. |
| Acquisition | Publication detail | seen | A catalogue row has the library's own detail page, with *Download* in its menu. |
| Acquisition | Multiple formats offered | seen | `CatalogueAcquisition.best` (StoryArcKit) picks one; the reader is not offered a choice. |
| Acquisition | No supported format | not walked | Not walked on the Mac. |
| Acquisition | Borrowing and indirect acquisition | not walked | Not walked on the Mac. |

## offline-downloads

Source: `docs/openspec/specs/offline-downloads/spec.md`.

| Requirement | Scenario | Result | Evidence or reason |
| --- | --- | --- | --- |
| Downloading | Downloading one publication | pass | `DownloadsWalkTests` downloads from the OPDS mock to the end, and the download joins the library |
| Downloading | Downloading a collection or reading list | seen | A shelf's menu offers *Download All*, which asks first and states the count; the size is not known before each starts (see the 3.15a note). |
| Downloading | Already downloaded | seen | A finished row offers its own menu and is not fetched again (`DownloadsView`); not walked. |
| Downloading | Reading while downloading | not walked | Not walked on the Mac. |
| Queue management | Queue controls | seen | Pause, resume, cancel and remove in each row's menu (`DownloadsView`); frame `downloads-*.png`. |
| Queue management | Resuming after interruption | pass | `DownloadsWalkTests` *A quit during a download asks, pauses with the partial kept, and the next launch resumes it* |
| Queue management | Background downloads | n/a | A desktop downloads while the app runs only; *No presence when the app is closed* replaces it. |
| Queue management | Failure | seen | A failed row is named and offers a retry (`DownloadsView`); no walk forces a failure. |
| Queue management | Concurrency | not walked | The queue is StoryArcKit's `DownloadQueue`; the rule is StoryArcKit's, tested there, and the Mac calls it unchanged; no Mac walk drives it. |
| Network policy | Wi-Fi only | pass | `MeteredPolicyTests` (the desktop reading is *metered*, `desktop-experience` *Metered connections*) |
| Network policy | Data saver | pass | `MeteredPolicyTests` *A path is metered when the system calls it expensive or constrained* |
| Network policy | Overriding once | pass | `MeteredPolicyTests` *Metered: a download started by hand still runs* |
| Storage management | Storage view | pass | `StorageTests` *Each store shows its own size*; frame `settings-downloads-*.png` |
| Storage management | Storage limit | not walked | The Mac sets no download limit of its own. |
| Storage management | Automatic cleanup | not walked | Not built on the Mac. |
| Storage management | Device storage is low | pass | `StorageTests` *A volume with less than the reserve left is full, said in grey, and offers the cache* |
| Storage management | Backup exclusion | seen | The Downloads tab says downloads are left out of backups (`MacStorage`); not asserted on the file's attribute. |
| Offline integrity | Reading fully offline | not walked | Not walked offline on the Mac. |
| Offline integrity | Verifying a download | not walked | the rule is StoryArcKit's, tested there, and the Mac calls it unchanged; no Mac walk drives it. |

## collections-and-reading-lists

Source: `docs/openspec/specs/collections-and-reading-lists/spec.md`.

| Requirement | Scenario | Result | Evidence or reason |
| --- | --- | --- | --- |
| Collections | Creating a collection | pass | `ShelvesWalkTests` *A collection is made, filled, seen on Home and in the sidebar, and deleted with the books kept* |
| Collections | Adding to a collection | pass | `ShelvesModelTests` *A publication belongs to every collection that holds it*; *Add to Shelf* in a cover's menu (`AddToShelfMenu`) |
| Collections | Cover for a collection | seen | Home's card draws the first member's cover; frame `home-*.png`. |
| Collections | Cover for a collection whose artwork cannot be fetched | seen | An empty shelf or a missing cover draws the well with the shelf's symbol (`ShelfCard`). |
| Collections | Deleting a collection | pass | `ShelvesWalkTests` (the books stay); the confirmation says no publication is deleted |
| Reading lists | Ordering a list | pass | `ShelvesModelTests` *A reading list keeps the reader's order*; `ShelvesWalkTests` *A reading list keeps the order its entries were added in, and moves one by hand* |
| Reading lists | Reading through a list | seen | A list's page opens an entry with a double-click; no next-in-list offer at the end of an entry. |
| Reading lists | Progress through a list | pass | `ShelvesModelTests` *A reading list states how far through it the reader is*; Home's list card says *n of m read* |
| Reading lists | An entry whose read state the source does not report | not walked | Local lists only on the Mac. |
| Reading lists | Cover for a reading list | seen | As for a collection; frame `home-*.png`. |
| Reading lists | Artwork for an entry | seen | A list entry shows its title and read share, without artwork; frame `shelf-list-*.png`. |
| Reading lists | Entry no longer available | pass | `ShelvesModelTests` *An entry whose publication is gone stays in its place, unavailable* |
| Server-backed and local objects | Mixed listing | not walked | The *All Shelves* window's `ShelvesView` lists server and local shelves, each labelled; no Mac walk reaches a server. |
| Server-backed and local objects | Editing while the server is unreachable | pass | `ShelvesModelTests` *An edit made while the server is away is shown, grey, at the end of the list* (the rule; no server list reaches a Mac screen yet) |
| Server-backed and local objects | Conflicting edit | not walked | the rule is StoryArcKit's, tested there, and the Mac calls it unchanged; no Mac walk drives it. |
| Server-backed and local objects | Converting a local list | not walked | The *All Shelves* window's shelf page offers the conversion through `ShelfBulkActions`. |
| Server-backed and local objects | Converting a local list while every server is away | not walked | As above. |
| Bulk actions | Downloading a collection | seen | *Download All* states the count before it queues; the size is not stated, as a catalogue gives none before a download starts. |
| Bulk actions | Marking a list read | pass | `ShelvesModelTests` *A bulk mark changes only what differs, and its undo puts back exactly that*; `ShelvesWalkTests` marks both members read; the undo bar lasts ten seconds (`ShelfBulk`) |
| Shelves on the home surface | Collections are listed | pass | `ShelvesModelTests` *Home lists collections and reading lists as two shelves*; `ShelvesWalkTests` finds the card on Home |
| Shelves on the home surface | Reading lists are a shelf of their own | pass | `ShelvesModelTests`; `ShelvesWalkTests` *A reading list keeps the order*… (Home holds the list) |
| Shelves on the home surface | One kind with nothing in it | pass | `ShelvesModelTests` *…and leaves out a kind with nothing* |
| Shelves on the home surface | No shelves at all | pass | `ShelvesModelTests` (`HomeShelves.isEmpty`); Home draws neither shelf |
| Shelves on the home surface | A shelf with no cover of its own | seen | The well with the shelf's symbol (`ShelfCard`). |
| Shelves on the home surface | A shelf that a server defines | not walked | The *All Shelves* window lists it; the Mac's home surface does not. |
| Shelves on the home surface | The home surface never asks a server for a shelf | pass | Home's shelves are read from the local `Shelves` alone (`MacShelves.home`), asserted by the model tests. |
| Shelves on the home surface | A source is removed | not walked | Local shelves only; a removed source's publications leave their shelves as unavailable entries. |
| Shelves on the home surface | Each shelf leads to the whole of its kind | seen | A card opens its shelf, and the sidebar's Shelves group lists every shelf; Home has no *Show All* per kind. |

## library-sync

Source: `docs/openspec/changes/library-sync/specs/library-sync/spec.md`.

| Requirement | Scenario | Result | Evidence or reason |
| --- | --- | --- | --- |
| The sync document lives where the reader chose | Choosing where it lives | seen | Preferences > Sources > *Choose a Place to Sync*; frame `settings-sources-*.png`. |
| The sync document lives where the reader chose | A folder that is really a cloud drive | not walked | the rule is StoryArcKit's, tested there, and the Mac calls it unchanged; no Mac walk drives it. |
| The sync document lives where the reader chose | Sync is off until it is turned on | pass | `SyncTests` *With sync off, start settles at once and quit writes nothing* |
| The sync document lives where the reader chose | The place is unreachable | pass | `SyncTests` *An unreachable place is grey, and the start still settles* |
| When a sync happens | The reader opens the app | pass | `SyncTests` *At start the sync runs beside the window, which is never kept waiting* |
| When a sync happens | The reader closes a publication | not walked | The Mac syncs at start and quit (`desktop-experience`); closing a reader window does not sync. |
| When a sync happens | In the background, as far as each platform allows | n/a | *No presence when the app is closed*: nothing runs after the quit. |
| Two devices that both moved | A position on two devices | not walked | The merge is StoryArcKit's `LibraryTransfer`; the rule is StoryArcKit's, tested there, and the Mac calls it unchanged; no Mac walk drives it. |
| Two devices that both moved | The watermark that decides it | not walked | the rule is StoryArcKit's, tested there, and the Mac calls it unchanged; no Mac walk drives it. |
| Two devices that both moved | A shelf changed on both sides | not walked | the rule is StoryArcKit's, tested there, and the Mac calls it unchanged; no Mac walk drives it. |
| Two devices that both moved | A deletion is not a disagreement | not walked | the rule is StoryArcKit's, tested there, and the Mac calls it unchanged; no Mac walk drives it; the Mac's delete goes through `ShelvesStore`, which stamps the tombstone. |
| Two devices that both moved | Two devices write at once | not walked | the rule is StoryArcKit's, tested there, and the Mac calls it unchanged; no Mac walk drives it. |
| Kavita keeps what Kavita owns | A Kavita publication's position | not walked | the rule is StoryArcKit's, tested there, and the Mac calls it unchanged; no Mac walk drives it. |
| Kavita keeps what Kavita owns | Everything Kavita cannot hold | not walked | the rule is StoryArcKit's, tested there, and the Mac calls it unchanged; no Mac walk drives it. |

## reading-progress (library-sync delta)

Source: `docs/openspec/changes/library-sync/specs/reading-progress/spec.md`.

| Requirement | Scenario | Result | Evidence or reason |
| --- | --- | --- | --- |
| Conflict resolution | The last-synchronised position is recorded | not walked | the rule is StoryArcKit's, tested there, and the Mac calls it unchanged; no Mac walk drives it. |
| Conflict resolution | A device that has never synchronised | not walked | the rule is StoryArcKit's, tested there, and the Mac calls it unchanged; no Mac walk drives it. |
| Conflict resolution | Remote is further ahead | not walked | the rule is StoryArcKit's, tested there, and the Mac calls it unchanged; no Mac walk drives it. |
| Conflict resolution | Both changed since the last sync | not walked | the rule is StoryArcKit's, tested there, and the Mac calls it unchanged; no Mac walk drives it. |
| Conflict resolution | Remote is behind | not walked | the rule is StoryArcKit's, tested there, and the Mac calls it unchanged; no Mac walk drives it. |
| Conflict resolution | Conflicting finished state | not walked | the rule is StoryArcKit's, tested there, and the Mac calls it unchanged; no Mac walk drives it. |

## library-portability

Source: `docs/openspec/changes/library-portability/specs/library-portability/spec.md`.

| Requirement | Scenario | Result | Evidence or reason |
| --- | --- | --- | --- |
| One versioned document | What the document declares | later | No export or import screen on the Mac in wave 3; `library-portability` is an open change, and the Mac carries none of it yet. |
| One versioned document | An older document is migrated forward | later | No export or import screen on the Mac in wave 3; `library-portability` is an open change, and the Mac carries none of it yet. |
| One versioned document | A newer document is refused, by name | later | No export or import screen on the Mac in wave 3; `library-portability` is an open change, and the Mac carries none of it yet. |
| One versioned document | A field this version does not know | later | No export or import screen on the Mac in wave 3; `library-portability` is an open change, and the Mac carries none of it yet. |
| One versioned document | A record this version cannot read | later | No export or import screen on the Mac in wave 3; `library-portability` is an open change, and the Mac carries none of it yet. |
| One versioned document | A document that is too large | later | No export or import screen on the Mac in wave 3; `library-portability` is an open change, and the Mac carries none of it yet. |
| What an export carries | The library's shape | later | No export or import screen on the Mac in wave 3; `library-portability` is an open change, and the Mac carries none of it yet. |
| What an export carries | What it does not carry | later | No export or import screen on the Mac in wave 3; `library-portability` is an open change, and the Mac carries none of it yet. |
| What an export carries | The two platforms write one shape | later | No export or import screen on the Mac in wave 3; `library-portability` is an open change, and the Mac carries none of it yet. |
| What an export carries | A chosen cover travels | later | No export or import screen on the Mac in wave 3; `library-portability` is an open change, and the Mac carries none of it yet. |
| Secrets travel only sealed, and only when asked | A server in the export | later | No export or import screen on the Mac in wave 3; `library-portability` is an open change, and the Mac carries none of it yet. |
| Secrets travel only sealed, and only when asked | Carrying secrets under a passphrase | later | No export or import screen on the Mac in wave 3; `library-portability` is an open change, and the Mac carries none of it yet. |
| Secrets travel only sealed, and only when asked | Importing sealed secrets | later | No export or import screen on the Mac in wave 3; `library-portability` is an open change, and the Mac carries none of it yet. |
| Secrets travel only sealed, and only when asked | A wrong or missing passphrase | later | No export or import screen on the Mac in wave 3; `library-portability` is an open change, and the Mac carries none of it yet. |
| Secrets travel only sealed, and only when asked | One document, both platforms | later | No export or import screen on the Mac in wave 3; `library-portability` is an open change, and the Mac carries none of it yet. |
| Secrets travel only sealed, and only when asked | Signing in again after an import | later | No export or import screen on the Mac in wave 3; `library-portability` is an open change, and the Mac carries none of it yet. |
| Secrets travel only sealed, and only when asked | A certificate pin | later | No export or import screen on the Mac in wave 3; `library-portability` is an open change, and the Mac carries none of it yet. |
| Import merges | Reading progress on both sides | later | No export or import screen on the Mac in wave 3; `library-portability` is an open change, and the Mac carries none of it yet. |
| Import merges | A device that never synced | later | No export or import screen on the Mac in wave 3; `library-portability` is an open change, and the Mac carries none of it yet. |
| Import merges | A collection that exists on both sides | later | No export or import screen on the Mac in wave 3; `library-portability` is an open change, and the Mac carries none of it yet. |
| Import merges | The reader sees what will happen first | later | No export or import screen on the Mac in wave 3; `library-portability` is an open change, and the Mac carries none of it yet. |

## sources (library-portability delta)

Source: `docs/openspec/changes/library-portability/specs/sources/spec.md`.

| Requirement | Scenario | Result | Evidence or reason |
| --- | --- | --- | --- |
| Credential storage | Storing a secret | pass | `SourcesWalkTests`; `MacCredentialStoreTests` |
| Credential storage | Secret appears in a diagnostic | pass | `DiagnosticExportTests` *Every credential, token and host is redacted, as on a phone* |
| Credential storage | Reading a secret | pass | `MacCredentialStoreTests` |
| Credential storage | A library export without secrets | later | No export on the Mac yet. |
| Credential storage | A library export that carries secrets | later | No export on the Mac yet. |

## desktop-experience

Source: `docs/openspec/changes/desktop-clients/specs/desktop-experience/spec.md`. The requirements wave 3 names: *Exporting a diagnostic to a file*, *Finding and reaching a network share*, *Metered connections*, *No presence when the app is closed*, *Secrets in the system's own store*, *Storage on a desktop*, *Sync when the app runs*.

| Requirement | Scenario | Result | Evidence or reason |
| --- | --- | --- | --- |
| No presence when the app is closed | After quitting | pass | `DownloadsQuitTests` *Nothing transferring: the quit asks nothing and pauses nothing* |
| No presence when the app is closed | A download in progress | pass | `DownloadsQuitTests` *A transfer, and the reader agrees: it pauses for the next launch, then the app quits*; `DownloadsWalkTests` relaunch resumes it |
| No presence when the app is closed | A finished download or a refresh | seen | A finished download joins the library with no notification (`LibraryWindow`); not asserted. |
| Secrets in the system's own store | Saving a password | pass | `SourcesWalkTests`; `MacCredentialStoreTests` (login keychain, per the measured spike) |
| Secrets in the system's own store | A secure store that is not running | n/a | The Mac's keychain is always there; the scenario is Linux's. |
| Secrets in the system's own store | A secret the store refuses | not walked | The keychain did not refuse a write in this session. |
| Secrets in the system's own store | Searching the app's files | pass | `MacCredentialStoreTests` *No file in the app's container holds a saved secret, in any encoding* |
| Metered connections | A metered network | pass | `MeteredPolicyTests` *Metered, with the rule on: queued and running downloads are held, and the queue says why* |
| Metered connections | A network that is not metered | pass | `MeteredPolicyTests` *Unmetered and unknown: nothing is held* |
| Metered connections | A network that changes mid-download | pass | `MeteredPolicyTests` *A change to metered mid-download pauses it*; `DownloadsWalkTests` |
| Metered connections | No connection | pass | `MeteredPolicyTests` *No connection holds nothing and says the queue waits, in grey* |
| Exporting a diagnostic to a file | Saving the diagnostic | pass | `DiagnosticExportTests` *Saving writes the export, whole, where the reader chose*; frame `diagnostic-*.png` |
| Exporting a diagnostic to a file | A place the file cannot be written | pass | `DiagnosticExportTests` *A place that cannot be written is named* |
| Exporting a diagnostic to a file | Cancelling | pass | `DiagnosticExportTests` *A cancel writes nothing, and nothing of the export is kept* |
| Finding and reaching a network share | Discovery that the system offers | pass | `SourcesWalkTests` (Bonjour) |
| Finding and reaching a network share | Discovery the system does not offer | n/a | The Mac offers Bonjour; the scenario is for a system that does not. |
| Finding and reaching a network share | An old protocol | not walked | No SMB 1 mock; StoryArcKit refuses SMB 1 by name. |
| Finding and reaching a network share | Encryption | pass | `SourcesWalkTests` *A share that requires encryption is never read in the clear*; `SourceRowTests` |
| Finding and reaching a network share | A server that cannot be reached | pass | `SourceRowTests` *An unreachable source is grey and keeps its place* |
| Finding and reaching a network share | A laptop that sleeps | not walked | The Mac was not put to sleep in this session. |
| Storage on a desktop | Where the data lives | seen | The Downloads tab says everything stays in StoryArc's own folder and downloads are left out of backups; frame `settings-downloads-*.png`. |
| Storage on a desktop | A full disk | pass | `StorageTests` *A write that failed for want of room is named as a full disk* |
| Storage on a desktop | Removing the app | seen | The Downloads tab offers to remove everything before the app is removed (`StorageSection`). |
| Sync when the app runs | At start | pass | `SyncTests` *At start the sync runs beside the window*; *At start, what the sync brought is reloaded once it lands* |
| Sync when the app runs | At quit | pass | `SyncTests` *At quit, a changed position is written once more, and a slow place gives up within five seconds* (gave up after 5.05 s); *A real share takes the sync document* |
| Sync when the app runs | Offline | pass | `SyncTests` *An unreachable place is grey, and the start still settles* |
