using StoryArc.Interop.Reader;

namespace StoryArc.Interop.Tests.Reader;

/// <summary>
/// The key mapper, test first (desktop-clients task 2.39, after 2.11). Each test is a scenario of
/// desktop-experience "Keys that turn pages", "A shortcut while typing" or "Leaving a book's text".
/// </summary>
public sealed class PageKeyMapperTests
{
    private static readonly KeyContext LeftToRight = new(IsRightToLeft: false, IsTextFieldFocused: false, IsAtFirstPage: false, IsAtLastPage: false, IsShiftHeld: false);
    private static readonly KeyContext RightToLeft = LeftToRight with { IsRightToLeft = true };

    [Theory]
    [InlineData(ReaderKey.Right, PageAction.Next)]
    [InlineData(ReaderKey.Left, PageAction.Previous)]
    [InlineData(ReaderKey.PageDown, PageAction.Next)]
    [InlineData(ReaderKey.PageUp, PageAction.Previous)]
    [InlineData(ReaderKey.Space, PageAction.Next)]
    [InlineData(ReaderKey.Home, PageAction.First)]
    [InlineData(ReaderKey.End, PageAction.Last)]
    [InlineData(ReaderKey.Enter, PageAction.ToggleChrome)]
    [InlineData(ReaderKey.Other, PageAction.None)]
    public void Left_to_right_keys_move_as_the_spec_says(ReaderKey key, PageAction expected)
    {
        Assert.Equal(expected, PageKeyMapper.Map(key, LeftToRight));
    }

    [Theory]
    [InlineData(ReaderKey.Right, PageAction.Previous)]
    [InlineData(ReaderKey.Left, PageAction.Next)]
    [InlineData(ReaderKey.PageDown, PageAction.Next)]
    [InlineData(ReaderKey.Space, PageAction.Next)]
    [InlineData(ReaderKey.PageUp, PageAction.Previous)]
    public void Right_to_left_mirrors_the_arrows_and_nothing_else(ReaderKey key, PageAction expected)
    {
        Assert.Equal(expected, PageKeyMapper.Map(key, RightToLeft));
    }

    [Fact]
    public void Shift_space_shows_the_previous_page()
    {
        Assert.Equal(PageAction.Previous, PageKeyMapper.Map(ReaderKey.Space, LeftToRight with { IsShiftHeld = true }));
    }

    [Fact]
    public void A_key_at_the_end_does_nothing_and_says_nothing()
    {
        var atEnd = LeftToRight with { IsAtLastPage = true };
        var atStart = LeftToRight with { IsAtFirstPage = true };

        Assert.Equal(PageAction.None, PageKeyMapper.Map(ReaderKey.Right, atEnd));
        Assert.Equal(PageAction.None, PageKeyMapper.Map(ReaderKey.Space, atEnd));
        Assert.Equal(PageAction.None, PageKeyMapper.Map(ReaderKey.End, atEnd));
        Assert.Equal(PageAction.Previous, PageKeyMapper.Map(ReaderKey.Left, atEnd));
        Assert.Equal(PageAction.None, PageKeyMapper.Map(ReaderKey.Left, atStart));
        Assert.Equal(PageAction.None, PageKeyMapper.Map(ReaderKey.Home, atStart));
        Assert.Equal(PageAction.None, PageKeyMapper.Map(ReaderKey.Left, RightToLeft with { IsAtLastPage = true }));
    }

    [Fact]
    public void A_text_field_in_focus_keeps_every_letter_and_arrow()
    {
        var typing = LeftToRight with { IsTextFieldFocused = true };

        Assert.Equal(PageAction.None, PageKeyMapper.Map(ReaderKey.Right, typing));
        Assert.Equal(PageAction.None, PageKeyMapper.Map(ReaderKey.Space, typing));
        Assert.Equal(PageAction.None, PageKeyMapper.Map(ReaderKey.Home, typing));
        Assert.Equal(PageAction.None, PageKeyMapper.Map(ReaderKey.Enter, typing));
        Assert.Equal(PageAction.None, PageKeyMapper.Map(ReaderKey.Other, typing));
    }

    [Fact]
    public void Escape_and_tab_leave_a_books_text_for_the_chrome()
    {
        var typing = LeftToRight with { IsTextFieldFocused = true };

        Assert.Equal(PageAction.LeaveText, PageKeyMapper.Map(ReaderKey.Escape, typing));
        Assert.Equal(PageAction.LeaveText, PageKeyMapper.Map(ReaderKey.Tab, typing));
        Assert.Equal(PageAction.LeaveText, PageKeyMapper.Map(ReaderKey.Escape, LeftToRight));
        Assert.Equal(PageAction.None, PageKeyMapper.Map(ReaderKey.Tab, LeftToRight));
    }
}
