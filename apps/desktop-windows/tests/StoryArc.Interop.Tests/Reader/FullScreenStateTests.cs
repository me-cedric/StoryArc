using StoryArc.Interop.Reader;

namespace StoryArc.Interop.Tests.Reader;

/// <summary>Full screen reading (desktop-clients task 2.41; desktop-experience "Full screen reading").</summary>
public sealed class FullScreenStateTests
{
    [Fact]
    public void The_full_screen_key_enters_then_leaves()
    {
        var state = new FullScreenState(isSupported: true);

        Assert.Equal(FullScreenChange.Entered, state.Toggle());
        Assert.True(state.IsFullScreen);
        Assert.Equal(FullScreenChange.Left, state.Toggle());
        Assert.False(state.IsFullScreen);
    }

    [Fact]
    public void Escape_leaves_full_screen_and_does_nothing_in_a_window()
    {
        var state = new FullScreenState(isSupported: true);

        Assert.Equal(FullScreenChange.None, state.Escape());
        state.Toggle();
        Assert.Equal(FullScreenChange.Left, state.Escape());
        Assert.False(state.IsFullScreen);
    }

    [Fact]
    public void A_system_that_refuses_leaves_the_window_as_it_is_and_the_entry_grey()
    {
        var state = new FullScreenState(isSupported: false);

        Assert.Equal(FullScreenChange.None, state.Toggle());
        Assert.False(state.IsFullScreen);
        Assert.False(state.IsAvailable);
    }

    [Fact]
    public void A_presenter_that_did_not_take_full_screen_is_reported_as_a_refusal()
    {
        var state = new FullScreenState(isSupported: true);
        state.Toggle();

        state.Refused();

        Assert.False(state.IsFullScreen);
        Assert.False(state.IsAvailable);
    }

    [Fact]
    public void Leaving_always_works_even_after_a_refusal_of_the_next_entry()
    {
        var state = new FullScreenState(isSupported: true);
        state.Toggle();

        Assert.Equal(FullScreenChange.Left, state.Toggle());
        Assert.True(state.IsAvailable);
    }
}
