namespace StoryArc.Interop.Reader;

/// <summary>
/// Where a reader window is in its publication and what it shows (desktop-clients task 2.40;
/// desktop-experience "Two-page spreads by window shape" and "Keys that turn pages"). It holds the
/// page order of <see cref="SpreadLayout"/> for the window's current shape, turns by slot, and keeps
/// the reader on the same page when the window widens into pairs or narrows back to one page. Pure,
/// so the reader view only feeds it the window size, the pages found wide when they decode, and the
/// actions of the keys, the pointer and the drag.
/// </summary>
public sealed class PageNavigator
{
    private readonly HashSet<int> _wide = [];
    private Extent _viewport = Extent.Zero;
    private int _page;

    /// <param name="pageCount">The publication's number of pages.</param>
    /// <param name="isRightToLeft">Whether pages run right to left, which mirrors the pair on screen.</param>
    /// <param name="startPage">The page index from zero to open on, clamped to the publication.</param>
    /// <param name="declaredWide">The pages the container declares as double spreads.</param>
    public PageNavigator(int pageCount, bool isRightToLeft, int startPage = 0, IEnumerable<int>? declaredWide = null)
    {
        PageCount = Math.Max(0, pageCount);
        IsRightToLeft = isRightToLeft;
        _page = Math.Clamp(startPage, 0, Math.Max(0, PageCount - 1));
        if (declaredWide is not null)
        {
            _wide.UnionWith(declaredWide);
        }

        Layout = SpreadLayout.Single(PageCount);
    }

    public int PageCount { get; }

    public bool IsRightToLeft { get; }

    /// <summary>Whether the cover stands alone on the first screen when pages pair; on by default.</summary>
    public bool IsOffset { get; private set; } = true;

    /// <summary>Whether the reader asked for one page whatever the window's width (the Single Page command).</summary>
    public bool IsSinglePageForced { get; private set; }

    /// <summary>The page order for the window as it is now.</summary>
    public SpreadLayout Layout { get; private set; }

    /// <summary>The page the reader is on, from zero. The slot that holds it is on screen; a turn lands on a slot's leading page.</summary>
    public int CurrentPage => _page;

    /// <summary>The slot on screen.</summary>
    public Spread? Current => Layout[Layout.SlotContaining(_page)];

    public bool IsAtFirst => Layout.SlotContaining(_page) == 0;

    public bool IsAtLast => PageCount == 0 || Layout.SlotContaining(_page) >= Layout.Count - 1;

    /// <summary>
    /// The pages on screen from left to right. In a right-to-left publication the leading page of a
    /// pair sits on the right; a page alone is centred and has no blank partner.
    /// </summary>
    public IReadOnlyList<int> ScreenOrder()
    {
        if (Current is not { } spread)
        {
            return [];
        }

        return spread.Trailing is { } trailing && IsRightToLeft ? new[] { trailing, spread.Leading } : spread.Pages;
    }

    /// <summary>The window's content size changed: pages pair when two fit, and the reader stays on the same page.</summary>
    public void Resize(Extent viewport)
    {
        _viewport = viewport;
        Relayout();
    }

    /// <summary>A page decoded landscape: it stands alone from now on, like a declared spread.</summary>
    public void FoundWide(int page)
    {
        if (page >= 0 && page < PageCount && _wide.Add(page))
        {
            Relayout();
        }
    }

    /// <summary>The Single Page and Two Pages commands: one page whatever the width, or pairs when the width allows.</summary>
    public void ForceSinglePage(bool isForced)
    {
        IsSinglePageForced = isForced;
        Relayout();
    }

    /// <summary>Shifts the pairing by one, for a publication whose pairs land wrong with the cover alone.</summary>
    public void SetOffset(bool isOffset)
    {
        IsOffset = isOffset;
        Relayout();
    }

    /// <summary>Applies a turn. Returns whether the reader moved; at a limit nothing moves and nothing is said.</summary>
    public bool Apply(PageAction action)
    {
        var slot = Layout.SlotContaining(_page);
        var target = action switch
        {
            PageAction.Next => slot + 1,
            PageAction.Previous => slot - 1,
            PageAction.First => 0,
            PageAction.Last => Layout.Count - 1,
            _ => slot,
        };

        if (target == slot || Layout[target] is not { } spread)
        {
            return false;
        }

        _page = spread.Leading;
        return true;
    }

    /// <summary>Goes to a page index from zero, clamped. Returns whether the slot on screen changed.</summary>
    public bool GoTo(int page)
    {
        var before = Layout.SlotContaining(_page);
        _page = Math.Clamp(page, 0, Math.Max(0, PageCount - 1));
        return before != Layout.SlotContaining(_page);
    }

    /// <summary>The pages of the slots either side of the one on screen, next first: what to decode ahead.</summary>
    public IReadOnlyList<int> Neighbours()
    {
        var slot = Layout.SlotContaining(_page);
        var pages = new List<int>();
        foreach (var neighbour in new[] { slot + 1, slot - 1 })
        {
            if (Layout[neighbour] is { } spread)
            {
                pages.AddRange(spread.Pages);
            }
        }

        return pages;
    }

    private void Relayout()
    {
        var pairs = !IsSinglePageForced && PageCount > 1 && SpreadLayout.TwoPagesFit(_viewport);
        // The page itself does not move: the slot that holds it is what shows.
        Layout = pairs ? SpreadLayout.Paired(PageCount, _wide, IsOffset) : SpreadLayout.Single(PageCount);
    }
}
