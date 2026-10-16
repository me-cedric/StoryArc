using StoryArc.Interop.SystemSettings;

namespace StoryArc.Interop.Tests.SystemSettings;

/// <summary>The keep-awake wrapper (desktop-clients task 2.46): held while in front, released after, silent on refusal.</summary>
public sealed class DisplayKeepAwakeTests
{
    [Fact]
    public void A_reader_in_front_holds_the_display_and_releases_it_when_it_is_not()
    {
        var calls = new List<uint>();
        var keepAwake = new DisplayKeepAwake(flags =>
        {
            calls.Add(flags);
            return DisplayKeepAwake.EsContinuous;
        });

        keepAwake.WindowIsInFront(true);
        keepAwake.WindowIsInFront(true);
        Assert.True(keepAwake.IsHeld);
        Assert.Equal<uint>([DisplayKeepAwake.EsContinuous | DisplayKeepAwake.EsDisplayRequired], calls);

        keepAwake.WindowIsInFront(false);
        Assert.False(keepAwake.IsHeld);
        Assert.Equal<uint>([DisplayKeepAwake.EsContinuous | DisplayKeepAwake.EsDisplayRequired, DisplayKeepAwake.EsContinuous], calls);
    }

    [Fact]
    public void A_refusal_is_silent_and_reading_goes_on()
    {
        var calls = 0;
        var keepAwake = new DisplayKeepAwake(_ =>
        {
            calls++;
            return 0;
        });

        keepAwake.Hold();

        Assert.False(keepAwake.IsHeld);
        Assert.True(keepAwake.WasRefused);
        Assert.Equal(1, calls);

        keepAwake.Release();
        Assert.Equal(1, calls);
        Assert.False(keepAwake.WasRefused);
    }

    [Fact]
    public void Releasing_what_was_never_held_asks_the_system_nothing()
    {
        var calls = 0;
        var keepAwake = new DisplayKeepAwake(_ =>
        {
            calls++;
            return DisplayKeepAwake.EsContinuous;
        });

        keepAwake.Release();

        Assert.Equal(0, calls);
    }

    [Fact]
    public void The_flags_are_the_documented_values()
    {
        Assert.Equal(0x80000000u, DisplayKeepAwake.EsContinuous);
        Assert.Equal(0x00000002u, DisplayKeepAwake.EsDisplayRequired);
        Assert.Equal(0x00000001u, DisplayKeepAwake.EsSystemRequired);
    }
}
