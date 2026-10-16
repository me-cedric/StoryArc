/*
 * Hand-authored libarchive configuration for the StoryArc desktop core on Linux (glibc).
 *
 * The vendored `third_party/libarchive/Sources/CLibarchive/config.h` covers Apple and
 * Android, and iOS and Android compile it, so it stays untouched (design.md, Decision 7).
 * This header is the desktop-only Linux configuration; `build.rs` hands its path to
 * libarchive through the library's own `PLATFORM_CONFIG_H` hook, which
 * `archive_platform.h` consults before `config.h`. (A `#include "config.h"` resolves the
 * including file's own directory before any include path, so an include-path order alone
 * cannot shadow the vendored header.)
 *
 * The content follows the vendored header's non-Apple branch: glibc and bionic agree on
 * `struct stat`'s `st_mtim`, on `major()` living in <sys/sysmacros.h>, and on
 * `arc4random_buf` (glibc 2.36; Ubuntu 24.04 ships 2.39). Everything optional is OFF for
 * the same reason as on mobile — RAR needs no zlib, no OpenSSL, no iconv — and because the
 * desktop binary is built by the `cc` crate with no configure step to probe for them.
 *
 * macOS hosts use the vendored header as is: it is the iOS configuration and the host is
 * the same platform. MSVC gets its own header beside this one in task 1.7.
 */

#ifndef STORYARC_LIBARCHIVE_CONFIG_LINUX_H
#define STORYARC_LIBARCHIVE_CONFIG_LINUX_H

/* Version reported by archive_version_string(). Keep in step with third_party/libarchive/pin.json. */
#define ARCHIVE_VERSION_ONLY_STRING "3.8.9"
#define ARCHIVE_VERSION_STRING "libarchive " ARCHIVE_VERSION_ONLY_STRING
#define ARCHIVE_VERSION_NUMBER 3008009
#define VERSION ARCHIVE_VERSION_ONLY_STRING

/* ── Headers ────────────────────────────────────────────────────────────── */
#define HAVE_CTYPE_H 1
#define HAVE_DIRENT_H 1
#define HAVE_DLFCN_H 1
#define HAVE_ERRNO_H 1
#define HAVE_FCNTL_H 1
#define HAVE_FNMATCH_H 1
#define HAVE_GRP_H 1
#define HAVE_INTTYPES_H 1
#define HAVE_LANGINFO_H 1
#define HAVE_LIMITS_H 1
#define HAVE_LOCALE_H 1
#define HAVE_MEMORY_H 1
#define HAVE_PATHS_H 1
#define HAVE_POLL_H 1
#define HAVE_PTHREAD_H 1
#define HAVE_PWD_H 1
#define HAVE_REGEX_H 1
#define HAVE_SIGNAL_H 1
#define HAVE_STDARG_H 1
#define HAVE_STDINT_H 1
#define HAVE_STDLIB_H 1
#define HAVE_STRINGS_H 1
#define HAVE_STRING_H 1
#define HAVE_SYS_CDEFS_H 1
#define HAVE_SYS_IOCTL_H 1
#define HAVE_SYS_PARAM_H 1
#define HAVE_SYS_POLL_H 1
#define HAVE_SYS_SELECT_H 1
#define HAVE_SYS_STAT_H 1
#define HAVE_SYS_STATVFS_H 1
#define HAVE_SYS_SYSMACROS_H 1
#define HAVE_SYS_TIME_H 1
#define HAVE_SYS_TYPES_H 1
#define HAVE_SYS_UTSNAME_H 1
#define HAVE_SYS_WAIT_H 1
#define HAVE_TIME_H 1
#define HAVE_UNISTD_H 1
#define HAVE_UTIME_H 1
#define HAVE_WCHAR_H 1
#define HAVE_WCTYPE_H 1

/* ── Functions ──────────────────────────────────────────────────────────── */
#define HAVE_ARC4RANDOM_BUF 1
#define HAVE_CHOWN 1
#define HAVE_CTIME_R 1
#define HAVE_FCHDIR 1
#define HAVE_FCHMOD 1
#define HAVE_FCHOWN 1
#define HAVE_FCNTL 1
#define HAVE_FDOPENDIR 1
#define HAVE_FNMATCH 1
#define HAVE_FORK 1
#define HAVE_FSEEKO 1
#define HAVE_FSTAT 1
#define HAVE_FSTATAT 1
#define HAVE_FSTATVFS 1
#define HAVE_FTRUNCATE 1
#define HAVE_FUTIMENS 1
#define HAVE_FUTIMES 1
#define HAVE_GETEUID 1
#define HAVE_GETGRGID_R 1
#define HAVE_GETGRNAM_R 1
#define HAVE_GETLINE 1
#define HAVE_GETPID 1
#define HAVE_GETPWNAM_R 1
#define HAVE_GETPWUID_R 1
#define HAVE_GETRESGID 1
#define HAVE_GETRESUID 1
#define HAVE_GMTIME_R 1
#define HAVE_LCHOWN 1
#define HAVE_LINK 1
#define HAVE_LINKAT 1
#define HAVE_LOCALTIME_R 1
#define HAVE_LSTAT 1
#define HAVE_LUTIMES 1
#define HAVE_MBRTOWC 1
#define HAVE_MEMMOVE 1
#define HAVE_MEMSET 1
#define HAVE_MKDIR 1
#define HAVE_MKFIFO 1
#define HAVE_MKNOD 1
#define HAVE_MKSTEMP 1
#define HAVE_NL_LANGINFO 1
#define HAVE_OPENAT 1
#define HAVE_PIPE 1
#define HAVE_POLL 1
#define HAVE_READLINK 1
#define HAVE_READLINKAT 1
#define HAVE_SELECT 1
#define HAVE_SETENV 1
#define HAVE_SETLOCALE 1
#define HAVE_SIGACTION 1
#define HAVE_STATVFS 1
#define HAVE_STRCHR 1
#define HAVE_STRDUP 1
#define HAVE_STRERROR 1
#define HAVE_STRERROR_R 1
#define HAVE_STRFTIME 1
#define HAVE_STRNLEN 1
#define HAVE_STRRCHR 1
#define HAVE_SYMLINK 1
#define HAVE_TCGETATTR 1
#define HAVE_TCSETATTR 1
#define HAVE_TIMEGM 1
#define HAVE_TZSET 1
#define HAVE_UNLINKAT 1
#define HAVE_UNSETENV 1
#define HAVE_UTIMENSAT 1
#define HAVE_UTIMES 1
#define HAVE_VFORK 1
#define HAVE_VPRINTF 1
#define HAVE_WCRTOMB 1
#define HAVE_WCSCMP 1
#define HAVE_WCSCPY 1
#define HAVE_WCSLEN 1
#define HAVE_WCTOMB 1
#define HAVE_WMEMCMP 1
#define HAVE_WMEMCPY 1
#define HAVE_WMEMMOVE 1

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
#define HAVE_DECL_SSIZE_MAX 1
#define HAVE_DECL_UINT32_MAX 1
#define HAVE_DECL_UINT64_MAX 1
#define HAVE_DECL_UINT64_MIN 1
#define HAVE_DECL_UINTMAX_MAX 1
#define HAVE_DECL_STRERROR_R 1
#define HAVE_EILSEQ 1
#define HAVE_MAJOR 1
/* glibc declares major()/minor()/makedev() in <sys/sysmacros.h> only. */
#define MAJOR_IN_SYSMACROS 1

#define SIZEOF_INT 4
#define SIZEOF_LONG 8
#define SIZEOF_WCHAR_T 4

/* struct stat on glibc: nanoseconds live in st_mtim. */
#define HAVE_STRUCT_STAT_ST_BLKSIZE 1
#define HAVE_STRUCT_STAT_ST_MTIM_TV_NSEC 1
#define HAVE_STRUCT_TM_TM_GMTOFF 1

/* ── Deliberately absent ────────────────────────────────────────────────── */
/*
 * HAVE_LIBZ, HAVE_BZLIB_H, HAVE_LZMA_H, HAVE_LZ4_H, HAVE_ZSTD_H, HAVE_LIBCRYPTO,
 * HAVE_OPENSSL_*, HAVE_LIBNETTLE, HAVE_LIBMBEDCRYPTO, HAVE_ICONV, HAVE_LIBXML2,
 * HAVE_READPASSPHRASE, HAVE_LINUX_FS_H, HAVE_LINUX_EXT2_FS_H, HAVE_LIBACL,
 * HAVE_SYS_XATTR_H: none of them is needed to decompress a RAR entry, which is the whole
 * of libarchive's job here, and each one would be a library the desktop binary has to
 * carry on every distro it targets.
 */

#endif /* STORYARC_LIBARCHIVE_CONFIG_LINUX_H */
