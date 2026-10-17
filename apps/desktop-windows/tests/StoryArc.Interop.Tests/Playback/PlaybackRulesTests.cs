using StoryArc.Interop.Playback;

namespace StoryArc.Interop.Tests.Playback;

/// <summary>The session, speed, skip and sleep rules of desktop-clients task 4.20, mirrored from StoryArcKit's Playback module.</summary>
public sealed class PlaybackRulesTests
{
    [Fact]
    public void A_listeners_pause_survives_an_interruption_ending_and_an_interruption_may_resume()
    {
        var playing = new PlaybackSession().Started();

        var byListener = playing.PausedByListener();
        Assert.Equal(InterruptionOutcome.Nothing, byListener.EndingInterruption(mayResume: true));
        Assert.Equal(byListener, byListener.InterruptionEnded(mayResume: true));

        var interrupted = playing.Interrupted();
        Assert.Equal(PauseCause.Interruption, interrupted.Cause);
        Assert.Equal(InterruptionOutcome.Resume, interrupted.EndingInterruption(mayResume: true));
        Assert.True(interrupted.InterruptionEnded(mayResume: true).IsPlaying);
        Assert.Equal(InterruptionOutcome.Lost, interrupted.EndingInterruption(mayResume: false));
        Assert.False(interrupted.InterruptionEnded(mayResume: false).IsActive);

        Assert.Equal(byListener, byListener.Interrupted());
        Assert.False(new PlaybackSession().PausedByListener().IsActive);
    }

    [Fact]
    public void Speed_is_clamped_to_the_range_and_stated_as_a_number()
    {
        Assert.Equal(0.5, PlaybackSpeed.Clamp(0.1));
        Assert.Equal(3.0, PlaybackSpeed.Clamp(9));
        Assert.Equal(1.0, PlaybackSpeed.Clamp(double.NaN));
        Assert.Equal("1", PlaybackSpeed.Label(1));
        Assert.Equal("1.5", PlaybackSpeed.Label(1.5).Replace(',', '.'));
        Assert.Equal(0.5, PlaybackSpeed.Offered[0]);
        Assert.Equal(3.0, PlaybackSpeed.Offered[^1]);
        Assert.Equal(2.0, PlaybackSpeed.SpeakingRate(2.0));
    }

    [Fact]
    public void A_skip_crosses_a_chapter_boundary_and_stops_at_the_ends_of_the_book()
    {
        var total = TimeSpan.FromMinutes(10);

        Assert.Equal(TimeSpan.FromSeconds(10), Skips.Apply(TimeSpan.FromSeconds(25), -Skips.Back, total));
        Assert.Equal(TimeSpan.Zero, Skips.Apply(TimeSpan.FromSeconds(5), -Skips.Back, total));
        Assert.Equal(total, Skips.Apply(total - TimeSpan.FromSeconds(10), Skips.Forward, total));
        Assert.Equal(TimeSpan.FromSeconds(15), Skips.Back);
        Assert.Equal(TimeSpan.FromSeconds(30), Skips.Forward);

        var chapters = new List<PlaybackChapter>
        {
            new("One", TimeSpan.Zero, TimeSpan.FromMinutes(4)),
            new("Two", TimeSpan.FromMinutes(4), TimeSpan.FromMinutes(6)),
        };
        Assert.Equal(0, Skips.ChapterAt(chapters, TimeSpan.FromMinutes(3.9)));
        Assert.Equal(1, Skips.ChapterAt(chapters, TimeSpan.FromMinutes(4)));
        Assert.Equal(1, Skips.ChapterAt(chapters, total));
        Assert.Null(Skips.ChapterAt([], TimeSpan.Zero));
    }

    [Fact]
    public void The_sleep_countdown_fades_over_its_last_thirty_seconds_and_records_a_little_before_the_end()
    {
        var countdown = SleepCountdown.Of(new SleepTimer(TimeSpan.FromMinutes(5)), untilChapterEnd: null);

        Assert.NotNull(countdown);
        Assert.Equal(1, countdown.Gain());
        var late = countdown.Advanced(TimeSpan.FromMinutes(5) - TimeSpan.FromSeconds(15), untilChapterEnd: null);
        Assert.Equal(0.5, late.Gain(), 3);
        Assert.False(late.HasElapsed);
        var over = late.Advanced(TimeSpan.FromSeconds(15), untilChapterEnd: null);
        Assert.True(over.HasElapsed);
        Assert.Equal(0, over.Gain());

        Assert.Equal(TimeSpan.FromSeconds(90), SleepCountdown.RecordedPosition(TimeSpan.FromSeconds(120)));
        Assert.Equal(TimeSpan.Zero, SleepCountdown.RecordedPosition(TimeSpan.FromSeconds(10)));
        Assert.Equal(new[] { 5, 15, 30, 45, 60 }, SleepTimer.Durations.Select(duration => (int)duration.TotalMinutes));
    }

    [Fact]
    public void End_of_chapter_is_re_read_from_the_audio_and_cannot_be_set_with_no_chapter_to_end()
    {
        Assert.Null(SleepCountdown.Of(SleepTimer.EndOfChapter, untilChapterEnd: null));
        Assert.Null(SleepCountdown.Of(SleepTimer.EndOfChapter, untilChapterEnd: TimeSpan.Zero));

        var countdown = SleepCountdown.Of(SleepTimer.EndOfChapter, TimeSpan.FromMinutes(2));
        Assert.NotNull(countdown);
        var later = countdown.Advanced(TimeSpan.FromSeconds(1), untilChapterEnd: TimeSpan.FromSeconds(5));
        Assert.Equal(TimeSpan.FromSeconds(5), later.Remaining);
        Assert.Equal(0.5, later.Gain(SleepCountdown.VoiceFade), 3);
    }
}
