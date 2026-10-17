using StoryArc.Interop.Reader;

namespace StoryArc.Interop.Tests.Reader;

/// <summary>
/// Pointer reading (desktop-clients task 2.39, after 2.12): hover reveals the chrome, three seconds
/// of rest hide the chrome and the pointer, and the click zones are on when nothing is stored.
/// </summary>
public sealed class PointerReadingTests
{
    private static TimeSpan Seconds(double seconds) => TimeSpan.FromSeconds(seconds);

    [Fact]
    public void Moving_the_pointer_reveals_the_chrome_and_resting_three_seconds_hides_it_and_the_pointer()
    {
        var chrome = new HoverChrome();
        Assert.False(chrome.IsChromeVisible);

        chrome.PointerMoved(Seconds(0));
        Assert.True(chrome.IsChromeVisible);
        Assert.False(chrome.IsPointerHidden);
        Assert.Equal(Seconds(3), chrome.HideDueAt);

        Assert.False(chrome.Settle(Seconds(2.9)));
        Assert.True(chrome.IsChromeVisible);

        Assert.True(chrome.Settle(Seconds(3)));
        Assert.False(chrome.IsChromeVisible);
        Assert.True(chrome.IsPointerHidden);
        Assert.Null(chrome.HideDueAt);
    }

    [Fact]
    public void A_movement_before_the_delay_starts_the_rest_again()
    {
        var chrome = new HoverChrome();
        chrome.PointerMoved(Seconds(0));
        chrome.PointerMoved(Seconds(2));

        Assert.False(chrome.Settle(Seconds(3)));
        Assert.True(chrome.Settle(Seconds(5)));
    }

    [Fact]
    public void Focus_in_the_chrome_keeps_it_and_shows_the_pointer()
    {
        var chrome = new HoverChrome();
        chrome.PointerMoved(Seconds(0));
        chrome.Settle(Seconds(3));

        chrome.FocusInChrome(true, Seconds(4));
        Assert.True(chrome.IsChromeVisible);
        Assert.False(chrome.IsPointerHidden);
        Assert.False(chrome.Settle(Seconds(60)));

        chrome.FocusInChrome(false, Seconds(61));
        Assert.False(chrome.Settle(Seconds(63)));
        Assert.True(chrome.Settle(Seconds(64)));
    }

    [Fact]
    public void The_pointer_leaving_the_window_shows_it_again_and_stops_the_clock()
    {
        var chrome = new HoverChrome();
        chrome.PointerMoved(Seconds(0));
        chrome.Settle(Seconds(3));

        chrome.PointerLeft();

        Assert.False(chrome.IsPointerHidden);
        Assert.Null(chrome.HideDueAt);
    }

    [Fact]
    public void A_toggle_flips_the_chrome()
    {
        var chrome = new HoverChrome();
        chrome.Toggle(Seconds(0));
        Assert.True(chrome.IsChromeVisible);
        chrome.Toggle(Seconds(1));
        Assert.False(chrome.IsChromeVisible);
    }

    [Theory]
    [InlineData(10, false, PageAction.Previous)]
    [InlineData(500, false, PageAction.ToggleChrome)]
    [InlineData(990, false, PageAction.Next)]
    [InlineData(10, true, PageAction.Next)]
    [InlineData(990, true, PageAction.Previous)]
    [InlineData(500, true, PageAction.ToggleChrome)]
    public void A_click_on_an_edge_turns_and_a_click_in_the_middle_toggles_the_chrome(double x, bool isRightToLeft, PageAction expected)
    {
        Assert.Equal(expected, EdgeClickZones.Resolve(x, 1000, isRightToLeft, zonesOn: true));
    }

    [Fact]
    public void With_the_zones_off_every_click_toggles_the_chrome()
    {
        Assert.Equal(PageAction.ToggleChrome, EdgeClickZones.Resolve(10, 1000, false, zonesOn: false));
        Assert.Equal(PageAction.ToggleChrome, EdgeClickZones.Resolve(990, 1000, true, zonesOn: false));
    }

    [Fact]
    public void Each_edge_zone_is_a_third_of_the_width()
    {
        Assert.Equal(PageAction.Previous, EdgeClickZones.Resolve(333, 1000, false, zonesOn: true));
        Assert.Equal(PageAction.ToggleChrome, EdgeClickZones.Resolve(334, 1000, false, zonesOn: true));
        Assert.Equal(PageAction.ToggleChrome, EdgeClickZones.Resolve(666, 1000, false, zonesOn: true));
        Assert.Equal(PageAction.Next, EdgeClickZones.Resolve(667, 1000, false, zonesOn: true));
    }
}
