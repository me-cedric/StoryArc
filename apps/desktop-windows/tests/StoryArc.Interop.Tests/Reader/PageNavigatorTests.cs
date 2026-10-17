using StoryArc.Interop.Reader;

namespace StoryArc.Interop.Tests.Reader;

/// <summary>
/// The reader's place and what it shows (task 2.40): pairs by window shape with the cover alone,
/// the same page across a resize, the mirrored pair of a right-to-left publication, the odd last
/// page alone, a page found wide, the limits, and the pages to decode ahead.
/// </summary>
public sealed class PageNavigatorTests
{
    private static readonly Extent Wide = new(1400, 900);
    private static readonly Extent Narrow = new(800, 900);

    [Fact]
    public void A_wide_window_pairs_pages_with_the_cover_alone_and_a_narrow_one_shows_one()
    {
        var reader = new PageNavigator(5, isRightToLeft: false);

        reader.Resize(Wide);
        Assert.Equal(new[] { 0 }, reader.ScreenOrder());
        Assert.True(reader.Apply(PageAction.Next));
        Assert.Equal(new[] { 1, 2 }, reader.ScreenOrder());

        reader.Resize(Narrow);
        Assert.Equal(new[] { 1 }, reader.ScreenOrder());
        Assert.Equal(5, reader.Layout.Count);
    }

    [Fact]
    public void Narrowing_and_widening_keep_the_reader_on_the_same_page()
    {
        var reader = new PageNavigator(6, isRightToLeft: false, startPage: 2);
        reader.Resize(Narrow);
        Assert.Equal(new[] { 2 }, reader.ScreenOrder());

        reader.Resize(Wide);
        Assert.Equal(new[] { 1, 2 }, reader.ScreenOrder());
        Assert.Equal(2, reader.CurrentPage);

        reader.Resize(Narrow);
        Assert.Equal(new[] { 2 }, reader.ScreenOrder());
    }

    [Fact]
    public void A_right_to_left_pair_puts_the_leading_page_on_the_right()
    {
        var reader = new PageNavigator(5, isRightToLeft: true, startPage: 1);
        reader.Resize(Wide);

        Assert.Equal(new[] { 2, 1 }, reader.ScreenOrder());
    }

    [Fact]
    public void The_last_page_of_an_odd_count_shows_alone_with_no_blank_beside_it()
    {
        var reader = new PageNavigator(4, isRightToLeft: false);
        reader.Resize(Wide);

        Assert.True(reader.Apply(PageAction.Last));
        Assert.Equal(new[] { 3 }, reader.ScreenOrder());
        Assert.True(reader.IsAtLast);
    }

    [Fact]
    public void A_page_found_wide_stands_alone_and_a_declared_spread_does_from_the_start()
    {
        var reader = new PageNavigator(4, isRightToLeft: false);
        reader.Resize(Wide);
        reader.FoundWide(1);

        Assert.Equal(new Spread(1, null), reader.Layout[1]);
        Assert.Equal(new Spread(2, 3), reader.Layout[2]);

        var declared = new PageNavigator(3, isRightToLeft: false, declaredWide: [1]);
        declared.Resize(Wide);
        Assert.All(declared.Layout.Slots, slot => Assert.False(slot.IsPair));
    }

    [Fact]
    public void A_turn_at_either_end_does_nothing()
    {
        var reader = new PageNavigator(3, isRightToLeft: false);
        reader.Resize(Narrow);

        Assert.True(reader.IsAtFirst);
        Assert.False(reader.Apply(PageAction.Previous));
        Assert.False(reader.Apply(PageAction.First));
        Assert.True(reader.Apply(PageAction.Last));
        Assert.False(reader.Apply(PageAction.Next));
        Assert.Equal(2, reader.CurrentPage);
    }

    [Fact]
    public void The_pages_either_side_are_decoded_ahead_next_first()
    {
        var reader = new PageNavigator(7, isRightToLeft: false, startPage: 1);
        reader.Resize(Wide);

        Assert.Equal(new[] { 3, 4, 0 }, reader.Neighbours());
    }

    [Fact]
    public void Single_page_holds_one_page_whatever_the_width_and_two_pages_gives_the_pairs_back()
    {
        var reader = new PageNavigator(5, isRightToLeft: false, startPage: 2);
        reader.Resize(Wide);

        reader.ForceSinglePage(true);
        Assert.Equal(new[] { 2 }, reader.ScreenOrder());

        reader.ForceSinglePage(false);
        Assert.Equal(new[] { 1, 2 }, reader.ScreenOrder());
    }

    [Fact]
    public void A_start_page_past_the_end_is_clamped_and_an_empty_publication_shows_nothing()
    {
        Assert.Equal(2, new PageNavigator(3, false, startPage: 40).CurrentPage);

        var empty = new PageNavigator(0, false);
        Assert.Empty(empty.ScreenOrder());
        Assert.False(empty.Apply(PageAction.Next));
    }

    [Fact]
    public void Go_to_moves_to_the_slot_that_holds_the_page()
    {
        var reader = new PageNavigator(6, isRightToLeft: false);
        reader.Resize(Wide);

        Assert.True(reader.GoTo(4));
        Assert.Equal(new[] { 3, 4 }, reader.ScreenOrder());
        Assert.False(reader.GoTo(3));
    }
}
