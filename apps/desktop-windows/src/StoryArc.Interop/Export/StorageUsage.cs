using StoryArc.Interop.Data;

namespace StoryArc.Interop.Export;

/// <summary>The three stores the storage page shows, each cleared on its own.</summary>
public enum StoreKind
{
    /// <summary>The publications downloaded from a source.</summary>
    Downloads,

    /// <summary>The cover cache.</summary>
    Covers,

    /// <summary>The library's records: reading positions and the lists the app keeps.</summary>
    Records,
}

/// <summary>What one store holds.</summary>
public sealed record StoreSize(StoreKind Kind, long Bytes);

/// <summary>The outcome of clearing one store: how much it freed, or why it could not, in the grey sentence the page shows.</summary>
public sealed record ClearResult(StoreKind Kind, long FreedBytes, string? Failure)
{
    public bool Succeeded => Failure is null;
}

/// <summary>
/// What the app keeps on disk and how to clear each part (desktop-clients task 3.23; desktop-experience, "Storage on a desktop"): the size of the
/// downloads, the cover cache and the library's records, each cleared on its own. The downloads and the covers are folders weighed by the core
/// (<c>storyarc_storage_bytes</c>); the records are the files the app keeps beside the progress store. Nothing here is in a roaming folder: the
/// caller passes folders under the package's local data, and a test holds them to that.
/// </summary>
/// <param name="downloads">The downloads folder.</param>
/// <param name="covers">The cover cache folder.</param>
/// <param name="records">Each file that holds the library's records: the progress store with its journal files, the shelves, the queue.</param>
public sealed class StorageUsage(string downloads, string covers, IReadOnlyList<string> records)
{
    /// <summary>The folders the downloads and the covers live in, and the files of the records, for the page to show where its data lives.</summary>
    public string DownloadsFolder => downloads;

    public string CoversFolder => covers;

    public IReadOnlyList<StoreSize> Measure() =>
    [
        new StoreSize(StoreKind.Downloads, StorageBytes.Of(downloads)),
        new StoreSize(StoreKind.Covers, StorageBytes.Of(covers)),
        new StoreSize(StoreKind.Records, records.Sum(WeighFile)),
    ];

    /// <summary>
    /// Clears one store. Downloads and covers remove the files in their folders and keep the folders; the records remove their files, which the app
    /// writes again when it next saves. A file that cannot be removed names the reason and everything else is still cleared: a failure is grey and
    /// nothing is half done silently.
    /// </summary>
    public ClearResult Clear(StoreKind kind)
    {
        var before = Measure().Single(size => size.Kind == kind).Bytes;
        string? failure = null;
        try
        {
            switch (kind)
            {
                case StoreKind.Downloads:
                    EmptyFolder(downloads);
                    break;
                case StoreKind.Covers:
                    EmptyFolder(covers);
                    break;
                default:
                    foreach (var file in records.Where(File.Exists))
                    {
                        File.Delete(file);
                    }

                    break;
            }
        }
        catch (Exception error) when (error is IOException or UnauthorizedAccessException)
        {
            failure = DiagnosticFile.Reason(error);
        }

        var after = Measure().Single(size => size.Kind == kind).Bytes;
        return new ClearResult(kind, Math.Max(0, before - after), failure);
    }

    private static long WeighFile(string path) => File.Exists(path) ? new FileInfo(path).Length : 0;

    private static void EmptyFolder(string folder)
    {
        if (!Directory.Exists(folder))
        {
            return;
        }

        foreach (var file in Directory.EnumerateFiles(folder))
        {
            File.Delete(file);
        }

        foreach (var directory in Directory.EnumerateDirectories(folder))
        {
            Directory.Delete(directory, recursive: true);
        }
    }
}
