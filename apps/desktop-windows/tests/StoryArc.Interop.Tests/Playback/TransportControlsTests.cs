using StoryArc.Interop.Playback;

namespace StoryArc.Interop.Tests.Playback;

/// <summary>
/// Media keys and the system overlay (desktop-clients task 4.19) over a fake transport: the entry shows title, cover and
/// position while a session exists, leaves when it ends, and the keys are not taken while nothing plays.
/// </summary>
public sealed class TransportControlsTests
{
    private sealed class FakeTransport : ISystemTransport
    {
        public List<TransportState> Shown { get; } = [];

        public int Hidden { get; private set; }

        public bool IsEnabled { get; private set; }

        public void Show(TransportState state)
        {
            IsEnabled = true;
            Shown.Add(state);
        }

        public void Hide()
        {
            IsEnabled = false;
            Hidden++;
        }
    }

    private static TransportState State(TimeSpan? position = null, bool hasNext = true) =>
        new("Moby-Dick", "Chapter 3", "C:\\covers\\moby.jpg", position ?? TimeSpan.FromSeconds(61), TimeSpan.FromHours(2), 1.0, IsPlaying: true, hasNext, HasPrevious: true);

    [Fact]
    public void The_entry_shows_title_cover_and_position_while_a_session_exists_and_leaves_when_it_ends()
    {
        var system = new FakeTransport();
        var controls = new TransportControls(system);
        var session = new PlaybackSession().Started();

        controls.SessionChanged(session, State());

        var shown = Assert.Single(system.Shown);
        Assert.Equal(("Moby-Dick", "Chapter 3", "C:\\covers\\moby.jpg", TimeSpan.FromSeconds(61)), (shown.Title, shown.Subtitle, shown.CoverPath, shown.Position));
        Assert.True(system.IsEnabled);

        controls.SessionChanged(session.PausedByListener(), State());
        Assert.False(system.Shown[^1].IsPlaying);

        controls.SessionChanged(session.Stopped(), state: null);
        Assert.False(system.IsEnabled);
        Assert.Equal(1, system.Hidden);
        Assert.False(controls.IsShown);
    }

    [Fact]
    public void While_nothing_plays_the_keys_are_left_to_whoever_holds_them()
    {
        var system = new FakeTransport();
        var controls = new TransportControls(system);

        controls.SessionChanged(new PlaybackSession(), state: null);

        Assert.False(system.IsEnabled);
        Assert.Empty(system.Shown);
        Assert.Equal(0, system.Hidden);
        Assert.Equal(TransportAction.None, controls.ButtonPressed(TransportButton.Play));
        Assert.Null(controls.SeekRequested(TimeSpan.FromMinutes(1)));
    }

    [Fact]
    public void Each_key_maps_to_the_players_action_and_next_is_nothing_at_the_last_chapter()
    {
        var controls = new TransportControls(new FakeTransport());
        controls.SessionChanged(new PlaybackSession().Started(), State(hasNext: false));

        Assert.Equal(TransportAction.Pause, controls.ButtonPressed(TransportButton.Pause));
        Assert.Equal(TransportAction.Play, controls.ButtonPressed(TransportButton.Play));
        Assert.Equal(TransportAction.Stop, controls.ButtonPressed(TransportButton.Stop));
        Assert.Equal(TransportAction.None, controls.ButtonPressed(TransportButton.Next));
        Assert.Equal(TransportAction.PreviousChapter, controls.ButtonPressed(TransportButton.Previous));
        Assert.Equal(TransportAction.SkipForward, controls.ButtonPressed(TransportButton.FastForward));
        Assert.Equal(TransportAction.SkipBack, controls.ButtonPressed(TransportButton.Rewind));
    }

    [Fact]
    public void A_seek_in_the_overlay_stays_inside_the_timeline()
    {
        var controls = new TransportControls(new FakeTransport());
        controls.SessionChanged(new PlaybackSession().Started(), State());

        Assert.Equal(TimeSpan.FromMinutes(30), controls.SeekRequested(TimeSpan.FromMinutes(30)));
        Assert.Equal(TimeSpan.Zero, controls.SeekRequested(TimeSpan.FromSeconds(-4)));
        Assert.Equal(TimeSpan.FromHours(2), controls.SeekRequested(TimeSpan.FromHours(3)));
    }

    [Fact]
    public void The_timeline_is_refreshed_once_a_second_not_once_a_tick()
    {
        var system = new FakeTransport();
        var controls = new TransportControls(system);
        controls.SessionChanged(new PlaybackSession().Started(), State(TimeSpan.FromSeconds(10)));

        controls.PositionChanged(TimeSpan.FromSeconds(10.25));
        controls.PositionChanged(TimeSpan.FromSeconds(10.5));
        controls.PositionChanged(TimeSpan.FromSeconds(10.75));
        Assert.Single(system.Shown);

        controls.PositionChanged(TimeSpan.FromSeconds(11));
        Assert.Equal(2, system.Shown.Count);
        Assert.Equal(TimeSpan.FromSeconds(11), system.Shown[^1].Position);
    }

    [Fact]
    public void The_same_state_twice_is_one_update_and_quit_takes_the_entry_down()
    {
        var system = new FakeTransport();
        var controls = new TransportControls(system);
        var session = new PlaybackSession().Started();

        controls.SessionChanged(session, State());
        controls.SessionChanged(session, State());
        Assert.Single(system.Shown);

        controls.Quit();
        Assert.Equal(1, system.Hidden);
        controls.Quit();
        Assert.Equal(1, system.Hidden);
    }
}
