using StoryArc.Interop.Reader;

namespace StoryArc.Interop.Tests.Reader;

/// <summary>The drag threshold (desktop-clients task 2.40, after 2.15; desktop-experience "Dragging to turn a page").</summary>
public sealed class DragTurnTests
{
    [Theory]
    [InlineData(-48, false, 1)]
    [InlineData(-200, false, 1)]
    [InlineData(48, false, -1)]
    [InlineData(-47, false, 0)]
    [InlineData(47, false, 0)]
    [InlineData(0, false, 0)]
    [InlineData(-48, true, -1)]
    [InlineData(48, true, 1)]
    public void A_drag_past_the_threshold_turns_in_its_direction_and_mirrors_right_to_left(double travel, bool isRightToLeft, int expected)
    {
        Assert.Equal(expected, DragTurn.ReadingStep(travel, isRightToLeft));
    }

    [Fact]
    public void A_page_follows_the_pointer_and_never_leaves_the_window()
    {
        Assert.Equal(-30, DragTurn.Travel(-30, 800));
        Assert.Equal(-800, DragTurn.Travel(-5000, 800));
        Assert.Equal(800, DragTurn.Travel(5000, 800));
    }
}
