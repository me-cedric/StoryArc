using StoryArc.Interop.Playback;

namespace StoryArc.Interop.Tests.Playback;

/// <summary>The player view model of desktop-clients task 4.20: play and pause, skips, chapters, the sleep timer's fade, interruptions, and the end of a session.</summary>
public sealed class PlayerModelTests
{
    private static readonly IReadOnlyList<PlaybackChapter> Chapters =
    [
        new("One", TimeSpan.Zero, TimeSpan.FromMinutes(10)),
        new("Two", TimeSpan.FromMinutes(10), TimeSpan.FromMinutes(10)),
        new("Three", TimeSpan.FromMinutes(20), TimeSpan.FromMinutes(10)),
    ];

    private static PlaybackItem Book(string id = "book-1", PlaybackKind kind = PlaybackKind.Narrated) =>
        new(id, "A Book", "An Author", null, Chapters, TimeSpan.FromMinutes(30), kind);

    private static PlayerModel Playing(TimeSpan? at = null)
    {
        var model = new PlayerModel();
        model.Start(Book(), at ?? TimeSpan.Zero);
        return model;
    }

    [Fact]
    public void Starting_plays_and_the_transport_names_the_title_the_chapter_and_the_position()
    {
        var model = Playing(TimeSpan.FromMinutes(12));

        Assert.True(model.Session.IsPlaying);
        var transport = model.Transport();
        Assert.NotNull(transport);
        Assert.Equal(("A Book", "Two", TimeSpan.FromMinutes(12), TimeSpan.FromMinutes(30)), (transport.Title, transport.Subtitle, transport.Position, transport.Duration));
        Assert.True(transport.HasNext);
        Assert.True(transport.HasPrevious);
        Assert.Equal("A Book, Two", model.CompactLine("{0}, {1}"));
    }

    [Fact]
    public void A_publication_with_no_chapters_shows_the_author_on_the_second_line()
    {
        var model = new PlayerModel();
        model.Start(new PlaybackItem("p", "Essays", "Someone", null, [], TimeSpan.FromMinutes(5), PlaybackKind.ReadAloud), TimeSpan.Zero);

        var transport = model.Transport();
        Assert.NotNull(transport);
        Assert.Equal("Someone", transport.Subtitle);
        Assert.False(transport.HasNext);
        Assert.False(transport.HasPrevious);
        Assert.Empty(model.ChapterRows());
    }

    [Fact]
    public void Skips_move_by_the_fixed_intervals_and_chapter_moves_land_on_starts()
    {
        var model = Playing(TimeSpan.FromMinutes(10) + TimeSpan.FromSeconds(5));

        model.SkipBack();
        Assert.Equal(TimeSpan.FromMinutes(9) + TimeSpan.FromSeconds(50), model.Position);
        Assert.Equal(0, model.CurrentChapter);
        model.SkipForward();
        Assert.Equal(TimeSpan.FromMinutes(10) + TimeSpan.FromSeconds(20), model.Position);
        model.NextChapter();
        Assert.Equal(TimeSpan.FromMinutes(20), model.Position);
        model.NextChapter();
        Assert.Equal(TimeSpan.FromMinutes(20), model.Position);
        model.PreviousChapter();
        Assert.Equal(TimeSpan.FromMinutes(10), model.Position);
        model.Seek(TimeSpan.FromMinutes(15));
        model.PreviousChapter();
        Assert.Equal(TimeSpan.FromMinutes(10), model.Position);
    }

    [Fact]
    public void The_chapter_list_marks_finished_in_progress_with_what_is_left_and_not_reached()
    {
        var model = Playing(TimeSpan.FromMinutes(13));

        var rows = model.ChapterRows();

        Assert.Equal(new[] { ChapterMark.Finished, ChapterMark.InProgress, ChapterMark.NotReached }, rows.Select(row => row.Mark));
        Assert.Equal(TimeSpan.FromMinutes(7), rows[1].Remaining);
        Assert.Null(rows[0].Remaining);
    }

    [Fact]
    public void The_sleep_timer_fades_the_gain_and_ends_the_session_recording_a_little_before()
    {
        var model = Playing(TimeSpan.FromMinutes(5));
        model.SetSleep(new SleepTimer(TimeSpan.FromSeconds(40)));
        Assert.NotNull(model.Sleep);
        Assert.Equal(1, model.Gain);

        model.PositionReported(TimeSpan.FromMinutes(5) + TimeSpan.FromSeconds(25), TimeSpan.FromSeconds(25));
        Assert.Equal(0.5, model.Gain, 3);
        Assert.True(model.Session.IsPlaying);

        model.PositionReported(TimeSpan.FromMinutes(5) + TimeSpan.FromSeconds(40), TimeSpan.FromSeconds(15));
        Assert.False(model.IsActive);
        Assert.Equal(EndReason.SleepTimer, model.LastEnd);
        Assert.Equal(TimeSpan.FromMinutes(5) + TimeSpan.FromSeconds(10), model.LastRecordedPosition);
        Assert.Equal(1, model.Gain);
    }

    [Fact]
    public void A_voice_fades_in_a_shorter_window_and_end_of_chapter_follows_the_audio()
    {
        var model = new PlayerModel();
        model.Start(Book(kind: PlaybackKind.ReadAloud), TimeSpan.FromMinutes(9));
        model.SetSleep(SleepTimer.EndOfChapter);
        Assert.NotNull(model.Sleep);
        Assert.Equal(TimeSpan.FromMinutes(1), model.Sleep.Remaining);

        model.PositionReported(TimeSpan.FromMinutes(9) + TimeSpan.FromSeconds(55), TimeSpan.FromSeconds(55));
        Assert.Equal(0.5, model.Gain, 3);

        var paused = Playing();
        paused.Pause();
        paused.SetSleep(new SleepTimer(TimeSpan.FromSeconds(10)));
        paused.PositionReported(TimeSpan.Zero, TimeSpan.FromSeconds(30));
        Assert.True(paused.IsActive, "a paused session's timer does not run");
    }

    [Fact]
    public void An_interruption_resumes_by_itself_but_never_undoes_the_listeners_pause_and_audio_taken_for_good_ends_it()
    {
        var model = Playing(TimeSpan.FromMinutes(1));
        model.Interrupted();
        Assert.Equal(PauseCause.Interruption, model.Session.Cause);
        model.InterruptionEnded(mayResume: true);
        Assert.True(model.Session.IsPlaying);

        model.Pause();
        model.InterruptionEnded(mayResume: true);
        Assert.False(model.Session.IsPlaying);

        model.Resume();
        model.Interrupted();
        model.InterruptionEnded(mayResume: false);
        Assert.False(model.IsActive);
        Assert.Equal(EndReason.AudioLost, model.LastEnd);
        Assert.Equal(TimeSpan.FromMinutes(1), model.LastRecordedPosition);
        Assert.Null(model.Transport());
    }

    [Fact]
    public void Headphones_removed_pauses_as_the_listener_would_so_nothing_resumes_on_its_own()
    {
        var model = Playing();

        model.RouteLost();

        Assert.Equal(PauseCause.Listener, model.Session.Cause);
        model.InterruptionEnded(mayResume: true);
        Assert.False(model.Session.IsPlaying);
    }

    [Fact]
    public void Opening_a_different_publication_ends_the_session_at_its_position_and_says_so_once()
    {
        var model = Playing(TimeSpan.FromMinutes(2));
        var changes = 0;
        model.Changed += () => changes++;

        model.Start(Book("book-2"), TimeSpan.Zero);

        Assert.Equal(EndReason.Displaced, model.LastEnd);
        Assert.Equal(TimeSpan.FromMinutes(2), model.LastRecordedPosition);
        Assert.True(model.Session.IsPlaying);
        Assert.Equal("book-2", model.Item!.PublicationId);
        Assert.True(changes >= 1);

        model.Start(Book("book-2"), TimeSpan.FromMinutes(1));
        Assert.Equal(EndReason.None, model.LastEnd);
    }

    [Fact]
    public void The_transport_actions_drive_the_same_session_and_speed_is_kept_across_a_restart()
    {
        var model = Playing();
        model.SetSpeed(1.5);

        model.Do(TransportAction.Pause);
        Assert.False(model.Session.IsPlaying);
        model.Do(TransportAction.Play);
        Assert.True(model.Session.IsPlaying);
        model.Do(TransportAction.SkipForward);
        Assert.Equal(TimeSpan.FromSeconds(30), model.Position);
        model.Do(TransportAction.NextChapter);
        Assert.Equal(TimeSpan.FromMinutes(10), model.Position);
        model.Do(TransportAction.Stop);
        Assert.False(model.IsActive);
        Assert.Equal(EndReason.Stopped, model.LastEnd);

        model.Start(Book(), TimeSpan.Zero);
        Assert.Equal(1.5, model.Speed);
        Assert.Equal(3.0, new PlayerModel().Speed + 2);
    }

    [Fact]
    public void The_clock_states_minutes_and_seconds_and_hours_past_one()
    {
        Assert.Equal("0:05", PlayerModel.Clock(TimeSpan.FromSeconds(5)));
        Assert.Equal("12:07", PlayerModel.Clock(TimeSpan.FromMinutes(12) + TimeSpan.FromSeconds(7)));
        Assert.Equal("1:02:03", PlayerModel.Clock(new TimeSpan(1, 2, 3)));
        Assert.Equal("0:00", PlayerModel.Clock(TimeSpan.FromSeconds(-3)));
    }
}
