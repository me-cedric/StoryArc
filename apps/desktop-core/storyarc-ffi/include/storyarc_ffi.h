#ifndef STORYARC_FFI_H
#define STORYARC_FFI_H

#ifdef __cplusplus
extern "C" {
#endif

/* Returns the storyarc-core version as a static NUL-terminated UTF-8 string.
 * The caller must never free it. The pointer stays valid for the process lifetime. */
const char *storyarc_core_version(void);

#ifdef __cplusplus
}
#endif

#endif
