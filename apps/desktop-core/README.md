# desktop-core

The Rust core Windows and Linux share ([ADR-0018](../../docs/decisions/0018-desktop-clients.md),
`desktop-clients` design.md, Decision 5). **No UI, ever.** The Linux app calls
`storyarc-core` directly; the Windows app calls the C ABI of `storyarc-ffi`.

| Crate | Holds |
| --- | --- |
| `storyarc-core` | Formats, page decoding, sources, the local store, library queries, locale |
| `storyarc-ffi` | The C ABI over `storyarc_core::library`, its header and the generated C# |
| `pdfium/` | The PDFium pin (lane P) |

## storyarc-core modules

| Module | What it does |
| --- | --- |
| `domain` | Records and rules mirrored from StoryArcKit: publications, identity, progress and the ADR-0006 merge, adjustments, border crop, spreads, natural order |
| `formats` | ZIP, TAR and RAR comic archives, EPUB metadata, page ordering, `ComicInfo.xml`, codec sniffing |
| `image` | Page decoding to RGBA (`decode`) and the reader's adjustments (`adjust`) |
| `io` | `RandomAccessSource`, file and memory sources, `CancelToken` |
| `library` | **The public API the apps call** (`facade`) and the shelf queries (`query`) |
| `locale` | ICU4X collation, the search fold, number and date formatting |
| `paths` | Per-user storage folders per system, the Flatpak and MSIX redirects |
| `runtime` | The one tokio runtime the network sources run on, behind a blocking `Runtime` handle |
| `secrets` | `Secret`, the in-memory type every credential travels in: no `Display`, a masked `Debug` |
| `sources` | Folder scanning, reconciliation and watching; SMB shares (`sources::smb`) |
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
| `SmbFile::drop_session()` | Called on a wake or a network change; the next read opens a new session | `paths::StorageLocations::current()` gives the store file and cache folders, and
`image::adjusted` applies an `ImageAdjustments` to a decoded page.

## The C seam (`storyarc-ffi`)

Twenty exports, declared in `storyarc-ffi/include/storyarc_ffi.h` and written into
`storyarc-ffi/generated/NativeMethods.g.cs` by `build.rs` with csbindgen. Opaque tagged
handles, Rust-owned buffers freed by `storyarc_buffer_free`, records as UTF-8 JSON, integer
codes with `storyarc_last_error`, cancel tokens. A test reads the exports from the source and
fails when the header or the generated file misses one.

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

`tests/smb.rs` runs against the Samba fixture (`pnpm smb`) and skips each case whose port does
not answer. `STORYARC_SMB_PORT`, `STORYARC_SMB_ENCRYPTED_PORT`, `STORYARC_SMB1_PORT` and
`STORYARC_SMB_USER` point it at another server; `docs/delivery/desktop-spike-smb.md` runs the
same `smb.conf` in Docker.
