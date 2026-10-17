using System.Globalization;
using StoryArc.Interop.Data;
using StoryArc.Interop.Settings;

namespace StoryArc.Interop.Export;

/// <summary>What the report states of this machine and this run. Every value is one the report may carry; a source's name, address and credential are not among them.</summary>
public sealed record DiagnosticFacts(
    string AppVersion,
    string CoreVersion,
    string Platform,
    string Locale,
    AppSettings Settings,
    long DownloadsBytes,
    long CoversBytes,
    long RecordsBytes,
    int SourcesConfigured,
    DownloadQueue Downloads,
    string SyncState);

/// <summary>
/// The diagnostic of a desktop (desktop-clients task 3.23; desktop-experience, "Exporting a diagnostic to a file"): the same sections the
/// phones' export holds, in English because it goes into a bug report, then rendered by the core, which removes every credential the vault
/// holds and every server host name, in every encoding. The sources section carries a count and never a row per source, because a source's
/// name is usually its host name and its address is where a credential could survive.
/// </summary>
public static class DiagnosticReport
{
    public const string Title = "StoryArc diagnostic";

    /// <summary>The sections, in the phones' order: app, device, settings, downloads, storage, sources, sync.</summary>
    public static IReadOnlyList<DiagnosticSection> Sections(DiagnosticFacts facts)
    {
        var settings = facts.Settings;
        var rows = facts.Downloads.Rows;
        return
        [
            new DiagnosticSection("App", [("version", facts.AppVersion), ("core", facts.CoreVersion)]),
            new DiagnosticSection("Device", [("platform", facts.Platform), ("deviceClass", "PC"), ("locale", facts.Locale)]),
            new DiagnosticSection("Settings",
            [
                ("appearance", settings.Appearance.ToString()),
                ("accent", settings.Accent.ToString()),
                ("transition", settings.Transition.ToString()),
                ("clickZones", Flag(settings.ClickZonesOn)),
                ("downloadsUnmeteredOnly", Flag(settings.DownloadsUnmeteredOnly)),
                ("syncFolderChosen", Flag(!string.IsNullOrEmpty(settings.SyncFolder))),
            ]),
            new DiagnosticSection("Downloads",
            [
                ("queued", Count(rows, DownloadStatus.Queued)),
                ("paused", Count(rows, DownloadStatus.Paused)),
                ("failed", Count(rows, DownloadStatus.Failed)),
                ("finished", Count(rows, DownloadStatus.Finished)),
            ]),
            new DiagnosticSection("Storage",
            [
                ("downloadsBytes", Bytes(facts.DownloadsBytes)),
                ("coversBytes", Bytes(facts.CoversBytes)),
                ("recordsBytes", Bytes(facts.RecordsBytes)),
            ]),
            new DiagnosticSection("Sources", [("configured", facts.SourcesConfigured.ToString(CultureInfo.InvariantCulture))]),
            new DiagnosticSection("Sync", [("state", facts.SyncState)]),
        ];
    }

    /// <summary>The report as text, every held credential and host name removed by the core. <paramref name="heldCredentials"/> are the credentials in the vault.</summary>
    public static string Text(DiagnosticFacts facts, IReadOnlyList<string> heldCredentials) =>
        Diagnostics.Render(Title, Sections(facts), heldCredentials);

    private static string Flag(bool value) => value ? "true" : "false";

    private static string Count(IReadOnlyList<DownloadRow> rows, DownloadStatus status) =>
        rows.Count(row => row.Status == status).ToString(CultureInfo.InvariantCulture);

    private static string Bytes(long value) => value.ToString(CultureInfo.InvariantCulture);
}

/// <summary>How saving the diagnostic ended.</summary>
public enum ExportOutcome
{
    /// <summary>The file is written where the reader chose.</summary>
    Saved,

    /// <summary>The reader cancelled the save dialog: no file is written and the text is not kept.</summary>
    Cancelled,

    /// <summary>The place cannot be written: named, another is offered, and nothing is written anywhere else.</summary>
    CannotWrite,
}

/// <param name="Location">The place the reader chose, named in the message when it cannot be written.</param>
/// <param name="Reason">Why it cannot be written, for the line that names the location.</param>
public sealed record ExportResult(ExportOutcome Outcome, string? Location, string? Reason);

/// <summary>
/// Writes the diagnostic to the file the reader named (the file save picker's answer). A <c>null</c> location is a cancel and writes nothing. A
/// place that cannot be written is named with its reason and writes nothing elsewhere: the text goes to a temporary file beside the target
/// first and moves into place, so a failure leaves no half-written file and no file anywhere the reader did not choose.
/// </summary>
public static class DiagnosticFile
{
    public static ExportResult Write(string text, string? location)
    {
        if (string.IsNullOrWhiteSpace(location))
        {
            return new ExportResult(ExportOutcome.Cancelled, null, null);
        }

        string? temporary = null;
        try
        {
            var full = Path.GetFullPath(location);
            var folder = Path.GetDirectoryName(full) ?? throw new DirectoryNotFoundException(full);
            if (!Directory.Exists(folder))
            {
                throw new DirectoryNotFoundException(folder);
            }

            temporary = Path.Combine(folder, "." + Path.GetFileName(full) + "." + Guid.NewGuid().ToString("N") + ".tmp");
            File.WriteAllText(temporary, text, new System.Text.UTF8Encoding(false));
            File.Move(temporary, full, overwrite: true);
            return new ExportResult(ExportOutcome.Saved, full, null);
        }
        catch (Exception error) when (error is IOException or UnauthorizedAccessException or ArgumentException or NotSupportedException)
        {
            return new ExportResult(ExportOutcome.CannotWrite, location, Reason(error));
        }
        finally
        {
            if (temporary is not null && File.Exists(temporary))
            {
                File.Delete(temporary);
            }
        }
    }

    /// <summary>The short reason, in plain words and not a stack: the folder is missing, access is refused, the disk is full, the name is not allowed.</summary>
    public static string Reason(Exception error) => error switch
    {
        DirectoryNotFoundException => "the folder does not exist",
        UnauthorizedAccessException => "access to it is refused",
        PathTooLongException => "the path is too long",
        IOException io when DiskFull.Is(io) => "the disk is full",
        ArgumentException or NotSupportedException => "the name is not allowed",
        _ => "it cannot be written",
    };
}

/// <summary>Whether a failed write means the disk is full, so the app says so in grey and offers to clear a cache.</summary>
public static class DiskFull
{
    // ERROR_HANDLE_DISK_FULL and ERROR_DISK_FULL, which Windows reports in the low word of an IOException's HResult; ENOSPC elsewhere.
    private const int HandleDiskFull = 0x27;
    private const int DiskFullError = 0x70;
    private const int NoSpace = 28;

    public static bool Is(Exception error)
    {
        var code = error.HResult & 0xFFFF;
        return error is IOException && (code is HandleDiskFull or DiskFullError || (error.HResult == NoSpace))
            || (error is StoryArcException core && core.Status == StoryArcStatus.Storage
                && core.CoreMessage?.Contains("full", StringComparison.OrdinalIgnoreCase) == true);
    }
}
