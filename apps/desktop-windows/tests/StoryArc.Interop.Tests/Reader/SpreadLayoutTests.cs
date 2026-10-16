using StoryArc.Interop.Reader;

namespace StoryArc.Interop.Tests.Reader;

/// <summary>
/// The pairing rule (desktop-clients task 2.40, after 2.14) across odd and even counts, wide pages,
/// the offset, and the window shape. Scenarios of desktop-experience "Two-page spreads by window shape".
/// </summary>
public sealed class SpreadLayoutTests
{
    private static readonly IReadOnlySet<int> NoWidePages = new HashSet<int>();

    private static IReadOnlyList<int[]> Pages(SpreadLayout layout) =>
        layout.Slots.Select(spread => spread.Pages.ToArray()).ToList();

    [Fact]
    public void Single_puts_every_page_on_its_own()
    {
        var layout = SpreadLayout.Single(3);

        Assert.Equal(3, layout.Count);
        Assert.False(layout.HasPairs);
        Assert.Equal(2, layout.SlotContaining(2));
        Assert.Empty(SpreadLayout.Single(0).Slots);
    }

    [Fact]
    public void An_even_count_pairs_every_page()
    {
        var layout = SpreadLayout.Paired(4, NoWidePages, isOffset: false);

        Assert.Equal<int[]>([[0, 1], [2, 3]], Pages(layout));
        Assert.True(layout.HasPairs);
        Assert.Equal(1, layout.SlotContaining(3));
    }

    [Fact]
    public void The_last_page_of_an_odd_count_shows_alone()
    {
        var layout = SpreadLayout.Paired(5, NoWidePages, isOffset: false);

        Assert.Equal<int[]>([[0, 1], [2, 3], [4]], Pages(layout));
        Assert.False(layout.Slots[2].IsPair);
    }

    [Fact]
    public void With_the_offset_the_cover_stands_alone_on_the_first_screen()
    {
        var layout = SpreadLayout.Paired(5, NoWidePages, isOffset: true);

        Assert.Equal<int[]>([[0], [1, 2], [3, 4]], Pages(layout));
    }

    [Fact]
    public void A_wide_page_stands_alone_and_so_does_the_page_it_would_have_paired_with()
    {
        var layout = SpreadLayout.Paired(6, new HashSet<int> { 3 }, isOffset: false);

        Assert.Equal<int[]>([[0, 1], [2], [3], [4, 5]], Pages(layout));
    }

    [Fact]
    public void A_publication_of_wide_pages_only_has_nothing_to_offset()
    {
        var layout = SpreadLayout.Paired(3, new HashSet<int> { 0, 1, 2 }, isOffset: false);

        Assert.False(layout.HasPairs);
        Assert.Equal(3, layout.Count);
    }

    [Fact]
    public void A_page_outside_the_layout_is_in_slot_zero_and_a_slot_outside_is_nothing()
    {
        var layout = SpreadLayout.Paired(4, NoWidePages, isOffset: false);

        Assert.Equal(0, layout.SlotContaining(99));
        Assert.Equal(0, layout.SlotContaining(-1));
        Assert.Null(layout[5]);
        Assert.Equal(new Spread(2, 3), layout[1]);
    }

    [Theory]
    [InlineData(1600, 900, true)]
    [InlineData(1200, 900, true)]
    [InlineData(1199, 900, false)]
    [InlineData(900, 900, false)]
    [InlineData(480, 1000, false)]
    [InlineData(0, 900, false)]
    public void Two_pages_fit_when_the_window_is_wide_enough_for_two_at_its_height(double width, double height, bool expected)
    {
        Assert.Equal(expected, SpreadLayout.TwoPagesFit(new Extent(width, height)));
    }

    [Fact]
    public void A_page_wider_than_tall_by_the_threshold_is_a_double_page_spread()
    {
        Assert.True(SpreadLayout.IsWidePage(new Extent(2000, 1500)));
        Assert.False(SpreadLayout.IsWidePage(new Extent(1000, 1500)));
        Assert.False(SpreadLayout.IsWidePage(new Extent(1800, 1500)));
        Assert.False(SpreadLayout.IsWidePage(new Extent(1000, 0)));
    }
}
