using StoryArc.Interop.Playback;

namespace StoryArc.Interop.Tests.Playback;

/// <summary>
/// Where a listening position is written (audio-playback), the coverless well of the player, and an audiobook's chapters on
/// its page before it plays (audio-playback, "Chapters before the first minute").
/// </summary>
public sealed class ListeningWritesTests
{
    private static readonly IReadOnlyList<PlaybackChapter> Chapters =
    [
        new("One", TimeSpan.Zero, TimeSpan.FromMinutes(10)),
        new("Two", TimeSpan.FromMinutes(10), TimeSpan.FromMinutes(10)),
        new("Three", TimeSpan.FromMinutes(20), TimeSpan.FromMinutes(10)),
    ];

    private static (PlayerModel Model, List<string> Writes, List<TimeSpan> Moves) Playing()
    {
        var model = new PlayerModel();
        model.Start(new PlaybackItem(@"C:\Books\A Book.m4b", "A Book", null, null, Chapters, TimeSpan.FromMinutes(30), PlaybackKind.Narrated), TimeSpan.FromMinutes(5));
        var writes = new List<string>();
        var moves = new List<TimeSpan>();
        model.WriteDue += () => writes.Add(PlayerModel.Clock(model.Position));
        model.SoughtTo += moves.Add;
        return (model, writes, moves);
    }

    [Fact]
    public void A_pause_a_skip_a_chapter_and_a_scrub_let_go_each_write_once_and_the_engine_follows_each_move()
    {
        var (model, writes, moves) = Playing();

        model.Pause();
        model.Pause();
        Assert.Equal(new[] { "5:00" }, writes);

        model.Resume();
        model.SkipForward();
        model.NextChapter();
        Assert.Equal(new[] { "5:00", "5:30", "10:00" }, writes);
        Assert.Equal(new[] { TimeSpan.FromMinutes(5.5), TimeSpan.FromMinutes(10) }, moves);

        // A drag on the scrub control moves the engine and writes nothing until it is let go.
        model.Seek(TimeSpan.FromMinutes(12), settled: false);
        model.Seek(TimeSpan.FromMinutes(13), settled: false);
        Assert.Equal(3, writes.Count);
        model.SeekSettled();
        Assert.Equal("13:00", writes[^1]);
        Assert.Equal(TimeSpan.FromMinutes(13), moves[^1]);
    }

    [Fact]
    public void A_book_left_playing_is_written_every_fifteen_seconds_of_audio_and_not_while_paused()
    {
        var (model, writes, moves) = Playing();
        var at = TimeSpan.FromMinutes(5);
        for (var tick = 0; tick < 64; tick++)
        {
            at += TimeSpan.FromMilliseconds(500);
            model.PositionReported(at, TimeSpan.FromMilliseconds(500));
        }

        Assert.Equal(new[] { "5:15", "5:30" }, writes);
        Assert.Empty(moves);

        model.Pause();
        Assert.Equal(3, writes.Count);
        for (var tick = 0; tick < 64; tick++)
        {
            model.PositionReported(at, TimeSpan.FromMilliseconds(500));
        }

        Assert.Equal(3, writes.Count);

        // The cadence starts again from a write the listener caused.
        model.Resume();
        for (var tick = 0; tick < 29; tick++)
        {
            at += TimeSpan.FromMilliseconds(500);
            model.PositionReported(at, TimeSpan.FromMilliseconds(500));
        }

        Assert.Equal(3, writes.Count);
    }

    [Fact]
    public void A_stopped_session_writes_nothing_more()
    {
        var (model, writes, _) = Playing();
        model.Stop();

        model.Seek(TimeSpan.FromMinutes(1));
        model.PositionReported(TimeSpan.FromMinutes(2), TimeSpan.FromMinutes(1));

        Assert.Empty(writes);
        Assert.Equal(TimeSpan.FromMinutes(5), model.LastRecordedPosition);
    }

    [Fact]
    public void A_book_with_no_cover_shows_its_kind_over_its_format_and_never_its_title()
    {
        var narrated = PlayerArtwork.Of(new PlaybackItem(@"C:\Books\A Book.m4b", "A Book", null, null, [], TimeSpan.FromMinutes(1), PlaybackKind.Narrated));
        var spoken = PlayerArtwork.Of(new PlaybackItem("/books/Essays.epub", "Essays", null, null, [], TimeSpan.FromMinutes(1), PlaybackKind.ReadAloud));

        Assert.Equal(new PlayerArtwork(PlaybackKind.Narrated, "M4B"), narrated);
        Assert.Equal(new PlayerArtwork(PlaybackKind.ReadAloud, "EPUB"), spoken);
        Assert.DoesNotContain("Book", narrated.FormatName, StringComparison.Ordinal);
    }

    [Fact]
    public void The_page_lists_the_chapters_with_their_marks_and_names_the_chapter_it_resumes_inside()
    {
        var started = AudiobookDetail.Of(Chapters, TimeSpan.FromMinutes(30), TimeSpan.FromMinutes(12));

        Assert.True(started.ListsChapters);
        Assert.Equal(new[] { ChapterMark.Finished, ChapterMark.InProgress, ChapterMark.NotReached }, started.Rows.Select(row => row.Mark));
        Assert.Equal(TimeSpan.FromMinutes(8), started.Rows[1].Remaining);
        Assert.Equal(TimeSpan.FromMinutes(10), started.Rows[2].Duration);
        Assert.Equal("Continue Two", started.PrimaryLabel("Listen", "Continue {0}", "Continue listening"));

        var fresh = AudiobookDetail.Of(Chapters, TimeSpan.FromMinutes(30), null);
        Assert.All(fresh.Rows, row => Assert.Equal(ChapterMark.NotReached, row.Mark));
        Assert.Equal("Listen", fresh.PrimaryLabel("Listen", "Continue {0}", "Continue listening"));
    }

    [Fact]
    public void A_book_of_one_part_states_its_length_and_offers_no_list()
    {
        var single = AudiobookDetail.Of([], TimeSpan.FromMinutes(42), TimeSpan.FromMinutes(3));

        Assert.False(single.ListsChapters);
        Assert.Equal(TimeSpan.FromMinutes(42), single.Duration);
        Assert.Equal("Continue listening", single.PrimaryLabel("Listen", "Continue {0}", "Continue listening"));
        Assert.False(AudiobookDetail.Of([new("All", TimeSpan.Zero, TimeSpan.FromMinutes(42))], TimeSpan.FromMinutes(42), null).ListsChapters);
    }
}
