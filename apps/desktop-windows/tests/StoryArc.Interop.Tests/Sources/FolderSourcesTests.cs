using StoryArc.Interop.Sources;

namespace StoryArc.Interop.Tests.Sources;

/// <summary>
/// Folder sources (task 2.43): the stored list that survives a relaunch, the states a scan leaves a
/// source in (an unplugged volume is offline, a withdrawn folder needs access), the schedule that
/// turns a burst of changes into one rescan within ten seconds and polls a folder it cannot watch,
/// and a rescan of the corpus through the core.
/// </summary>
public sealed class FolderSourcesTests
{
    [Fact]
    public void A_chosen_folder_is_stored_once_and_survives_a_relaunch()
    {
        var list = FolderSourceList.Empty.Adding(@"/data/Comics/").Adding("/data/Comics").Adding("/data/Manga");

        var restored = FolderSourceList.Restore(list.Save());

        Assert.Equal(2, restored.Sources.Count);
        Assert.Equal("Comics", restored.Sources[0].Name);
        Assert.Equal(list.Sources, restored.Sources);
        Assert.Equal(list.Sources[0].Id, FolderSourceList.Empty.Adding("/data/Comics").Sources[0].Id);
    }

    [Fact]
    public void A_removed_folder_leaves_and_a_damaged_file_is_no_folders()
    {
        var list = FolderSourceList.Empty.Adding("/a").Adding("/b");

        Assert.Equal("/b", Assert.Single(list.Without(list.Sources[0].Id).Sources).Path);
        Assert.Empty(FolderSourceList.Restore("not json").Sources);
    }

    [Theory]
    [InlineData(null, true, FolderAvailability.Available)]
    [InlineData(StoryArcStatus.NotFound, false, FolderAvailability.Offline)]
    [InlineData(StoryArcStatus.NotFound, true, FolderAvailability.NeedsAccess)]
    [InlineData(StoryArcStatus.Storage, true, FolderAvailability.NeedsAccess)]
    public void A_scan_leaves_the_source_available_offline_or_needing_access(StoryArcStatus? failure, bool volume, FolderAvailability expected)
    {
        Assert.Equal(expected, FolderSourceList.Classify(failure, volume, FolderAvailability.Available));
    }

    [Fact]
    public void A_cancelled_scan_changes_nothing()
    {
        Assert.Equal(FolderAvailability.Offline, FolderSourceList.Classify(StoryArcStatus.Cancelled, false, FolderAvailability.Offline));
    }

    [Fact]
    public void A_burst_of_changes_is_one_rescan_after_a_quiet_moment()
    {
        var schedule = new RescanSchedule(isWatched: true, TimeSpan.Zero);
        Assert.False(schedule.IsDue(TimeSpan.FromMinutes(5)));

        for (var ms = 0; ms < 600; ms += 100)
        {
            schedule.Changed(TimeSpan.FromSeconds(10) + TimeSpan.FromMilliseconds(ms));
        }

        Assert.False(schedule.IsDue(TimeSpan.FromSeconds(10.6)));
        Assert.True(schedule.IsDue(TimeSpan.FromSeconds(11.6)));
        schedule.Scanned(TimeSpan.FromSeconds(11.6));
        Assert.False(schedule.IsDue(TimeSpan.FromSeconds(20)));
    }

    [Fact]
    public void A_folder_that_never_goes_quiet_is_still_scanned_within_ten_seconds()
    {
        var schedule = new RescanSchedule(isWatched: true, TimeSpan.Zero);
        var now = TimeSpan.Zero;
        while (!schedule.IsDue(now))
        {
            schedule.Changed(now);
            now += TimeSpan.FromMilliseconds(200);
        }

        Assert.True(now <= TimeSpan.FromSeconds(10));
    }

    [Fact]
    public void A_folder_that_cannot_be_watched_is_polled_and_scanned_on_focus()
    {
        var schedule = new RescanSchedule(isWatched: true, TimeSpan.Zero);
        schedule.WatchingStopped();

        Assert.False(schedule.IsWatched);
        Assert.True(schedule.IsDue(RescanSchedule.PollInterval));
        Assert.True(RescanSchedule.PollInterval <= TimeSpan.FromSeconds(10));
        schedule.Scanned(TimeSpan.FromSeconds(10));

        schedule.Focused(TimeSpan.FromSeconds(12));
        Assert.True(schedule.IsDue(TimeSpan.FromSeconds(13)));
    }

    [Fact]
    public void A_file_added_to_a_folder_appears_in_the_next_scan_through_the_core()
    {
        using var folder = Corpus.TemporaryFolder();
        folder.Copy("comics/single-page.cbz");
        using (var first = ComicFolder.Open(folder.FullPath))
        {
            Assert.Single(first.Records());
        }

        folder.Copy("comics/zip64.cbz");
        using var second = ComicFolder.Open(folder.FullPath);

        Assert.Equal(2, second.Records().Count);
    }

    [Fact]
    public void An_unplugged_folder_is_not_found_by_the_core_and_classified_offline()
    {
        var missing = Path.Combine(Path.GetTempPath(), "storyarc-unplugged-" + Guid.NewGuid().ToString("N"), "Comics");

        var error = Assert.Throws<StoryArcException>(() => ComicFolder.Open(missing));

        Assert.Equal(FolderAvailability.Offline, FolderSourceList.Classify(error.Status, isVolumePresent: false, FolderAvailability.Available));
    }
}
