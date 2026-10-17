using System.Globalization;

namespace StoryArc.Interop.Playback;

/// <summary>What the session is doing. Mirrors StoryArcKit <c>PlaybackState</c>.</summary>
public enum PlaybackState
{
    Idle,
    Playing,
    Paused,
}

/// <summary>Who paused: the listener, whose pause is never undone by the platform, or an interruption, which may resume by itself.</summary>
public enum PauseCause
{
    None,
    Listener,
    Interruption,
}

/// <summary>What the end of an interruption means (audio-playback, "Something else takes the audio").</summary>
public enum InterruptionOutcome
{
    /// <summary>Nothing changes: the listener had paused, or nothing was interrupted.</summary>
    Nothing,

    /// <summary>Playback carries on by itself.</summary>
    Resume,

    /// <summary>Audio was taken for good: the session ends and the position is recorded.</summary>
    Lost,
}

/// <summary>
/// The session's state, immutable, with the transitions StoryArcKit <c>PlaybackSession</c> defines:
/// a pause the listener made survives an interruption's end; an interruption that may not resume
/// ends the session rather than leaving it paused for ever.
/// </summary>
public sealed record PlaybackSession(PlaybackState State = PlaybackState.Idle, PauseCause Cause = PauseCause.None)
{
    public bool IsPlaying => State == PlaybackState.Playing;

    public bool IsActive => State != PlaybackState.Idle;

    public PlaybackSession Started() => new(PlaybackState.Playing);

    public PlaybackSession PausedByListener() => IsActive ? new(PlaybackState.Paused, PauseCause.Listener) : this;

    public PlaybackSession Interrupted() => IsPlaying ? new(PlaybackState.Paused, PauseCause.Interruption) : this;

    public PlaybackSession Resumed() => IsActive ? new(PlaybackState.Playing) : this;

    public InterruptionOutcome EndingInterruption(bool mayResume)
    {
        if (State != PlaybackState.Paused || Cause != PauseCause.Interruption)
        {
            return InterruptionOutcome.Nothing;
        }

        return mayResume ? InterruptionOutcome.Resume : InterruptionOutcome.Lost;
    }

    public PlaybackSession InterruptionEnded(bool mayResume) => EndingInterruption(mayResume) switch
    {
        InterruptionOutcome.Resume => Resumed(),
        InterruptionOutcome.Lost => Stopped(),
        _ => this,
    };

    public PlaybackSession Stopped() => new();
}

/// <summary>The player's speed, 0.5× to 3× (audio-playback, "Speed"), stated as a number.</summary>
public static class PlaybackSpeed
{
    public const double Slowest = 0.5;
    public const double Normal = 1.0;
    public const double Fastest = 3.0;

    /// <summary>The steps the speed control offers, the phones' set.</summary>
    public static readonly IReadOnlyList<double> Offered = [0.5, 0.75, 1.0, 1.25, 1.5, 1.75, 2.0, 2.5, 3.0];

    public static double Clamp(double rate) => double.IsNaN(rate) ? Normal : Math.Clamp(rate, Slowest, Fastest);

    /// <summary>The number the control states: <c>1</c>, <c>1.5</c>, <c>0.75</c>, in the reader's locale, for the <c>{0}×</c> string.</summary>
    public static string Label(double rate) => Clamp(rate).ToString("0.##", CultureInfo.CurrentCulture);

    /// <summary>
    /// The <c>SpeakingRate</c> of <c>SpeechSynthesizerOptions</c> for a speed: the engine's range is 0.5 to 6.0 with 1.0
    /// the voice's own pace, so the player's range maps one to one and is never clamped by the engine.
    /// </summary>
    public static double SpeakingRate(double rate) => Clamp(rate);
}

/// <summary>A sleep timer: a duration, or the end of the chapter (audio-playback, "Sleep timer").</summary>
public sealed record SleepTimer(TimeSpan? After)
{
    public static readonly SleepTimer EndOfChapter = new(After: null);

    /// <summary>The durations offered beside End of chapter, the phones' five.</summary>
    public static readonly IReadOnlyList<TimeSpan> Durations = [.. new[] { 5, 15, 30, 45, 60 }.Select(minutes => TimeSpan.FromMinutes(minutes))];

    public bool IsEndOfChapter => After is null;
}

/// <summary>
/// A sleep timer that is running and how much of it is left. A duration counts itself down; End of
/// chapter is re-read from where the audio has reached. The audio fades over the last
/// <see cref="Fade"/> seconds and the position written is <see cref="Rewind"/> before the end, so
/// resuming starts at the last thing the listener properly heard. Mirrors StoryArcKit <c>SleepCountdown</c>.
/// </summary>
public sealed record SleepCountdown(SleepTimer Timer, TimeSpan Remaining)
{
    public static readonly TimeSpan Fade = TimeSpan.FromSeconds(30);

    /// <summary>A voice can only change volume between sentences, so it fades in steps over a shorter window (D19).</summary>
    public static readonly TimeSpan VoiceFade = TimeSpan.FromSeconds(10);

    public static TimeSpan Rewind => Fade;

    public static readonly TimeSpan Tick = TimeSpan.FromMilliseconds(500);

    /// <summary>The countdown for <paramref name="timer"/>, or <c>null</c> when it cannot be honoured: End of chapter with no chapter end to reach.</summary>
    public static SleepCountdown? Of(SleepTimer timer, TimeSpan? untilChapterEnd)
    {
        if (timer.After is { } after)
        {
            return new SleepCountdown(timer, after);
        }

        return untilChapterEnd is { } left && left > TimeSpan.Zero ? new SleepCountdown(timer, left) : null;
    }

    public bool HasElapsed => Remaining <= TimeSpan.Zero;

    /// <summary>How loud the audio should be, 0 to 1: a straight ramp over the last <paramref name="window"/>, else full.</summary>
    public double Gain(TimeSpan? window = null)
    {
        var fade = window ?? Fade;
        if (Remaining >= fade)
        {
            return 1;
        }

        if (Remaining <= TimeSpan.Zero)
        {
            return 0;
        }

        return Math.Clamp(Remaining / fade, 0, 1);
    }

    /// <summary>The countdown a moment later: a duration by <paramref name="elapsed"/>, End of chapter from <paramref name="untilChapterEnd"/>.</summary>
    public SleepCountdown Advanced(TimeSpan elapsed, TimeSpan? untilChapterEnd) =>
        Timer.IsEndOfChapter
            ? this with { Remaining = untilChapterEnd ?? TimeSpan.Zero }
            : this with { Remaining = Remaining - elapsed };

    /// <summary>The time written when the fade ends, a little before where the audio stopped.</summary>
    public static TimeSpan RecordedPosition(TimeSpan stoppedAt) => stoppedAt < Rewind ? TimeSpan.Zero : stoppedAt - Rewind;
}

/// <summary>One chapter or part of what is playing, with its start in book time.</summary>
public sealed record PlaybackChapter(string Title, TimeSpan Start, TimeSpan Duration)
{
    public TimeSpan End => Start + Duration;
}

/// <summary>The skip intervals, fixed and stated on the control: fifteen seconds back, thirty forward (audio-playback, "Skipping").</summary>
public static class Skips
{
    public static readonly TimeSpan Back = TimeSpan.FromSeconds(15);
    public static readonly TimeSpan Forward = TimeSpan.FromSeconds(30);

    /// <summary>
    /// The book time after a skip from <paramref name="position"/> by <paramref name="delta"/>: a skip crosses a chapter
    /// boundary into the neighbouring one rather than stopping at it, and stops at the start and the end of the book.
    /// </summary>
    public static TimeSpan Apply(TimeSpan position, TimeSpan delta, TimeSpan total)
    {
        var target = position + delta;
        if (target < TimeSpan.Zero)
        {
            return TimeSpan.Zero;
        }

        return target > total ? total : target;
    }

    /// <summary>The chapter index that holds <paramref name="position"/>, or the last chapter at the very end; <c>null</c> for no chapters.</summary>
    public static int? ChapterAt(IReadOnlyList<PlaybackChapter> chapters, TimeSpan position)
    {
        if (chapters.Count == 0)
        {
            return null;
        }

        for (var index = chapters.Count - 1; index >= 0; index--)
        {
            if (position >= chapters[index].Start)
            {
                return index;
            }
        }

        return 0;
    }
}
