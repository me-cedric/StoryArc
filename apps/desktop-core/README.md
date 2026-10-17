# desktop-core

The Rust core Windows and Linux share ([ADR-0018](../../docs/decisions/0018-desktop-clients.md),
`desktop-clients` design.md, Decision 5). **No UI, ever.** The Linux app calls
`storyarc-core` directly; the Windows app calls the C ABI of `storyarc-ffi`.

| Crate | Holds |
| --- | --- |
| `storyarc-core` | Formats, page decoding, sources, the local store, library queries, locale |
| `storyarc-ffi` | The C ABI over `storyarc_core::library`, its header and the generated C# |
| `pdfium/` | The PDFium pin (lane P); `pnpm pdfium:fetch` downloads the pinned library into `.build/pdfium/` |

## storyarc-core modules

| Module | What it does |
| --- | --- |
| `epub` | `WebPublication`: the Readium Web Publication Manifest and the positions list the desktop EPUB bundle takes, and each resource by container path (task 4.3) |
| `pdf` | `PdfEngine` and `PdfDocument`: PDFium on one thread over a `RandomAccessSource`, pages to RGBA, text, search, the outline (task 4.4) |
| `downloads` | The download policy (metered, offline, storage limit, concurrency), one resumable transfer into a partial file, the queue as a value, and the downloads folder with the integrity check |
| `domain` | Records and rules mirrored from StoryArcKit: publications, identity, progress and the ADR-0006 merge, adjustments, border crop, spreads, natural order |
| `formats` | ZIP, TAR and RAR comic archives, EPUB metadata, page ordering, `ComicInfo.xml`, codec sniffing |
| `image` | Page decoding to RGBA (`decode`) and the reader's adjustments (`adjust`) |
| `io` | `RandomAccessSource`, file and memory sources, `CancelToken` |
| `library` | **The public API the apps call** (`facade`) and the shelf queries (`query`) |
| `locale` | ICU4X collation, the search fold, number and date formatting |
| `metered` | The metered flag: a provider trait, `NetworkCostType` on Windows, the network-monitor portal then NetworkManager on Linux, a fake for tests, and the watch that turns readings into changes |
| `net` | HTTP over reqwest and rustls: credentials only to the configured origin, no `https` to `http` step, redirects by hand, the system's trust then the reader's pins (`net::trust`) |
| `paths` | Per-user storage folders per system, the Flatpak and MSIX redirects |
| `diagnostics` | The diagnostic export's text and the phones' five redaction rules, plus every held secret removed |
| `portability` | The library document both phones write: decode with the version rules, encode with secrets out of every address, sealed secrets, the merge, and the sync document in a place the reader chose |
| `runtime` | The one tokio runtime the network sources run on, behind a blocking `Runtime` handle |
| `secrets` | `Secret`, the in-memory type every credential travels in: no `Display`, a masked `Debug` |
| `secure_store` | `SecretStore`, `Vault`, Credential Manager on Windows, Secret Service through `oo7` on Linux, the session-only fallback |
| `shelves` | Collections and reading lists as values, the offline edit queue for server shelves with its five-row merge, pins, and the server shelves remembered for the home surface |
| `sources` | Folder scanning, reconciliation and watching; SMB shares (`sources::smb`); OPDS catalogues (`sources::opds`); Kavita servers and the progress exchange (`sources::kavita`); source health and refresh (`sources::health`); the metadata cache (`sources::cache`) |
| `store` | The SQLite store: progress, sources, publications |

## Public Rust API (`storyarc_core::library`)

| Call | Does |
| --- | --- |
| `FolderSource::open(root, &CancelToken)` | Scans a folder into publications |
| `FolderSource::rescan(&CancelToken)` | Rescans, opening only changed files |
| `FolderSource::publications()` / `skipped()` / `unreadable_folders()` / `was_cancelled()` | What the scan found |
| `FolderSource::records_json()` | The publications as a UTF-8 JSON array |
| `OpenPublication::open(path)` | Opens a CBZ, CBR, CBT or image folder |
| `OpenPublication::publication()` / `metadata_json()` / `page_count()` / `declared_spreads()` | Its record and pages |
| `OpenPublication::page_bytes(i)` / `page_size(i)` / `decode_page(i, max)` | One page, raw, sized or as RGBA |
| `ProgressStore::open(path)` / `in_memory()` | The progress store |
| `ProgressStore::read(&identity)` / `write(&record)` / `recent(limit)` | The reader's place |
| `LibraryIndex::arrange(...)` | Search, filters and sort under a `Collation` |
| `LibraryIndex::continue_reading(...)` / `up_next(...)` / `next(...)` / `previous(...)` | Home shelves and series navigation |

Every failure is a `LibraryError` case. Every call is synchronous; call it off the interface
thread.

### Network sources

The host creates one `runtime::Runtime` at start and hands it to every network source. The
calls below block on it, so they are made from a worker thread and never from inside the
runtime.

| Call | Does |
| --- | --- |
| `SmbAddress::parse(text)` / `SmbAddress::new(host, share).with_port(p).with_folder(f)` | Where a share is |
| `SmbShare::check(&runtime, address, login)` | Validates before saving; the four named failures and the SMB 1 refusal are `SmbError` cases |
| `SmbShare::connect(...)` then `identity()` | The negotiated dialect and whether the session is encrypted |
| `SmbShare::list(path)` | One folder, folders first, natural order |
| `SmbShare::open(path)` | An `SmbFile`, a `RandomAccessSource` that reconnects once on a failed read |
| `SmbFile::status()` / `health()` | The two-second indicator and the sixty-second download offer |
| `SmbFile::drop_session()` | Called on a wake or a network change; the next read opens a new session |

| `HttpClient::new(&runtime, trust)` | The HTTP client every catalogue, server and download shares |
| `OpdsCatalogue::new(&http, root, credential)` then `validate()` | The root feed, for the add sheet's title and dialect confirmation |
| `OpdsCatalogue::feed(&url)` / `search(&feed, terms)` / `bytes(&url)` | A page in either dialect; a server search or `LocalOnly`; a cover or a file |
| `OpdsError::Unauthorized(challenge)` / `Untrusted(certificate)` | Prompt for Basic or Bearer; show the fingerprint, then `TrustStore::pin` and retry |
| `OpdsEntry::best_acquisition()` / `unreadable_formats()` / `unsupported_kinds()` | EPUB, then comics, then PDF; what to name when nothing opens |
| `KavitaClient::new(&http, KavitaAddress::parse(typed, key))` then `connect()` | Signs in with the API key; a refused key is `KavitaError::KeyRejected` |
| `libraries()` / `series(library)` / `volumes(series)` / `continue_point(series)` | The server's shelves, with `pages` and `pagesRead` per chapter |
| `ProgressPull::merging(remote, local)` then `KavitaExchange::of(&pull, &chapters)` | ADR-0006's merge sorted into records to save and positions owed |
| `KavitaClient::push(&owed, library, series, volume)` | A page, or a mark for a finished record; write `owed.settled` only when it succeeds |
| `chapter_request(id)` | The download request, signed for the server alone |

### Downloads

| Call | Does |
| --- | --- |
| `DownloadQueue::load(path)` / `save(path)` | The queue, saved atomically; a row running at a kill comes back `Queued` |
| `queueing` / `pausing` / `resuming` / `moving` / `removing` / `pausing_all` / `resuming_all` | The reader's controls, each returning a new queue |
| `holding(network, &policy, used)` then `startable(network, &policy)` | Pauses what the policy holds back, running rows included, releases what it no longer holds, and names what may start |
| `failing(id, reason, retryable)` / `should_retry(row)` / `backoff(attempts)` | Three attempts, doubling from two seconds |
| `failing_verification(id, reason)` | Bytes that are not a publication: re-queued once, then failed |
| `DownloadFolder::new(root).fetch(&http, id, title, request, hint, &cancel, progress)` | Transfers, resuming a partial file with `Range` and `If-Range`, verifies by indexing, and lands the file; `Landed::resumption` says fresh, resumed or restarted |
| `located(id)` / `remove(id)` / `bytes_on_disk()` | The finished file, its removal, and the storage view's number |

### Shelves, health and the metadata cache

| Call | Does |
| --- | --- |
| `Shelves::adding_collection` / `adding_members` / `removing_members` / `setting_collection_cover` / `renaming_collection` / `deleting_collection` | Collections; a removed cover member clears the choice |
| `Shelves::adding_list` / `appending` / `moving_entry` / `removing_entry` / `setting_list_cover` | Reading lists in the reader's order |
| `ReadingList::next` / `next_available` / `progress(reading)` | The next entry in list order; the count of finished entries over those the source reports |
| `cover_members(chosen, ordered, has_cover)` | The chosen cover, else the first four available, else the placeholder |
| `ShelfEditQueue::queueing` / `recording` / `noting` / `acknowledging` then `ShelfPull::merging(&remote, &queue)` | Offline edits, baselines and the one-time conflict notice; push, settle or discard |
| `edits::projecting(&remote, &pending)` | The list with pending entries shown after the server's own |
| `PinnedShelves::of_tokens` / `tokens` / `ordering` and `RememberedShelf::stored` / `of_stored` | The pins the library document carries, and the server shelves home draws without asking |
| `SourceHealth::refreshing` / `refreshed(now)` / `failed(&failure, now)` / `actions(..)` | Grey since a moment, never red; reconnect first only when a credential was refused |
| `MetadataCache::write(id, &value, now)` / `read(id)` / `clear(id)` / `bytes()` | What a source listed when it last answered |

### The metered flag

| Call | Does |
| --- | --- |
| `metered::system_provider(&runtime)` | The system's provider; elsewhere `Undescribed`, which says unmetered |
| `MeteredProvider::network()` | `Unmetered`, `Metered` or `Offline`; a connection the system does not describe is unmetered, and the data saver is metered |
| `NetworkWatch::new(&provider)` then `poll(&provider)` | The new state when it changed, for `DownloadQueue::holding` |
| `FakeMetered::new(state)` / `set(state)` | A provider a test sets by hand |

The Windows provider compiles only on Windows and the Linux one only on Linux; neither runs on
the Mac host, so their manual check is a phone tether on each system.

### Library portability and sync

| Call | Does |
| --- | --- |
| `portability::decode(bytes)` / `encode(&document)` | One versioned document; over 64 MiB or a newer format is a `DocumentFailure` by name; an unreadable progress record is dropped alone |
| `exportable_address(locator)` | The address with its password and any secret query or fragment item removed |
| `sealing::seal(&secrets, &passphrase)` / `open(&sealed, &passphrase)` | PBKDF2-HMAC-SHA256 at 600,000 rounds over the NFC passphrase, AES-256-GCM per secret |
| `LibrarySnapshot::document(app_version, now, device, for_sync)` | What this device writes; a sync document leaves Kavita's positions to Kavita |
| `merging(&document, &snapshot, device)` | The import and sync merge: furthest position, shelf members united, deletions as tombstones, settings by last writer, sources, pins and covers added |
| `LibrarySync::new(FolderPlace::new(dir), device, version).sync(&snapshot, now)` | Read, merge, write only over the version read, retry on a lost race, fold in a provider's conflicted copies; `Err(Unreachable)` is grey |

### Secrets and the diagnostic

| Call | Does |
| --- | --- |
| `secrets::system_store(&runtime)` | Credential Manager on Windows, Secret Service or the portal keyring on Linux, else the session-only store |
| `Vault::new(store)` then `save(&key, secret)` | `Stored`, or `SessionOnly { notice }` with the grey line's text the first time only; a refusal keeps no copy |
| `Vault::load(&key)` / `delete(&key)` | The secret, from the session first; removal everywhere |
| `SecretKey::for_source(id, field)` | The reference: a source's record holds only its id |
| `DiagnosticReport::new(title).section(name, lines).render(&[&secret])` | The export's text, every held secret and every hostname redacted |

The Windows and Linux backends compile only on their own systems. The Mac host runs the
in-memory and session-only stores; the Ubuntu container compiles the Linux one and, having no
Secret Service, takes the session-only path; the `desktop-windows` workflow is the first to
compile the Windows one. `paths::StorageLocations::current()` gives the store file and cache folders, and
`image::adjusted` applies an `ImageAdjustments` to a decoded page.

## The C seam (`storyarc-ffi`)

Sixty-three exports, declared in `storyarc-ffi/include/storyarc_ffi.h` and written into
`storyarc-ffi/generated/NativeMethods.g.cs` by `build.rs` with csbindgen, which reads
`src/lib.rs`, `src/network.rs`, `src/data.rs` and `src/reading.rs`. Opaque tagged handles,
Rust-owned buffers freed by `storyarc_buffer_free`, records and requests as UTF-8 JSON, integer
codes 0 to 9 with `storyarc_last_error`, cancel tokens. A test reads the exports from the four
files and fails when the header or the generated file misses one.

Wave 3 adds twenty-eight. The network, in `src/network.rs`: the runtime, the HTTP client and
its certificate pins, SMB (`connect`, `identity`, `list`, `free`), an OPDS page or search, one
Kavita call, the network state, and a download with a progress callback. The reader's data, in
`src/data.rs`: the vault (`open`, `save`, `load`, `delete`, `free`), the download queue's rules
and the shelves as value-plus-operations, the shelf edit pull, library import, export and
sync, sealed secrets, the diagnostic's text and a folder's size. Codes 8 (`UNREACHABLE`, grey)
and 9 (`UNAUTHORIZED`) are new; the C# `StoryArcStatus` enum gains them in lane W.

Wave 4 adds fifteen, in `src/reading.rs`. The EPUB (`storyarc_epub_open`, `manifest`,
`positions`, `resource`, `free`): the manifest and positions the bundle takes, and each
resource with its media type for the scheme handler. PDF (`storyarc_pdf_engine_start`, `open`,
`page_count`, `page_size`, `render_page`, `page_text`, `has_text_layer`, `search`, `outline`,
`free`): the engine binds once per process to the library in the folder the app names.

## Features

| Feature | Default | Does |
| --- | --- | --- |
| `heic` | on | HEIC pages through `zune-heic` (pure Rust) |
| `avif` | off | AVIF pages through dav1d; needs the libdav1d system library |

Without its feature, a page in that codec is refused by name.

## Tests

```bash
pnpm test:desktop:core   # cargo test -p storyarc-core -p storyarc-ffi
pnpm lint:desktop        # cargo fmt --check and clippy with warnings denied
cargo test -p storyarc-core --features avif   # with Homebrew's or the distro's dav1d
apps/desktop-linux/scripts/container-build.sh ubuntu-24.04
```

The corpus is `packages/test-fixtures`; `storyarc-core/tests/images` holds one small page in
each decoded format.

`tests/pdf.rs` and the PDF cases of `storyarc-ffi/tests/wave4.rs` bind to the pinned PDFium
library at run time: `pnpm pdfium:fetch` puts it under `.build/pdfium/<platform>/` after
checking its digest against `pdfium/pin.json`, or `STORYARC_PDFIUM_DIR` names a folder. Without
it each case skips with a line on stderr.

`tests/opds.rs` runs StoryArcKit's OPDS parsing expectations, then the `pnpm opds` fixture
(`STORYARC_OPDS_URL`, default port 4444) when it answers, and brings its own servers for the
origin, downgrade and pinned-certificate cases.

`tests/kavita.rs` runs StoryArcKit's Kavita exchange cases, then `pnpm kavita` at
`STORYARC_KAVITA_URL` (default port 5000, which on a Mac is the AirPlay receiver's, so set it).

`tests/smb.rs` runs against the Samba fixture (`pnpm smb`) and skips each case whose port does
not answer. `STORYARC_SMB_PORT`, `STORYARC_SMB_ENCRYPTED_PORT`, `STORYARC_SMB1_PORT` and
`STORYARC_SMB_USER` point it at another server; `docs/delivery/desktop-spike-smb.md` runs the
same `smb.conf` in Docker.
