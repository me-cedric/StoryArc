namespace StoryArc.Interop.Reader;

/// <summary>A key the reader cares about, platform-free. The app maps <c>Windows.System.VirtualKey</c> to it.</summary>
public enum ReaderKey
{
    Other,
    Left,
    Right,
    PageUp,
    PageDown,
    Space,
    Home,
    End,
    Enter,
    Escape,
    Tab,
}

/// <summary>What a key asks the reader to do.</summary>
public enum PageAction
{
    /// <summary>Nothing: the key is not the reader's, the page is at a limit, or a text field has focus.</summary>
    None,
    Next,
    Previous,
    First,
    Last,
    ToggleChrome,

    /// <summary>Focus leaves the book's text for the reader's chrome (desktop-experience, "Leaving a book's text").</summary>
    LeaveText,
}

/// <summary>What the mapper needs to know about the reader at the moment of the key.</summary>
public readonly record struct KeyContext(
    bool IsRightToLeft,
    bool IsTextFieldFocused,
    bool IsAtFirstPage,
    bool IsAtLastPage,
    bool IsShiftHeld);

/// <summary>
/// The pure mapper from a key and the reading direction to a page action (desktop-clients task
/// 2.39, after 2.11; desktop-experience "Keys that turn pages" and "A shortcut while typing").
/// The horizontal keys follow the reading direction: in a right-to-left publication the right
/// arrow shows the previous page, so the key points the way the page moves. Page Down, Page Up,
/// Space and Shift+Space are reading-order keys and never mirror. A key at the end does nothing
/// and says nothing. While a text field has focus a letter or an arrow edits the text.
/// </summary>
public static class PageKeyMapper
{
    public static PageAction Map(ReaderKey key, KeyContext context)
    {
        if (context.IsTextFieldFocused)
        {
            return key is ReaderKey.Escape or ReaderKey.Tab ? PageAction.LeaveText : PageAction.None;
        }

        var action = key switch
        {
            ReaderKey.Right => context.IsRightToLeft ? PageAction.Previous : PageAction.Next,
            ReaderKey.Left => context.IsRightToLeft ? PageAction.Next : PageAction.Previous,
            ReaderKey.PageDown => PageAction.Next,
            ReaderKey.PageUp => PageAction.Previous,
            ReaderKey.Space => context.IsShiftHeld ? PageAction.Previous : PageAction.Next,
            ReaderKey.Home => PageAction.First,
            ReaderKey.End => PageAction.Last,
            ReaderKey.Enter => PageAction.ToggleChrome,
            ReaderKey.Escape => PageAction.LeaveText,
            _ => PageAction.None,
        };

        return action switch
        {
            PageAction.Next when context.IsAtLastPage => PageAction.None,
            PageAction.Previous when context.IsAtFirstPage => PageAction.None,
            PageAction.First when context.IsAtFirstPage => PageAction.None,
            PageAction.Last when context.IsAtLastPage => PageAction.None,
            _ => action,
        };
    }
}
