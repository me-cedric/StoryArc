/*
 * JNI shim over libarchive's RAR readers.
 *
 * The Android counterpart of iOS's RarDecoder.swift, and deliberately the same
 * shape: a path in, entry bytes out. Everything else about a CBR — names, sizes,
 * the cover, solid, encrypted, and reading stored entries — is done by
 * RarReader.kt from headers, with no C involved. So this file is the whole of
 * libarchive's job on Android.
 *
 * Only the two RAR readers are registered. archive_read_support_format_all() is
 * not vendored, so no other parser is reachable even by accident — see
 * third_party/libarchive/VENDORING.md.
 *
 * Every function returns NULL on failure and leaves a message in the out
 * parameter or the log, rather than throwing from C. The Kotlin side turns that
 * into a typed exception, which keeps the JNI boundary free of exception state.
 */

#include <jni.h>
#include <stdlib.h>
#include <string.h>

#include <archive.h>
#include <archive_entry.h>

/* Reading in 64 KB blocks, matching the iOS decoder. */
#define BLOCK_SIZE (64 * 1024)

/*
 * A ceiling on one entry's unpacked size. The size in a RAR header is untrusted:
 * without a cap, a crafted archive claiming a petabyte would drive the loop until
 * the process died. 512 MB is far past any real comic page.
 */
#define MAX_ENTRY_BYTES (512L * 1024L * 1024L)

/* Opens an archive with only the RAR readers registered. */
static struct archive *open_rar(const char *path)
{
	struct archive *a = archive_read_new();
	if (a == NULL)
		return NULL;
	archive_read_support_format_rar(a);
	archive_read_support_format_rar5(a);
	archive_read_support_filter_none(a);
	if (archive_read_open_filename(a, path, BLOCK_SIZE) != ARCHIVE_OK) {
		archive_read_free(a);
		return NULL;
	}
	return a;
}

/*
 * Drains the current entry into a fresh Java byte array.
 *
 * `declared` seeds the allocation but never bounds the loop, and a short read is
 * reported as failure rather than returned as a truncated page: handing half an
 * image to the decoder would surface as "corrupt file" and hide the real cause.
 */
static jbyteArray read_entry(JNIEnv *env, struct archive *a, jlong declared)
{
	if (declared < 0 || declared > MAX_ENTRY_BYTES)
		return NULL;

	size_t capacity = declared > 0 ? (size_t)declared : BLOCK_SIZE;
	unsigned char *buffer = malloc(capacity);
	if (buffer == NULL)
		return NULL;

	size_t filled = 0;
	for (;;) {
		if (filled == capacity) {
			if (capacity >= (size_t)MAX_ENTRY_BYTES)
				break;
			size_t grown = capacity * 2;
			if (grown > (size_t)MAX_ENTRY_BYTES)
				grown = (size_t)MAX_ENTRY_BYTES;
			unsigned char *bigger = realloc(buffer, grown);
			if (bigger == NULL) {
				free(buffer);
				return NULL;
			}
			buffer = bigger;
			capacity = grown;
		}
		ssize_t got = archive_read_data(a, buffer + filled, capacity - filled);
		if (got == 0)
			break;
		if (got < 0) {
			free(buffer);
			return NULL;
		}
		filled += (size_t)got;
	}

	if (declared > 0 && filled != (size_t)declared) {
		free(buffer);
		return NULL;
	}

	jbyteArray out = (*env)->NewByteArray(env, (jsize)filled);
	if (out != NULL)
		(*env)->SetByteArrayRegion(env, out, 0, (jsize)filled, (const jbyte *)buffer);
	free(buffer);
	return out;
}

/*
 * Entry names and sizes as libarchive sees them, as a flat String[] of
 * "name\tsize" pairs.
 *
 * Not used for indexing — RarReader.kt does that without a C library. This
 * exists so a test can assert the two agree, which is the only way to know the
 * header parser and the decoder are looking at the same archive.
 */
JNIEXPORT jobjectArray JNICALL
Java_app_storyarc_core_format_RarDecoder_nativeEntryNames(
	JNIEnv *env, jclass clazz, jstring archivePath)
{
	(void)clazz;
	const char *path = (*env)->GetStringUTFChars(env, archivePath, NULL);
	if (path == NULL)
		return NULL;

	struct archive *a = open_rar(path);
	(*env)->ReleaseStringUTFChars(env, archivePath, path);
	if (a == NULL)
		return NULL;

	/* Collected into a list first, since the count is not known up front. */
	size_t capacity = 32, count = 0;
	char **rows = calloc(capacity, sizeof(char *));
	if (rows == NULL) {
		archive_read_free(a);
		return NULL;
	}

	struct archive_entry *entry;
	int failed = 0;
	for (;;) {
		int status = archive_read_next_header(a, &entry);
		if (status == ARCHIVE_EOF)
			break;
		if (status != ARCHIVE_OK && status != ARCHIVE_WARN) {
			failed = 1;
			break;
		}
		const char *name = archive_entry_pathname(entry);
		if (name == NULL)
			continue;

		if (count == capacity) {
			size_t grown = capacity * 2;
			char **bigger = realloc(rows, grown * sizeof(char *));
			if (bigger == NULL) {
				failed = 1;
				break;
			}
			rows = bigger;
			capacity = grown;
		}
		/* 21 digits covers any int64, plus a tab and a terminator. */
		size_t room = strlen(name) + 24;
		char *row = malloc(room);
		if (row == NULL) {
			failed = 1;
			break;
		}
		snprintf(row, room, "%s\t%lld", name,
			 (long long)archive_entry_size(entry));
		rows[count++] = row;
	}
	archive_read_free(a);

	jobjectArray out = NULL;
	if (!failed) {
		jclass stringClass = (*env)->FindClass(env, "java/lang/String");
		if (stringClass != NULL) {
			out = (*env)->NewObjectArray(env, (jsize)count, stringClass, NULL);
			for (size_t i = 0; out != NULL && i < count; i++) {
				jstring value = (*env)->NewStringUTF(env, rows[i]);
				if (value == NULL) {
					out = NULL;
					break;
				}
				(*env)->SetObjectArrayElement(env, out, (jsize)i, value);
				/* Freed eagerly: a large archive would otherwise fill
				 * the local reference table before returning. */
				(*env)->DeleteLocalRef(env, value);
			}
		}
	}
	for (size_t i = 0; i < count; i++)
		free(rows[i]);
	free(rows);
	return out;
}

/* Unpacked bytes for one entry, found by its path inside the archive. */
JNIEXPORT jbyteArray JNICALL
Java_app_storyarc_core_format_RarDecoder_nativeEntryData(
	JNIEnv *env, jclass clazz, jstring archivePath, jstring entryName)
{
	(void)clazz;
	const char *path = (*env)->GetStringUTFChars(env, archivePath, NULL);
	if (path == NULL)
		return NULL;
	const char *wanted = (*env)->GetStringUTFChars(env, entryName, NULL);
	if (wanted == NULL) {
		(*env)->ReleaseStringUTFChars(env, archivePath, path);
		return NULL;
	}

	struct archive *a = open_rar(path);
	jbyteArray out = NULL;
	if (a != NULL) {
		struct archive_entry *entry;
		for (;;) {
			int status = archive_read_next_header(a, &entry);
			if (status == ARCHIVE_EOF)
				break;
			if (status != ARCHIVE_OK && status != ARCHIVE_WARN)
				break;
			const char *name = archive_entry_pathname(entry);
			if (name == NULL || strcmp(name, wanted) != 0)
				continue;
			out = read_entry(env, a, (jlong)archive_entry_size(entry));
			break;
		}
		archive_read_free(a);
	}

	(*env)->ReleaseStringUTFChars(env, entryName, wanted);
	(*env)->ReleaseStringUTFChars(env, archivePath, path);
	return out;
}

/*
 * Several entries in one pass, returned as a byte[][] parallel to `entryNames`
 * with NULL for any entry not found.
 *
 * One pass rather than one open per page. A solid archive makes this the only
 * affordable shape: reading page 30 there means decompressing 1 to 29, so asking
 * page by page would be quadratic.
 */
JNIEXPORT jobjectArray JNICALL
Java_app_storyarc_core_format_RarDecoder_nativeEntriesData(
	JNIEnv *env, jclass clazz, jstring archivePath, jobjectArray entryNames)
{
	(void)clazz;
	jsize wanted = (*env)->GetArrayLength(env, entryNames);
	jclass byteArrayClass = (*env)->FindClass(env, "[B");
	if (byteArrayClass == NULL)
		return NULL;
	jobjectArray out = (*env)->NewObjectArray(env, wanted, byteArrayClass, NULL);
	if (out == NULL || wanted == 0)
		return out;

	const char *path = (*env)->GetStringUTFChars(env, archivePath, NULL);
	if (path == NULL)
		return NULL;
	struct archive *a = open_rar(path);
	(*env)->ReleaseStringUTFChars(env, archivePath, path);
	if (a == NULL)
		return NULL;

	jsize remaining = wanted;
	struct archive_entry *entry;
	while (remaining > 0) {
		int status = archive_read_next_header(a, &entry);
		if (status == ARCHIVE_EOF)
			break;
		if (status != ARCHIVE_OK && status != ARCHIVE_WARN)
			break;
		const char *name = archive_entry_pathname(entry);
		if (name == NULL)
			continue;

		for (jsize i = 0; i < wanted; i++) {
			jstring candidate = (jstring)(*env)->GetObjectArrayElement(env, entryNames, i);
			if (candidate == NULL)
				continue;
			const char *text = (*env)->GetStringUTFChars(env, candidate, NULL);
			int matches = text != NULL && strcmp(text, name) == 0;
			if (text != NULL)
				(*env)->ReleaseStringUTFChars(env, candidate, text);
			if (!matches) {
				(*env)->DeleteLocalRef(env, candidate);
				continue;
			}
			(*env)->DeleteLocalRef(env, candidate);

			/* Already filled means a duplicate name; keep the first. */
			jobject existing = (*env)->GetObjectArrayElement(env, out, i);
			if (existing != NULL) {
				(*env)->DeleteLocalRef(env, existing);
				break;
			}
			jbyteArray data = read_entry(env, a, (jlong)archive_entry_size(entry));
			if (data != NULL) {
				(*env)->SetObjectArrayElement(env, out, i, data);
				(*env)->DeleteLocalRef(env, data);
				remaining--;
			}
			break;
		}
	}
	archive_read_free(a);
	return out;
}
