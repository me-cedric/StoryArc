namespace StoryArc.Interop.Reader;

/// <summary>
/// One slot in the reader's page order: a page on its own, or two facing pages. Leading and
/// trailing are in the publication's own order, not in screen order: which side each lands on is
/// the view's business, and a manga spread puts the leading page on the right.
/// </summary>
public sealed record Spread(int Leading, int? Trailing)
{
    public bool IsPair => Trailing is not null;

    public IReadOnlyList<int> Pages => Trailing is { } trailing ? new[] { Leading, trailing } : new[] { Leading };
}

/// <summary>
/// The reader's page order once two pages may share the window. Mirrored from StoryArcKit's
/// <c>SpreadLayout</c> (and Android's), because the pairing rule is arithmetic and arithmetic is
/// what diverges silently between codebases (desktop-clients task 2.40, after 2.14;
/// desktop-experience "Two-page spreads by window shape").
/// </summary>
public sealed class SpreadLayout
{
    private readonly int[] _slotOfPage;

    private SpreadLayout(IReadOnlyList<Spread> slots)
    {
        Slots = slots;
        var pageCount = slots.Sum(spread => spread.Pages.Count);
        _slotOfPage = new int[pageCount];
        for (var slot = 0; slot < slots.Count; slot++)
        {
            foreach (var page in slots[slot].Pages)
            {
                if (page >= 0 && page < pageCount)
                {
                    _slotOfPage[page] = slot;
                }
            }
        }
    }

    /// <summary>The slots, in the publication's own order.</summary>
    public IReadOnlyList<Spread> Slots { get; }

    public int Count => Slots.Count;

    /// <summary>Whether anything here is a pair: what decides whether the pairing offset control is offered.</summary>
    public bool HasPairs => Slots.Any(spread => spread.IsPair);

    /// <summary>Every page on its own: a narrow window, a scroll, or a publication of one page.</summary>
    public static SpreadLayout Single(int pageCount) =>
        new(Enumerable.Range(0, Math.Max(0, pageCount)).Select(page => new Spread(page, null)).ToList());

    /// <summary>
    /// Facing pages, paired. A wide page (declared by ComicInfo or found landscape when it decoded)
    /// stands alone, and so does the page that would have been paired with it. With the offset,
    /// the cover stands alone on the first screen and the pairing shifts by one.
    /// </summary>
    public static SpreadLayout Paired(int pageCount, IReadOnlySet<int> wide, bool isOffset)
    {
        var slots = new List<Spread>();
        var index = 0;
        if (isOffset && pageCount > 0)
        {
            slots.Add(new Spread(0, null));
            index = 1;
        }

        while (index < pageCount)
        {
            var alone = wide.Contains(index) || index + 1 >= pageCount || wide.Contains(index + 1);
            if (alone)
            {
                slots.Add(new Spread(index, null));
                index += 1;
            }
            else
            {
                slots.Add(new Spread(index, index + 1));
                index += 2;
            }
        }

        return new SpreadLayout(slots);
    }

    /// <summary>The slot a page is shown in; zero for a page that is not in this layout.</summary>
    public int SlotContaining(int page) => page >= 0 && page < _slotOfPage.Length ? _slotOfPage[page] : 0;

    public Spread? this[int slot] => slot >= 0 && slot < Slots.Count ? Slots[slot] : null;

    /// <summary>
    /// Whether two portrait pages fit side by side in a window of this size: the width at which
    /// two pages at the window's full height sit beside each other. Below it one page shows, on
    /// the page the reader was on.
    /// </summary>
    public static bool TwoPagesFit(Extent viewport, double pageAspectRatio = DefaultPageAspectRatio) =>
        viewport.Width > 0 && viewport.Height > 0 && viewport.Width >= 2 * pageAspectRatio * viewport.Height;

    /// <summary>A comic page is about 2:3, so two of them want a window at least 4:3.</summary>
    public const double DefaultPageAspectRatio = 2.0 / 3.0;

    /// <summary>
    /// Whether a page's own shape makes it a double-page spread, the way <c>PageDecoder.isSpread</c>
    /// reads it on iOS: wider than tall by the threshold.
    /// </summary>
    public static bool IsWidePage(Extent image, double threshold = 1.2) =>
        image.Height > 0 && image.Width / image.Height > threshold;
}
