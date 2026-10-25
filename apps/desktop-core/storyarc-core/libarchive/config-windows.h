/*
 * Hand-authored libarchive configuration for the StoryArc desktop core on Windows (MSVC),
 * x64 and ARM64. Task 1.7 of `desktop-clients`.
 *
 * Reached the same way as `config-linux.h`: `build.rs` hands its path to libarchive through
 * the `PLATFORM_CONFIG_H` hook, which `archive_platform.h` reads before anything else.
 * `archive_platform.h` then includes the vendored `archive_windows.h`, which maps the POSIX
 * names to the CRT and declares the `__la_*` replacements; `windows-shim.c` beside this file
 * defines the few of them the RAR readers reach.
 *
 * The values follow what libarchive's own CMake build writes for MSVC. Everything optional
 * is OFF for the same reason as on Linux and mobile: RAR needs no zlib, no OpenSSL, no
 * iconv. `archive_random.c` takes its Windows branch, BCryptGenRandom, so `build.rs` links
 * `bcrypt`.
 */

#ifndef STORYARC_LIBARCHIVE_CONFIG_WINDOWS_H
#define STORYARC_LIBARCHIVE_CONFIG_WINDOWS_H

/* Windows 10 API set, before any system header; the app's floor is Windows 11 24H2. */
#ifndef _WIN32_WINNT
#define _WIN32_WINNT 0x0A00
#endif
#ifndef WINVER
#define WINVER _WIN32_WINNT
#endif
#ifndef _CRT_SECURE_NO_WARNINGS
#define _CRT_SECURE_NO_WARNINGS 1
#endif
#ifndef _CRT_NONSTDC_NO_DEPRECATE
#define _CRT_NONSTDC_NO_DEPRECATE 1
#endif

/* Version reported by archive_version_string(). Keep in step with third_party/libarchive/pin.json. */
#define ARCHIVE_VERSION_ONLY_STRING "3.8.10"
#define ARCHIVE_VERSION_STRING "libarchive " ARCHIVE_VERSION_ONLY_STRING
#define ARCHIVE_VERSION_NUMBER 3008010
#define VERSION ARCHIVE_VERSION_ONLY_STRING

/* ── Headers ────────────────────────────────────────────────────────────── */
#define HAVE_BCRYPT_H 1
#define HAVE_CTYPE_H 1
#define HAVE_DIRECT_H 1
#define HAVE_ERRNO_H 1
#define HAVE_FCNTL_H 1
#define HAVE_INTTYPES_H 1
#define HAVE_IO_H 1
#define HAVE_LIMITS_H 1
#define HAVE_LOCALE_H 1
#define HAVE_MEMORY_H 1
#define HAVE_PROCESS_H 1
#define HAVE_SIGNAL_H 1
#define HAVE_STDARG_H 1
#define HAVE_STDINT_H 1
#define HAVE_STDLIB_H 1
#define HAVE_STRING_H 1
#define HAVE_SYS_STAT_H 1
#define HAVE_SYS_TYPES_H 1
#define HAVE_SYS_UTIME_H 1
#define HAVE_TIME_H 1
#define HAVE_WCHAR_H 1
#define HAVE_WCTYPE_H 1
#define HAVE_WINCRYPT_H 1
#define HAVE_WINDOWS_H 1

/* ── Functions ──────────────────────────────────────────────────────────── */
#define HAVE_GMTIME_S 1
#define HAVE_LOCALTIME_S 1
#define HAVE_MBRTOWC 1
#define HAVE_MEMMOVE 1
#define HAVE_MEMSET 1
#define HAVE_SETLOCALE 1
#define HAVE_STRCHR 1
#define HAVE_STRDUP 1
#define HAVE_STRERROR 1
#define HAVE_STRFTIME 1
#define HAVE_STRNLEN 1
#define HAVE_STRRCHR 1
#define HAVE_VPRINTF 1
#define HAVE_WCRTOMB 1
#define HAVE_WCSCMP 1
#define HAVE_WCSCPY 1
#define HAVE_WCSLEN 1
#define HAVE_WCTOMB 1
#define HAVE_WMEMCMP 1
#define HAVE_WMEMCPY 1
#define HAVE_WMEMMOVE 1
#define HAVE__CTIME64_S 1
#define HAVE__FSEEKI64 1
#define HAVE__GET_TIMEZONE 1
#define HAVE__MKGMTIME 1

/* ── Types ──────────────────────────────────────────────────────────────── */
#define HAVE_INTMAX_T 1
#define HAVE_UINTMAX_T 1
#define HAVE_LONG_LONG_INT 1
#define HAVE_UNSIGNED_LONG_LONG 1
#define HAVE_UNSIGNED_LONG_LONG_INT 1
#define HAVE_WCHAR_T 1
#define HAVE_DECL_INT32_MAX 1
#define HAVE_DECL_INT32_MIN 1
#define HAVE_DECL_INT64_MAX 1
#define HAVE_DECL_INT64_MIN 1
#define HAVE_DECL_INTMAX_MAX 1
#define HAVE_DECL_INTMAX_MIN 1
#define HAVE_DECL_SIZE_MAX 1
#define HAVE_DECL_UINT32_MAX 1
#define HAVE_DECL_UINT64_MAX 1
#define HAVE_DECL_UINTMAX_MAX 1
#define HAVE_EILSEQ 1

/* LLP64: long stays 32-bit on both x64 and ARM64; wchar_t is UTF-16. */
#define SIZEOF_INT 4
#define SIZEOF_LONG 4
#define SIZEOF_WCHAR_T 2

/* The POSIX types the CRT does not declare, as libarchive's CMake build defines them. */
#define gid_t short
#define id_t short
#define mode_t unsigned short
#define pid_t int
#define uid_t short
#define ssize_t __int64

/* ── Deliberately absent ────────────────────────────────────────────────── */
/*
 * HAVE_LIBZ, HAVE_BZLIB_H, HAVE_LZMA_H, HAVE_LZ4_H, HAVE_ZSTD_H, HAVE_LIBCRYPTO,
 * HAVE_OPENSSL_*, HAVE_LIBNETTLE, HAVE_LIBMBEDCRYPTO, HAVE_ICONV, HAVE_LIBXML2,
 * HAVE_UNISTD_H: none of them is needed to decompress a RAR entry, and MSVC has no
 * unistd.h. HAVE_DECL_SSIZE_MAX stays off so archive_platform.h derives SSIZE_MAX.
 */

#endif /* STORYARC_LIBARCHIVE_CONFIG_WINDOWS_H */
