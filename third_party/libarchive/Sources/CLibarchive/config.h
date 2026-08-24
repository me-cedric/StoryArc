/*
 * Hand-authored libarchive configuration for StoryArc.
 *
 * libarchive normally generates this with autoconf or CMake. Neither can be run
 * here: SwiftPM compiles the sources itself with no configure step, and Phase 0
 * of the format change found that libarchive's CMake cannot configure for iOS at
 * all. So the file is written once, by hand, covering the two platforms StoryArc
 * targets — both POSIX, both clang — with `__APPLE__` and `__ANDROID__` guards
 * for the handful of real differences.
 *
 * Everything optional is deliberately OFF. No zlib, no bzip2, no lzma, no
 * OpenSSL, no iconv. RAR4 and RAR5 need none of them: RAR carries its own
 * compression, and libarchive's own blake2 and ppmd7 sources are vendored
 * alongside this file. Every dependency left out is one fewer thing to build for
 * six ABIs and one fewer thing to audit.
 *
 * See VENDORING.md for the source version and how to refresh it.
 */

#ifndef STORYARC_LIBARCHIVE_CONFIG_H
#define STORYARC_LIBARCHIVE_CONFIG_H

/* Version reported by archive_version_string(). Keep in step with VENDORING.md. */
#define ARCHIVE_VERSION_ONLY_STRING "3.8.1"
#define ARCHIVE_VERSION_STRING "libarchive " ARCHIVE_VERSION_ONLY_STRING
#define ARCHIVE_VERSION_NUMBER 3008001
#define VERSION ARCHIVE_VERSION_ONLY_STRING

/* ── Headers, present on both platforms ─────────────────────────────────── */
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
#define HAVE_SYS_TIME_H 1
#define HAVE_SYS_TYPES_H 1
#define HAVE_SYS_UTSNAME_H 1
#define HAVE_SYS_WAIT_H 1
#define HAVE_TIME_H 1
#define HAVE_UNISTD_H 1
#define HAVE_UTIME_H 1
#define HAVE_WCHAR_H 1
#define HAVE_WCTYPE_H 1

/* ── Functions, present on both platforms ───────────────────────────────── */
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
#define HAVE_GMTIME_R 1
#define HAVE_LCHOWN 1
#define HAVE_LINK 1
#define HAVE_LINKAT 1
#define HAVE_LOCALTIME_R 1
#define HAVE_LSTAT 1
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

/*
 * major()/minor()/makedev() live in a different header on each platform: Apple
 * declares them in <sys/types.h>, bionic only in <sys/sysmacros.h>. libarchive
 * picks with MAJOR_IN_SYSMACROS, so Android needs it set and Apple must not have
 * it — with neither define, archive_entry.c calls them undeclared.
 */
#ifdef __ANDROID__
#define MAJOR_IN_SYSMACROS 1
#endif

#define SIZEOF_INT 4
#define SIZEOF_LONG 8
#define SIZEOF_WCHAR_T 4
/* Apple keeps 32-bit wchar_t on none of its current targets; Android matches. */

/* struct stat, where the two platforms diverge. */
#define HAVE_STRUCT_STAT_ST_BLKSIZE 1
#define HAVE_STRUCT_TM_TM_GMTOFF 1
#ifdef __APPLE__
#define HAVE_STRUCT_STAT_ST_BIRTHTIME 1
#define HAVE_STRUCT_STAT_ST_BIRTHTIMESPEC_TV_NSEC 1
#define HAVE_STRUCT_STAT_ST_MTIMESPEC_TV_NSEC 1
#define HAVE_STRUCT_STAT_ST_FLAGS 1
#define HAVE_CHFLAGS 1
#define HAVE_FCHFLAGS 1
#define HAVE_LCHFLAGS 1
#define HAVE_LCHMOD 1
#define HAVE_LUTIMES 1
#define HAVE_ARC4RANDOM_BUF 1
#define HAVE_D_MD_ORDER 1
#define HAVE_SYS_MOUNT_H 1
#define HAVE_STATFS 1
#define HAVE_FSTATFS 1
#define HAVE_GETVFSBYNAME 1
#define HAVE_STRUCT_STATFS_F_NAMEMAX 1
#define HAVE_STRUCT_XVFSCONF 1
#define HAVE_POSIX_SPAWNP 1
#define HAVE_SPAWN_H 1
#else
#define HAVE_STRUCT_STAT_ST_MTIM_TV_NSEC 1
#define HAVE_SYS_STATVFS_H 1
/* Android has had arc4random_buf since API 21, and StoryArc's floor is 31. */
#define HAVE_ARC4RANDOM_BUF 1
#endif

/* ── Deliberately absent ────────────────────────────────────────────────── */
/*
 * Left undefined on purpose, each one a dependency not taken:
 *
 *   HAVE_LIBZ / HAVE_ZLIB_H        deflate, which RAR does not use
 *   HAVE_BZLIB_H, HAVE_LZMA_H     other archive codecs, no format here needs them
 *   HAVE_LZ4_H, HAVE_ZSTD_H
 *   HAVE_LIBCRYPTO, HAVE_OPENSSL_*  RAR5 encryption is not supported; the
 *                                   password-protected refusal is honest instead
 *   HAVE_LIBNETTLE, HAVE_LIBMBEDCRYPTO
 *   HAVE_ICONV / HAVE_ICONV_H     entry names are decoded by the callers, which
 *                                 both have a platform Unicode implementation
 *   HAVE_LIBXML2, HAVE_BSDXML_H   only the XAR reader wants XML
 *   HAVE_READPASSPHRASE          StoryArc never prompts for an archive password
 *
 * Adding any of these means building it for six Android ABIs and two iOS
 * slices, so each one has to be argued for rather than assumed.
 */

#endif /* STORYARC_LIBARCHIVE_CONFIG_H */
