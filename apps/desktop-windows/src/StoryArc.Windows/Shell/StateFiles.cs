using Windows.Storage;

namespace StoryArc.Windows.Shell;

/// <summary>
/// The files the shell keeps: the session (which windows were open, where, on which page), the
/// settings, the chosen folders, the recent list and the core's progress store. All of them live in
/// <c>Windows.Storage.ApplicationData.Current.LocalFolder</c>, the package's <c>%LOCALAPPDATA%</c> that MSIX redirects (design.md, Decision 8), never the
/// roaming folder. A read that fails is nothing to restore; a write that fails is logged by the
/// caller and never stops a window from closing.
/// </summary>
internal static class StateFiles
{
    public static string SessionPath => Path.Combine(ApplicationData.Current.LocalFolder.Path, "session.json");

    public static string SettingsPath => Path.Combine(ApplicationData.Current.LocalFolder.Path, "settings.json");

    /// <summary>The folders the reader chose (task 2.43).</summary>
    public static string SourcesPath => Path.Combine(ApplicationData.Current.LocalFolder.Path, "sources.json");

    /// <summary>The recent publications behind the Jump List (task 2.42).</summary>
    public static string RecentPath => Path.Combine(ApplicationData.Current.LocalFolder.Path, "recent.json");

    /// <summary>The core's progress store: one position per publication, in the phones' shape (task 2.44).</summary>
    public static string ProgressPath => Path.Combine(ApplicationData.Current.LocalFolder.Path, "progress.sqlite");

    /// <summary>The network sources: ids, names and addresses, never a credential (task 3.21).</summary>
    public static string NetworkSourcesPath => Path.Combine(ApplicationData.Current.LocalFolder.Path, "network-sources.json");

    /// <summary>The certificates the reader accepted: public fingerprints.</summary>
    public static string PinsPath => Path.Combine(ApplicationData.Current.LocalFolder.Path, "certificate-pins.json");

    /// <summary>The download queue (task 3.23): rows hold an address, never a credential.</summary>
    public static string DownloadQueuePath => Path.Combine(ApplicationData.Current.LocalFolder.Path, "download-queue.json");

    /// <summary>The collections and reading lists (task 3.23a).</summary>
    public static string ShelvesPath => Path.Combine(ApplicationData.Current.LocalFolder.Path, "shelves.json");

    /// <summary>The pinned shelves, as tokens in the order pinned.</summary>
    public static string PinnedShelvesPath => Path.Combine(ApplicationData.Current.LocalFolder.Path, "pinned-shelves.json");

    /// <summary>The offline edits owed to server shelves.</summary>
    public static string ShelfEditsPath => Path.Combine(ApplicationData.Current.LocalFolder.Path, "shelf-edits.json");

    /// <summary>Where downloads land: the package's local data, which MSIX does not roam.</summary>
    public static string DownloadsFolder => Path.Combine(ApplicationData.Current.LocalFolder.Path, "downloads");

    /// <summary>The cover cache, local and never roamed.</summary>
    public static string CoversFolder => Path.Combine(ApplicationData.Current.LocalFolder.Path, "covers");

    /// <summary>The WebView2 user data of the EPUB windows (task 4.16): cache and storage of a renderer that never reaches the network.</summary>
    public static string WebViewDataFolder => Path.Combine(ApplicationData.Current.LocalFolder.Path, "webview2");

    /// <summary>The EPUB reader's look: the reading theme, the typography, scroll or pages, the brightness and the appearance pair.</summary>
    public static string EpubLookPath => Path.Combine(ApplicationData.Current.LocalFolder.Path, "epub-look.json");

    /// <summary>The bookmarks and highlights of each EPUB, one file a publication, named by its content digest.</summary>
    public static string EpubMarksFolder => Path.Combine(ApplicationData.Current.LocalFolder.Path, "epub-marks");

    /// <summary>The highlights and notes of each text PDF, in the EPUB's record, one file a publication, named by its content digest.</summary>
    public static string PdfMarksFolder => Path.Combine(ApplicationData.Current.LocalFolder.Path, "pdf-marks");

    /// <summary>Written when the reader clears the library's records: the progress store is open, so its files go at the next start.</summary>
    public static string ClearRecordsMarker => Path.Combine(ApplicationData.Current.LocalFolder.Path, "clear-records.pending");

    /// <summary>
    /// Removes the library's records when the last run asked to clear them, before the store opens. A file that cannot be removed leaves the
    /// marker in place, so the next start tries again.
    /// </summary>
    public static void ApplyPendingRecordsClear()
    {
        if (!File.Exists(ClearRecordsMarker))
        {
            return;
        }

        try
        {
            foreach (var path in new[] { ProgressPath, ProgressPath + "-wal", ProgressPath + "-shm", ShelvesPath, PinnedShelvesPath, ShelfEditsPath })
            {
                File.Delete(path);
            }

            File.Delete(ClearRecordsMarker);
        }
        catch (Exception error) when (error is IOException or UnauthorizedAccessException)
        {
            // Left for the next start.
        }
    }

    public static string? Read(string path)
    {
        try
        {
            return File.Exists(path) ? File.ReadAllText(path) : null;
        }
        catch (Exception error) when (error is IOException or UnauthorizedAccessException)
        {
            return null;
        }
    }

    public static bool Write(string path, string text)
    {
        try
        {
            File.WriteAllText(path, text);
            return true;
        }
        catch (Exception error) when (error is IOException or UnauthorizedAccessException)
        {
            return false;
        }
    }
}
