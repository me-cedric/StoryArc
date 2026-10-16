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

/* Status codes. */
#define STORYARC_OK 0
#define STORYARC_ERROR_INVALID_ARGUMENT 1
#define STORYARC_ERROR_CANCELLED 2

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

#ifdef __cplusplus
}
#endif

#endif
