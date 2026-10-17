using System.Runtime.InteropServices.WindowsRuntime;
using Microsoft.UI.Xaml;
using Microsoft.UI.Xaml.Controls;
using Microsoft.UI.Xaml.Media;
using Microsoft.UI.Xaml.Media.Imaging;
using StoryArc.Interop;
using StoryArc.Interop.Reader;
using StoryArc.Windows.Shell;
using Windows.Foundation;

namespace StoryArc.Windows;

/// <summary>
/// The page view of a reader window over the interop decoder (desktop-clients task 2.40). It sizes
/// the one or two slots of <see cref="PageNavigator.ScreenOrder"/> to fit the window, decodes each
/// page through <see cref="ComicPublication.DecodePage"/> on a worker thread at the size
/// <see cref="PagePixels.DecodeEdge"/> asks for, converts it with
/// <see cref="PagePixels.ToPremultipliedBgra"/> into a <c>WriteableBitmap</c>, and decodes the
/// neighbouring pages ahead. A page still decoding is a quiet frame in the page's shape; a page that
/// cannot be read is the same frame with its named reason, and the other page of the pair shows at once.
/// </summary>
internal sealed class ReaderPageView
{
    private const int CacheLimit = 8;

    private readonly OpenedPublication _opened;
    private readonly PageNavigator _navigator;
    private readonly ReaderWindow _window;
    private readonly Dictionary<int, (int Edge, WriteableBitmap Bitmap)> _bitmaps = [];
    private readonly Dictionary<int, string> _failures = [];
    private readonly HashSet<(int Page, int Edge)> _inFlight = [];
    private readonly TranslateTransform _follow = new();
    private int _version;

    public ReaderPageView(OpenedPublication opened, PageNavigator navigator, ReaderWindow window)
    {
        _opened = opened;
        _navigator = navigator;
        _window = window;
        _window.FirstSlotParts.Slot.RenderTransform = _follow;
        _window.SecondSlotParts.Slot.RenderTransform = _follow;
    }

    /// <summary>Whether the page is zoomed past its fit, which gives the arrows and the drag to panning.</summary>
    public bool IsZoomed => PageZoom.IsZoomedPastFit(_window.Scroller.ZoomFactor, PageZoom.Floor);

    /// <summary>Draws the slot on screen and asks for what it lacks.</summary>
    public void Show()
    {
        var version = ++_version;
        var pages = _navigator.ScreenOrder();
        var viewport = Viewport();
        var slotViewport = pages.Count == 2 ? new Extent(viewport.Width / 2, viewport.Height) : viewport;
        var edge = PagePixels.DecodeEdge(slotViewport, _window.Scroller.XamlRoot?.RasterizationScale ?? 1, _window.Scroller.ZoomFactor);

        Fill(_window.FirstSlotParts, pages.Count > 0 ? pages[0] : null, slotViewport, edge, version);
        Fill(_window.SecondSlotParts, pages.Count > 1 ? pages[1] : null, slotViewport, edge, version);

        foreach (var neighbour in _navigator.Neighbours())
        {
            _ = DecodeAsync(neighbour, edge, version: null);
        }
    }

    /// <summary>The page follows a drag by <paramref name="travel"/> pixels; zero settles it back.</summary>
    public void Follow(double travel) => _follow.X = travel;

    /// <summary>Zooms to <paramref name="scale"/> about <paramref name="anchor"/>, or about the centre, inside the limits.</summary>
    public void ZoomTo(double scale, Point? anchor)
    {
        var scroller = _window.Scroller;
        var target = PageZoom.Clamp(scale);
        var old = scroller.ZoomFactor;
        var focus = anchor ?? new Point(scroller.ViewportWidth / 2, scroller.ViewportHeight / 2);
        var x = PageZoom.OffsetZoomedAbout(scroller.HorizontalOffset, focus.X, old, target, scroller.ExtentWidth / old * target, scroller.ViewportWidth);
        var y = PageZoom.OffsetZoomedAbout(scroller.VerticalOffset, focus.Y, old, target, scroller.ExtentHeight / old * target, scroller.ViewportHeight);
        _ = scroller.ChangeView(x, y, (float)target);
    }

    /// <summary>A zoom has settled: decode again at the sharper size when the zoom asks for more pixels.</summary>
    public void ZoomSettled() => Show();

    private void Fill((Grid Slot, Image Image, Border Placeholder, TextBlock Reason) slot, int? page, Extent viewport, int edge, int version)
    {
        if (page is not { } index)
        {
            slot.Slot.Visibility = Visibility.Collapsed;
            return;
        }

        slot.Slot.Visibility = Visibility.Visible;
        var bitmap = _bitmaps.TryGetValue(index, out var held) ? held.Bitmap : null;
        var shape = bitmap is null ? new Extent(2, 3) : new Extent(bitmap.PixelWidth, bitmap.PixelHeight);
        var fitted = PageZoom.Fitted(shape, viewport);
        slot.Slot.Width = fitted.Width;
        slot.Slot.Height = fitted.Height;
        slot.Image.Source = bitmap;
        slot.Reason.Text = _failures.TryGetValue(index, out var reason) ? reason : string.Empty;
        slot.Placeholder.Visibility = bitmap is null ? Visibility.Visible : Visibility.Collapsed;
        Microsoft.UI.Xaml.Automation.AutomationProperties.SetName(
            slot.Image,
            string.Format(System.Globalization.CultureInfo.CurrentCulture, Strings.Get("reader_pageLabel__lld__lld", "Page {0} of {1}"), index + 1, _navigator.PageCount));

        if (held.Bitmap is null || held.Edge < edge)
        {
            _ = DecodeAsync(index, edge, version);
        }
    }

    private async Task DecodeAsync(int page, int edge, int? version)
    {
        if (_failures.ContainsKey(page) || (_bitmaps.TryGetValue(page, out var held) && held.Edge >= edge) || !_inFlight.Add((page, edge)))
        {
            return;
        }

        try
        {
            var decoded = await Task.Run(() =>
            {
                var pixels = _opened.Handle.DecodePage(page, edge);
                return (pixels.Width, pixels.Height, Bgra: PagePixels.ToPremultipliedBgra(pixels.Rgba));
            });

            var bitmap = new WriteableBitmap(decoded.Width, decoded.Height);
            using (var stream = bitmap.PixelBuffer.AsStream())
            {
                await stream.WriteAsync(decoded.Bgra);
            }

            bitmap.Invalidate();
            Keep(page, edge, bitmap);
            if (SpreadLayout.IsWidePage(new Extent(decoded.Width, decoded.Height)))
            {
                _navigator.FoundWide(page);
            }
        }
        catch (StoryArcException error)
        {
            _failures[page] = error.Status == StoryArcStatus.Unsupported && error.CoreMessage is { } codec
                ? string.Format(System.Globalization.CultureInfo.CurrentCulture, Strings.Get("reader_pageUnavailable_codec___", "This page could not be read ({0})"), codec)
                : Strings.Get("reader_pageUnavailable", "This page could not be read");
            if (error.Status is StoryArcStatus.NotFound or StoryArcStatus.Unreadable && !File.Exists(_opened.Id))
            {
                _window.ShowUnavailable(Strings.Get("library_cell_unavailable", "Needs its library to be reachable"));
            }
        }
        catch (ObjectDisposedException)
        {
            // The window closed while the page decoded.
            return;
        }
        finally
        {
            _inFlight.Remove((page, edge));
        }

        // Redraw only when the reader is still looking at what asked, or the slot on screen wants this page.
        if (version is null ? _navigator.ScreenOrder().Contains(page) : version == _version || _navigator.ScreenOrder().Contains(page))
        {
            Show();
        }
    }

    private void Keep(int page, int edge, WriteableBitmap bitmap)
    {
        _bitmaps[page] = (edge, bitmap);
        if (_bitmaps.Count <= CacheLimit)
        {
            return;
        }

        var wanted = _navigator.ScreenOrder().Concat(_navigator.Neighbours()).ToHashSet();
        foreach (var stale in _bitmaps.Keys.Where(key => !wanted.Contains(key)).ToList())
        {
            _bitmaps.Remove(stale);
        }
    }

    private Extent Viewport()
    {
        var scroller = _window.Scroller;
        return new Extent(Math.Max(1, scroller.ActualWidth), Math.Max(1, scroller.ActualHeight));
    }
}
