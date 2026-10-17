#ifndef STORYARC_FFI_H
#define STORYARC_FFI_H

#include <stddef.h>
#include <stdint.h>

#ifdef __cplusplus
extern "C" {
#endif

/* The seam's rules (design.md, Decision 5): opaque handles, byte buffers Rust owns and
 * storyarc_buffer_free releases, integer status codes with storyarc_last_error for the
 * message, and storyarc_cancel on a token for cancellation. The Rust side is
 * apps/desktop-core/storyarc-ffi/src/lib.rs; the C# side, generated/NativeMethods.g.cs, is
 * written from it by csbindgen. Keep the three in step. */

/* Status codes. Every failing call also leaves a message for storyarc_last_error. */
#define STORYARC_OK 0
/* A pointer, length, handle or index the call cannot work with. */
#define STORYARC_ERROR_INVALID_ARGUMENT 1
/* The call was abandoned because its cancel token fired. */
#define STORYARC_ERROR_CANCELLED 2
/* Nothing at the path the call was given. */
#define STORYARC_ERROR_NOT_FOUND 3
/* A format or codec this build refuses; the message names it for the reader. */
#define STORYARC_ERROR_UNSUPPORTED 4
/* A publication or page in a supported format that is damaged, locked or too large. */
#define STORYARC_ERROR_UNREADABLE 5
/* The local store refused, or the disk is full. */
#define STORYARC_ERROR_STORAGE 6
/* The core failed in a way it has no case for: a defect, reported rather than a crash. */
#define STORYARC_ERROR_INTERNAL 7
/* The source, server or sync place did not answer: grey, never red. */
#define STORYARC_ERROR_UNREACHABLE 8
/* A credential, key or passphrase was refused, or a certificate is not trusted; the message
 * names the challenge or the fingerprint. */
#define STORYARC_ERROR_UNAUTHORIZED 9

/* Bytes Rust owns. Read `len` bytes at `data`, then hand the whole struct to
 * storyarc_buffer_free exactly once. `data` is NULL when `len` is zero. */
typedef struct StoryArcBuffer {
    uint8_t *data;
    size_t len;
    size_t capacity;
} StoryArcBuffer;

/* Returns the storyarc-core version as a static NUL-terminated UTF-8 string.
 * The caller must never free it. The pointer stays valid for the process lifetime. */
const char *storyarc_core_version(void);

/* Copies `len` bytes at `data` into a buffer Rust owns and writes it to `out`.
 * Returns STORYARC_OK, or STORYARC_ERROR_INVALID_ARGUMENT when `out` is NULL or `data` is
 * NULL with a non-zero `len`. */
int32_t storyarc_buffer_roundtrip(const uint8_t *data, size_t len, StoryArcBuffer *out);

/* Releases a buffer a call of this library returned. A zeroed struct is safe to free. */
void storyarc_buffer_free(StoryArcBuffer buffer);

/* The message of the most recent failing call on the calling thread, NUL-terminated UTF-8,
 * or NULL when no call on this thread has failed. Valid until the next failing call on the
 * same thread. The caller never frees it. */
const char *storyarc_last_error(void);

/* A new cancel token, not yet cancelled. Free it with storyarc_cancel_token_free. */
void *storyarc_cancel_token_new(void);

/* Raises the token. Every read behind it stops with STORYARC_ERROR_CANCELLED. NULL is
 * ignored; cancelling twice is harmless. */
void storyarc_cancel(void *token);

/* 1 when the token has been raised, 0 when it has not or is NULL. */
int32_t storyarc_cancel_token_is_cancelled(const void *token);

/* Frees a token. NULL is ignored. */
void storyarc_cancel_token_free(void *token);

/* Handles. Three opaque kinds, each released once by its own _free; releasing NULL is a
 * no-op, and a handle of the wrong kind is refused with STORYARC_ERROR_INVALID_ARGUMENT. A
 * handle is used by one thread at a time. Paths and JSON arrive as UTF-8 bytes with a
 * length, never NUL-terminated. Records leave as UTF-8 JSON in a StoryArcBuffer, in the
 * camelCase shape of the phones' library documents. */

/* Scans the folder at `path` and writes a folder handle to `out_folder`. `cancel` may be
 * NULL; when it fires the call returns STORYARC_ERROR_CANCELLED and no handle. A missing
 * folder is STORYARC_ERROR_NOT_FOUND. */
int32_t storyarc_folder_open(const uint8_t *path, size_t path_len, const void *cancel,
                             void **out_folder);

/* Writes the folder's publications to `out` as a UTF-8 JSON array of publication records. */
int32_t storyarc_folder_records(const void *folder, StoryArcBuffer *out);

/* Releases a folder handle. */
void storyarc_folder_free(void *folder);

/* Opens a CBZ, CBR, CBT or folder of images at `path` and writes a publication handle to
 * `out_publication`. A refused format is STORYARC_ERROR_UNSUPPORTED, named in the message. */
int32_t storyarc_publication_open(const uint8_t *path, size_t path_len,
                                  void **out_publication);

/* Writes the number of pages, in reading order, to `out_count`. */
int32_t storyarc_publication_page_count(const void *publication, uint32_t *out_count);

/* Writes the publication's record to `out` as a UTF-8 JSON object. */
int32_t storyarc_publication_metadata(const void *publication, StoryArcBuffer *out);

/* Decodes page `index` to 8-bit RGBA, not premultiplied, rows top to bottom with no
 * padding, at most `max_pixel_size` on its longest edge (0 for the page's own size). Writes
 * width * height * 4 bytes to `out_pixels` and the size to `out_width` and `out_height`;
 * on failure all three are zeroed. An index past the end is
 * STORYARC_ERROR_INVALID_ARGUMENT, a refused codec STORYARC_ERROR_UNSUPPORTED and a damaged
 * page STORYARC_ERROR_UNREADABLE, with the codec named in the message. */
int32_t storyarc_publication_decode_page(const void *publication, uint32_t index,
                                         uint32_t max_pixel_size, StoryArcBuffer *out_pixels,
                                         uint32_t *out_width, uint32_t *out_height);

/* Releases a publication handle. */
void storyarc_publication_free(void *publication);

/* Opens or creates the progress store at `path` and writes a store handle to `out_store`. */
int32_t storyarc_store_open(const uint8_t *path, size_t path_len, void **out_store);

/* Reads the record of the publication whose identity is the JSON object at `identity_json`
 * (serverSourceId, serverRemoteId, contentDigest, normalizedPath, any of them). Writes the
 * record to `out` as JSON, or `null` when there is none. */
int32_t storyarc_progress_read(const void *store, const uint8_t *identity_json,
                               size_t identity_len, StoryArcBuffer *out);

/* Records the JSON progress record at `record_json`. Finished stays finished. A record that
 * is not one is STORYARC_ERROR_INVALID_ARGUMENT; a full disk STORYARC_ERROR_STORAGE. */
int32_t storyarc_progress_write(const void *store, const uint8_t *record_json,
                                size_t record_len);

/* Releases a store handle. */
void storyarc_store_free(void *store);

/* ---- Wave 3: the network (src/network.rs). Requests are UTF-8 JSON with a length. ------ */

/* Creates the core's one runtime. Free it with storyarc_runtime_free when the app quits. */
int32_t storyarc_runtime_new(void **out_runtime);

/* Releases the runtime, after every handle made from it. */
void storyarc_runtime_free(void *runtime);

/* Creates the HTTP client every catalogue, server and download shares. */
int32_t storyarc_http_new(const void *runtime, void **out_http);

/* Pins the certificate fingerprint the reader accepted for `host`. */
int32_t storyarc_http_pin(const void *http, const uint8_t *host, size_t host_len,
                          const uint8_t *fingerprint, size_t fingerprint_len);

/* Releases the HTTP client. */
void storyarc_http_free(void *http);

/* Connects to a share: {"address", "port"?, "username"?, "password"?}. The four named
 * failures and the SMB 1 refusal are status codes with the remedy in the message. */
int32_t storyarc_smb_connect(const void *runtime, const uint8_t *request, size_t request_len,
                             void **out_share);

/* Writes {"dialect", "isEncrypted"} for a connected share. */
int32_t storyarc_smb_identity(const void *share, StoryArcBuffer *out);

/* Lists one folder: [{"name", "path", "isDirectory", "length"}], folders first. */
int32_t storyarc_smb_list(const void *share, const uint8_t *path, size_t path_len,
                          StoryArcBuffer *out);

/* Releases a share and its session. */
void storyarc_smb_free(void *share);

/* Fetches a catalogue page or a search: {"root", "url"?, "search"?, "username"?,
 * "password"?, "token"?}. Writes the page, or {"localOnly": true}. */
int32_t storyarc_opds_feed(const void *http, const uint8_t *request, size_t request_len,
                           StoryArcBuffer *out);

/* One Kavita call: {"address", "apiKey", "call", "library"?, "series"?}. */
int32_t storyarc_kavita_call(const void *http, const uint8_t *request, size_t request_len,
                             StoryArcBuffer *out);

/* Writes 0 unmetered or undescribed, 1 metered, 2 no connection. */
int32_t storyarc_network_state(const void *runtime, int32_t *out_state);

/* Downloads one publication, resuming a partial file, verifying it by indexing and moving it
 * into place. `progress` may be NULL; it receives `context`, the bytes so far and the total or
 * -1. Writes {"path", "resumption", "length", "publication"}. */
int32_t storyarc_download_fetch(const void *http, const uint8_t *request, size_t request_len,
                                const void *cancel,
                                void (*progress)(void *context, uint64_t received, int64_t total),
                                void *context, StoryArcBuffer *out);

/* ---- Wave 3: the reader's data (src/data.rs). ------------------------------------------ */

/* Opens the vault over the system's store, or the session alone when none runs. */
int32_t storyarc_vault_open(const void *runtime, void **out_vault);

/* Saves a secret under {"sourceId", "field"}. Writes {"stored": true} or
 * {"stored": false, "notice"}. */
int32_t storyarc_vault_save(const void *vault, const uint8_t *key, size_t key_len,
                            const uint8_t *secret, size_t secret_len, StoryArcBuffer *out);

/* Writes the secret under {"sourceId", "field"}, or STORYARC_ERROR_NOT_FOUND. */
int32_t storyarc_vault_load(const void *vault, const uint8_t *key, size_t key_len,
                            StoryArcBuffer *out);

/* Removes the secret under {"sourceId", "field"} everywhere. */
int32_t storyarc_vault_delete(const void *vault, const uint8_t *key, size_t key_len);

/* Releases the vault; session-only secrets go with it. */
void storyarc_vault_free(void *vault);

/* Applies {"queue", "ops", "startable"?} to the download queue. Writes {"queue",
 * "startable", "retry"}. */
int32_t storyarc_queue_apply(const uint8_t *request, size_t request_len, StoryArcBuffer *out);

/* Applies {"shelves", "ops"} to the collections and reading lists. Writes the shelves. */
int32_t storyarc_shelves_apply(const uint8_t *request, size_t request_len, StoryArcBuffer *out);

/* Reconciles offline shelf edits with {"queue", "remote"}. Writes {"toPush", "toDrop",
 * "conflicts"}. */
int32_t storyarc_shelf_pull(const uint8_t *request, size_t request_len, StoryArcBuffer *out);

/* Merges a library document into the snapshot JSON this device holds. */
int32_t storyarc_library_import(const uint8_t *document, size_t document_len,
                                const uint8_t *snapshot, size_t snapshot_len,
                                const uint8_t *device, size_t device_len, StoryArcBuffer *out);

/* Writes the library document for {"snapshot", "appVersion", "device", "now", "forSync"?,
 * "sealed"?}. */
int32_t storyarc_library_export(const uint8_t *request, size_t request_len, StoryArcBuffer *out);

/* Synchronises with the document in a folder: {"folder", "device", "appVersion", "now",
 * "snapshot"}. An unreachable folder is STORYARC_ERROR_UNREACHABLE. */
int32_t storyarc_library_sync(const uint8_t *request, size_t request_len, StoryArcBuffer *out);

/* Opens sealed secrets: {"passphrase", "secrets"}. A wrong passphrase is
 * STORYARC_ERROR_UNAUTHORIZED. */
int32_t storyarc_secrets_open(const uint8_t *request, size_t request_len, StoryArcBuffer *out);

/* The diagnostic's text for {"title", "sections", "secrets"}, every secret removed. */
int32_t storyarc_diagnostic_render(const uint8_t *request, size_t request_len,
                                   StoryArcBuffer *out);

/* Writes what every file under `path` weighs. */
int32_t storyarc_storage_bytes(const uint8_t *path, size_t path_len, uint64_t *out_bytes);

/* Seals secrets for an export: {"passphrase", "secrets": {id: text}}. */
int32_t storyarc_secrets_seal(const uint8_t *request, size_t request_len, StoryArcBuffer *out);

/* Wave 4: reading. The EPUB manifest and positions the desktop EPUB bundle takes (task 4.3)
 * and the PDF engine (task 4.4). */

/* Opens the EPUB at `path`, builds its Readium Web Publication Manifest with `self_url` as
 * the manifest's own address, and writes an EPUB handle to `out_epub`. Not an EPUB is
 * STORYARC_ERROR_UNSUPPORTED; no package document is STORYARC_ERROR_UNREADABLE. */
int32_t storyarc_epub_open(const uint8_t *path, size_t path_len, const uint8_t *self_url,
                           size_t self_url_len, void **out_epub);

/* Writes the manifest as UTF-8 JSON: metadata with layout and readingProgression,
 * readingOrder, resources, toc and the self link. Every other href is a container path. */
int32_t storyarc_epub_manifest(const void *epub, StoryArcBuffer *out);

/* Writes the positions list as a UTF-8 JSON array of locators, the numbers the phones show. */
int32_t storyarc_epub_positions(const void *epub, StoryArcBuffer *out);

/* Writes the resource at the container path `href` to `out_bytes` and its declared media
 * type to `out_media_type`, for the scheme handler. Missing is STORYARC_ERROR_NOT_FOUND. */
int32_t storyarc_epub_resource(const void *epub, const uint8_t *href, size_t href_len,
                               StoryArcBuffer *out_bytes, StoryArcBuffer *out_media_type);

/* Releases an EPUB handle. */
void storyarc_epub_free(void *epub);

/* Starts the PDF engine on its one thread, binding to the PDFium library in `library_dir`
 * (a length of zero lets the core look in STORYARC_PDFIUM_DIR, beside the executable, then
 * the system). The first call decides the library for the process. A library that cannot
 * be loaded is STORYARC_ERROR_UNSUPPORTED, with every folder tried in the message. */
int32_t storyarc_pdf_engine_start(const uint8_t *library_dir, size_t library_dir_len);

/* Opens the PDF at `path` through ranged reads and writes a PDF handle to `out_pdf`. A
 * file PDFium cannot open is STORYARC_ERROR_UNREADABLE. */
int32_t storyarc_pdf_open(const uint8_t *path, size_t path_len, void **out_pdf);

/* Writes the page count. */
int32_t storyarc_pdf_page_count(const void *pdf, uint32_t *out_count);

/* Writes a page's size in PDF points. A page past the end is STORYARC_ERROR_INVALID_ARGUMENT. */
int32_t storyarc_pdf_page_size(const void *pdf, uint32_t index, float *out_width,
                               float *out_height);

/* Renders a page to 8-bit RGBA, not premultiplied, at most `max_pixel_size` on its longest
 * edge (zero for one pixel per point). The three outputs are zeroed on failure. */
int32_t storyarc_pdf_render_page(const void *pdf, uint32_t index, uint32_t max_pixel_size,
                                 StoryArcBuffer *out_pixels, uint32_t *out_width,
                                 uint32_t *out_height);

/* Writes a page's text as UTF-8, empty for a page with no text layer. */
int32_t storyarc_pdf_page_text(const void *pdf, uint32_t index, StoryArcBuffer *out);

/* Writes 1 when any page carries text, else 0. */
int32_t storyarc_pdf_has_text_layer(const void *pdf, int32_t *out_flag);

/* Searches every page for `query`, case folded. Writes a UTF-8 JSON array of {"page",
 * "rects": [{"left", "bottom", "right", "top"}]} in PDF points, origin bottom left. */
int32_t storyarc_pdf_search(const void *pdf, const uint8_t *query, size_t query_len,
                            StoryArcBuffer *out);

/* Writes the outline as a UTF-8 JSON array of {"title", "page"?, "children"}, nested. */
int32_t storyarc_pdf_outline(const void *pdf, StoryArcBuffer *out);

/* Releases a PDF handle and closes the document. */
void storyarc_pdf_free(void *pdf);

#ifdef __cplusplus
}
#endif

#endif
