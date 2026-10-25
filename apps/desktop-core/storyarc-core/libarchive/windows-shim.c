/*
 * The `__la_*` replacements `archive_windows.h` declares, for the StoryArc desktop core on
 * Windows (task 1.7 of `desktop-clients`).
 *
 * Upstream keeps them in `archive_windows.c`, which is not vendored: it also carries the
 * disk-writer, the pipe and the ACL code the RAR readers never reach. This file defines only
 * the seven symbols the vendored sources link against, which the MSVC linker named.
 *
 * One deliberate difference from upstream: a narrow path is UTF-8, not the ANSI code page.
 * The only caller is `libarchive_sys.rs`, and a Rust `&str` is UTF-8, so a book in a folder
 * named in any script opens rather than failing in the code page conversion.
 */

#include "archive_platform.h"

#include <errno.h>
#include <io.h>
#include <limits.h>
#include <stdarg.h>
#include <stdlib.h>
#include <string.h>
#include <sys/stat.h>
#include <wchar.h>
#include <windows.h>

/* archive_windows.h maps `_wopen` to `__la_wopen`; this file needs the CRT's own. */
#undef _wopen

/* A UTF-8 string as a freshly allocated wide string, or NULL with errno set. */
static wchar_t *
utf8_to_wide(const char *text)
{
	int count = MultiByteToWideChar(CP_UTF8, MB_ERR_INVALID_CHARS, text, -1, NULL, 0);
	wchar_t *wide;

	if (count <= 0) {
		errno = EINVAL;
		return NULL;
	}
	wide = malloc((size_t)count * sizeof(wchar_t));
	if (wide == NULL) {
		errno = ENOMEM;
		return NULL;
	}
	MultiByteToWideChar(CP_UTF8, MB_ERR_INVALID_CHARS, text, -1, wide, count);
	return wide;
}

void
__la_dosmaperr(unsigned long e)
{
	switch (e) {
	case ERROR_FILE_NOT_FOUND:
	case ERROR_PATH_NOT_FOUND:
	case ERROR_INVALID_DRIVE:
	case ERROR_BAD_NETPATH:
	case ERROR_BAD_PATHNAME:
		errno = ENOENT;
		break;
	case ERROR_ACCESS_DENIED:
	case ERROR_SHARING_VIOLATION:
	case ERROR_LOCK_VIOLATION:
		errno = EACCES;
		break;
	case ERROR_NOT_ENOUGH_MEMORY:
	case ERROR_OUTOFMEMORY:
		errno = ENOMEM;
		break;
	case ERROR_INVALID_HANDLE:
		errno = EBADF;
		break;
	case ERROR_FILE_EXISTS:
	case ERROR_ALREADY_EXISTS:
		errno = EEXIST;
		break;
	case ERROR_DISK_FULL:
		errno = ENOSPC;
		break;
	default:
		errno = EINVAL;
		break;
	}
}

/*
 * The full path with the `\\?\` prefix, which lifts MAX_PATH; `\\server\share` becomes
 * `\\?\UNC\server\share`. A path that already carries a prefix is returned as a copy.
 */
wchar_t *
__la_win_permissive_name_w(const wchar_t *wname)
{
	static const wchar_t local[] = L"\\\\?\\";
	static const wchar_t unc[] = L"\\\\?\\UNC\\";
	DWORD needed;
	DWORD written;
	wchar_t *full;
	wchar_t *result;
	const wchar_t *body;
	const wchar_t *prefix;
	size_t length;

	if (wname == NULL || wname[0] == L'\0') {
		errno = EINVAL;
		return NULL;
	}
	if (wcsncmp(wname, local, 4) == 0)
		return _wcsdup(wname);

	needed = GetFullPathNameW(wname, 0, NULL, NULL);
	if (needed == 0) {
		__la_dosmaperr(GetLastError());
		return NULL;
	}
	full = malloc((size_t)needed * sizeof(wchar_t));
	if (full == NULL) {
		errno = ENOMEM;
		return NULL;
	}
	written = GetFullPathNameW(wname, needed, full, NULL);
	if (written == 0 || written >= needed) {
		free(full);
		errno = EINVAL;
		return NULL;
	}

	if (full[0] == L'\\' && full[1] == L'\\') {
		prefix = unc;
		body = full + 2;
	} else {
		prefix = local;
		body = full;
	}
	length = wcslen(prefix) + wcslen(body) + 1;
	result = malloc(length * sizeof(wchar_t));
	if (result != NULL) {
		wcscpy(result, prefix);
		wcscat(result, body);
	} else {
		errno = ENOMEM;
	}
	free(full);
	return result;
}

int
__la_wopen(const wchar_t *path, int flags, ...)
{
	int mode = 0;

	if (flags & _O_CREAT) {
		va_list ap;
		va_start(ap, flags);
		mode = va_arg(ap, int);
		va_end(ap);
	}
	return _wopen(path, flags, mode);
}

int
__la_open(const char *path, int flags, ...)
{
	int mode = 0;
	int fd;
	wchar_t *wide;

	if (flags & _O_CREAT) {
		va_list ap;
		va_start(ap, flags);
		mode = va_arg(ap, int);
		va_end(ap);
	}
	wide = utf8_to_wide(path);
	if (wide == NULL)
		return -1;
	fd = _wopen(wide, flags, mode);
	free(wide);
	return fd;
}

/* `_read` and `_write` take an unsigned int count, so a larger request is served in part. */
ssize_t
__la_read(int fd, void *buf, size_t nbytes)
{
	unsigned int count = nbytes > INT_MAX ? INT_MAX : (unsigned int)nbytes;
	return _read(fd, buf, count);
}

ssize_t
__la_write(int fd, const void *buf, size_t nbytes)
{
	unsigned int count = nbytes > INT_MAX ? INT_MAX : (unsigned int)nbytes;
	return _write(fd, buf, count);
}

int
__la_seek_fstat(int fd, la_seek_stat_t *st)
{
	struct __stat64 native;

	if (_fstat64(fd, &native) != 0)
		return -1;
	memset(st, 0, sizeof(*st));
	st->st_mtime = native.st_mtime;
	st->st_ino = native.st_ino;
	st->st_mode = native.st_mode;
	st->st_nlink = (uint32_t)native.st_nlink;
	st->st_gid = native.st_gid;
	st->st_size = native.st_size;
	st->st_uid = native.st_uid;
	st->st_dev = native.st_dev;
	st->st_rdev = native.st_rdev;
	return 0;
}
