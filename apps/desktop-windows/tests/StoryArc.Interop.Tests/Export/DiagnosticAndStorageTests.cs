using StoryArc.Interop;
using StoryArc.Interop.Data;
using StoryArc.Interop.Export;
using StoryArc.Interop.Settings;
using StoryArc.Interop.Tests.Support;

namespace StoryArc.Interop.Tests.Export;

/// <summary>The diagnostic export and the storage page of desktop-clients task 3.23: the three save outcomes, the redaction, each store cleared on its own, and a full disk named.</summary>
public sealed class DiagnosticAndStorageTests
{
    private const string Password = "hunter2-p4ssw0rd";

    private static DiagnosticFacts Facts(int sources = 2) => new(
        "1.0.0",
        "0.1.0",
        "Windows 11",
        "fr-FR",
        AppSettings.Default with { SyncFolder = @"\\nas\sync" },
        DownloadsBytes: 1000,
        CoversBytes: 200,
        RecordsBytes: 30,
        sources,
        DownloadQueue.Empty,
        "Synced");

    [Fact]
    public void The_report_holds_the_phones_sections_and_a_count_of_sources_never_a_row_per_source()
    {
        var text = DiagnosticReport.Text(Facts(sources: 4), [Password]);

        foreach (var section in new[] { "[App]", "[Device]", "[Settings]", "[Downloads]", "[Storage]", "[Sources]", "[Sync]" })
        {
            Assert.Contains(section, text, StringComparison.Ordinal);
        }

        Assert.Contains("configured = 4", text, StringComparison.Ordinal);
        Assert.Contains("syncFolderChosen = true", text, StringComparison.Ordinal);
        Assert.DoesNotContain("nas", text, StringComparison.Ordinal);
    }

    [Fact]
    public void A_credential_and_a_host_name_are_redacted_wherever_they_could_have_come_from()
    {
        var sections = DiagnosticReport.Sections(Facts())
            .Append(new DiagnosticSection("Leak", [("address", $"smb://reader:{Password}@nas.local/comics"), ("token", Password)]))
            .ToList();

        var text = Diagnostics.Render(DiagnosticReport.Title, sections, [Password]);

        Assert.DoesNotContain(Password, text, StringComparison.Ordinal);
        Assert.DoesNotContain("nas.local", text, StringComparison.Ordinal);
    }

    [Fact]
    public void Saving_writes_the_file_the_reader_named_and_nothing_else_beside_it()
    {
        using var folder = Corpus.TemporaryFolder();
        var target = Path.Combine(folder.FullPath, "diagnostic.txt");

        var result = DiagnosticFile.Write("the text", target);

        Assert.Equal(ExportOutcome.Saved, result.Outcome);
        Assert.Equal(target, result.Location);
        Assert.Equal("the text", File.ReadAllText(target));
        Assert.Equal(new[] { target }, Directory.GetFileSystemEntries(folder.FullPath));
    }

    [Fact]
    public void Cancelling_the_save_dialog_writes_no_file()
    {
        using var folder = Corpus.TemporaryFolder();

        var result = DiagnosticFile.Write("the text", location: null);

        Assert.Equal(ExportOutcome.Cancelled, result.Outcome);
        Assert.Empty(Directory.GetFileSystemEntries(folder.FullPath));
    }

    [Fact]
    public void A_place_that_cannot_be_written_is_named_with_its_reason_and_nothing_is_written_elsewhere()
    {
        using var folder = Corpus.TemporaryFolder();
        var missing = Path.Combine(folder.FullPath, "no-such-folder", "diagnostic.txt");

        var absent = DiagnosticFile.Write("the text", missing);

        Assert.Equal(ExportOutcome.CannotWrite, absent.Outcome);
        Assert.Equal(missing, absent.Location);
        Assert.Equal("the folder does not exist", absent.Reason);

        // A name that is already a folder cannot be a file either, and the failed attempt leaves no temporary file behind.
        var occupied = Path.Combine(folder.FullPath, "taken");
        Directory.CreateDirectory(occupied);
        var blocked = DiagnosticFile.Write("the text", occupied);

        Assert.Equal(ExportOutcome.CannotWrite, blocked.Outcome);
        Assert.Equal(occupied, blocked.Location);
        Assert.Equal(new[] { occupied }, Directory.GetFileSystemEntries(folder.FullPath));
        Assert.Empty(Directory.GetFileSystemEntries(occupied));

        // The reader then picks another place, and that one is written.
        var another = DiagnosticFile.Write("the text", Path.Combine(folder.FullPath, "again.txt"));
        Assert.Equal(ExportOutcome.Saved, another.Outcome);
    }

    [Fact]
    public void A_name_the_system_does_not_allow_is_a_place_that_cannot_be_written()
    {
        var result = DiagnosticFile.Write("the text", "bad\0name.txt");

        Assert.Equal(ExportOutcome.CannotWrite, result.Outcome);
        Assert.Equal("the name is not allowed", result.Reason);
    }

    [Fact]
    public void Each_store_is_measured_and_cleared_on_its_own()
    {
        using var data = Corpus.TemporaryFolder();
        var downloads = Directory.CreateDirectory(Path.Combine(data.FullPath, "downloads")).FullName;
        var covers = Directory.CreateDirectory(Path.Combine(data.FullPath, "covers")).FullName;
        File.WriteAllBytes(Path.Combine(downloads, "a.cbz"), new byte[1000]);
        Directory.CreateDirectory(Path.Combine(downloads, "series"));
        File.WriteAllBytes(Path.Combine(downloads, "series", "b.cbz"), new byte[500]);
        File.WriteAllBytes(Path.Combine(covers, "c.png"), new byte[200]);
        var store = Path.Combine(data.FullPath, "progress.sqlite");
        var journal = store + "-wal";
        File.WriteAllBytes(store, new byte[30]);
        File.WriteAllBytes(journal, new byte[12]);
        var usage = new StorageUsage(downloads, covers, [store, journal, Path.Combine(data.FullPath, "gone.json")]);

        Assert.Equal(
            new[] { (StoreKind.Downloads, 1500L), (StoreKind.Covers, 200L), (StoreKind.Records, 42L) },
            usage.Measure().Select(size => (size.Kind, size.Bytes)));

        var clearedCovers = usage.Clear(StoreKind.Covers);
        Assert.True(clearedCovers.Succeeded);
        Assert.Equal(200, clearedCovers.FreedBytes);
        Assert.Equal(1500, usage.Measure()[0].Bytes);
        Assert.True(Directory.Exists(covers), "the folder stays, only its files go");

        var clearedDownloads = usage.Clear(StoreKind.Downloads);
        Assert.Equal(1500, clearedDownloads.FreedBytes);
        Assert.Empty(Directory.GetFileSystemEntries(downloads));
        Assert.Equal(42, usage.Measure()[2].Bytes);

        var clearedRecords = usage.Clear(StoreKind.Records);
        Assert.Equal(42, clearedRecords.FreedBytes);
        Assert.False(File.Exists(store));
    }

    [Fact]
    public void A_store_that_was_never_written_weighs_nothing_and_clears_without_complaint()
    {
        using var data = Corpus.TemporaryFolder();
        var usage = new StorageUsage(Path.Combine(data.FullPath, "downloads"), Path.Combine(data.FullPath, "covers"), []);

        Assert.All(usage.Measure(), size => Assert.Equal(0, size.Bytes));
        Assert.All(Enum.GetValues<StoreKind>(), kind => Assert.True(usage.Clear(kind).Succeeded));
    }

    [Fact]
    public void A_full_disk_is_recognised_from_the_system_and_from_the_core_so_the_app_names_it_and_offers_a_cache_to_clear()
    {
        Assert.True(DiskFull.Is(new IOException("full", unchecked((int)0x80070070))));
        Assert.True(DiskFull.Is(new IOException("full", unchecked((int)0x80070027))));
        Assert.True(DiskFull.Is(new StoryArcException("storyarc_download_fetch", StoryArcStatus.Storage, "the disk is full")));
        Assert.False(DiskFull.Is(new IOException("other", unchecked((int)0x80070005))));
        Assert.False(DiskFull.Is(new StoryArcException("storyarc_download_fetch", StoryArcStatus.Storage, "Credential Manager refused")));
        Assert.Equal("the disk is full", DiagnosticFile.Reason(new IOException("full", unchecked((int)0x80070070))));
    }
}
