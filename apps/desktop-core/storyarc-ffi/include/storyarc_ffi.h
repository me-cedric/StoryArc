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

#ifdef __cplusplus
}
#endif

#endif
