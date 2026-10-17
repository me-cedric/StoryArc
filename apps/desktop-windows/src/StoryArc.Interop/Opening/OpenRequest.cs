namespace StoryArc.Interop.Opening;

/// <summary>Where a request to open files came from. Each one opens the same way; the origin decides only whether the library comes forward.</summary>
public enum OpenOrigin
{
    /// <summary>A cell, Home or the detail page of the library window.</summary>
    Library,

    /// <summary>Files dropped on a window.</summary>
    Drop,

    /// <summary>Paths on the command line, at launch or redirected from a second launch.</summary>
    CommandLine,

    /// <summary>A double click or Open With in Explorer: the <c>windows.fileTypeAssociation</c> activation.</summary>
    FileActivation,

    /// <summary>A recent item chosen in the Jump List.</summary>
    JumpList,

    /// <summary>The File menu's Open File picker.</summary>
    Picker,
}

/// <summary>Why a file was refused before the core was asked. The core names its own refusals (a damaged file, a codec).</summary>
public enum RefusalReason
{
    /// <summary>Moved, deleted, or on a volume that is not connected (desktop-experience, "A file that cannot be reached").</summary>
    NotFound,

    /// <summary>A CB7 archive, refused by name on every desktop as on a phone (<c>library_cell_cannotOpen_cb7</c>).</summary>
    Cb7,

    /// <summary>A file of a kind StoryArc does not read (<c>library_skipped_reason_unsupported___</c>).</summary>
    NotAFormat,
}

/// <summary>One file refused by name, with its reason, for the place where What could not be opened is shown.</summary>
public sealed record OpenRefusal(string Path, RefusalReason Reason)
{
    public string Name => System.IO.Path.GetFileName(Path);
}

/// <summary>
/// What a request to open some paths turns into: the files that open in reader windows, those past
/// the window limit (listed so the reader can open them from the library), the folders (offered as a
/// folder library, added only when the reader agrees) and the refusals by name.
/// </summary>
public sealed record OpenPlan(
    IReadOnlyList<string> Open,
    IReadOnlyList<string> Overflow,
    IReadOnlyList<string> Folders,
    IReadOnlyList<OpenRefusal> Refused)
{
    public bool IsEmpty => Open.Count == 0 && Overflow.Count == 0 && Folders.Count == 0 && Refused.Count == 0;
}

/// <summary>
/// Turning dropped files, command-line paths, a file activation or a Jump List item into an
/// <see cref="OpenPlan"/> (desktop-clients task 2.42; desktop-experience "Dropping files and folders
/// on the app" and "File associations and Open With"). Pure: the host passes what the file system
/// says. A file the plan lets through can still be refused by the core, which names the reason.
/// </summary>
public static class OpenRequest
{
    /// <summary>How many reader windows one request opens at most; the rest are listed.</summary>
    public const int WindowLimit = 8;

    /// <summary>The extensions StoryArc reads on every desktop (capability <c>publication-formats</c>).</summary>
    public static readonly IReadOnlySet<string> Readable = new HashSet<string>(StringComparer.OrdinalIgnoreCase)
    {
        ".cbz", ".cbr", ".cbt", ".epub", ".pdf", ".m4b", ".m4a", ".mp3", ".flac", ".ogg",
    };

    /// <summary>The audiobook extensions, which open in the player rather than a reader window (desktop-clients task 4.20).</summary>
    public static readonly IReadOnlySet<string> Audio = new HashSet<string>(StringComparer.OrdinalIgnoreCase) { ".m4b", ".m4a", ".mp3", ".flac", ".ogg" };

    /// <summary>The extensions the package claims in Explorer: the comics the core opens page by page in wave 2.</summary>
    public static readonly IReadOnlyList<string> Associated = [".cbz", ".cbr", ".cbt"];

    public static OpenPlan Plan(
        IEnumerable<string> paths,
        Func<string, bool> fileExists,
        Func<string, bool> directoryExists,
        int windowLimit = WindowLimit)
    {
        var open = new List<string>();
        var overflow = new List<string>();
        var folders = new List<string>();
        var refused = new List<OpenRefusal>();
        foreach (var path in paths.Where(path => !string.IsNullOrWhiteSpace(path)).Distinct(StringComparer.OrdinalIgnoreCase))
        {
            if (directoryExists(path))
            {
                folders.Add(path);
                continue;
            }

            var extension = System.IO.Path.GetExtension(path);
            if (string.Equals(extension, ".cb7", StringComparison.OrdinalIgnoreCase))
            {
                refused.Add(new OpenRefusal(path, RefusalReason.Cb7));
            }
            else if (!Readable.Contains(extension))
            {
                refused.Add(new OpenRefusal(path, RefusalReason.NotAFormat));
            }
            else if (!fileExists(path))
            {
                refused.Add(new OpenRefusal(path, RefusalReason.NotFound));
            }
            else if (open.Count < windowLimit)
            {
                open.Add(path);
            }
            else
            {
                overflow.Add(path);
            }
        }

        return new OpenPlan(open, overflow, folders, refused);
    }
}
