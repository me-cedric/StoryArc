using System.ComponentModel;
using System.Runtime.InteropServices.WindowsRuntime;
using Microsoft.UI.Xaml;
using Microsoft.UI.Xaml.Media;
using Microsoft.UI.Xaml.Media.Imaging;
using StoryArc.Interop;
using StoryArc.Interop.Library;
using StoryArc.Interop.Reader;
using StoryArc.Windows.Shell;

namespace StoryArc.Windows.Library;

/// <summary>
/// One cell of the library grid, the list or a Home shelf, bound with <c>x:Bind</c> (desktop-clients
/// task 2.47a). The text comes from <see cref="LibraryViewModel.Cell"/>. The cover follows the ladder
/// of <see cref="CoverStep"/>: a quiet placeholder in the page's ratio, then the decoded cover. The
/// decode starts only when the binding first reads <see cref="Cover"/>, which happens when the
/// <c>ItemsView</c> realises the cell, so scrolling 10,000 publications decodes only what shows.
/// </summary>
public sealed partial class CoverCell : INotifyPropertyChanged
{
    private readonly Action<CoverCell> _open;
    private readonly Action<CoverCell> _details;
    private ImageSource? _cover;
    private bool _isLoading;

    internal CoverCell(LibraryRecord record, Action<CoverCell> open, Action<CoverCell> details)
    {
        Record = record;
        _open = open;
        _details = details;
        var cell = LibraryViewModel.Cell(record);
        Id = cell.Id;
        Title = cell.Title;
        Subtitle = cell.Subtitle ?? string.Empty;
        AccessibleName = cell.AccessibleName;
        ProgressPercent = Math.Round(cell.Progress * 100);
        UnreadableReason = cell.UnreadableReason ?? string.Empty;
    }

    public event PropertyChangedEventHandler? PropertyChanged;

    internal LibraryRecord Record { get; }

    public string Id { get; }

    public string Title { get; }

    public string Subtitle { get; }

    /// <summary>What Narrator reads for the cover: title, series, issue, percent read, downloaded.</summary>
    public string AccessibleName { get; }

    public double ProgressPercent { get; }

    public Visibility ProgressVisibility => ProgressPercent > 0 && ProgressPercent < 100 ? Visibility.Visible : Visibility.Collapsed;

    /// <summary>The named reason a file could not be opened, shown on its cell in place of the cover.</summary>
    public string UnreadableReason { get; }

    public Visibility UnreadableVisibility => UnreadableReason.Length > 0 ? Visibility.Visible : Visibility.Collapsed;

    public string OpenLabel => Strings.Get("library_action_open", "Open");

    public string DetailsLabel => Strings.Get("library_action_showDetails", "Show details");

    /// <summary>The cover, or <c>null</c> while it decodes: the cell's placeholder shows through.</summary>
    public ImageSource? Cover
    {
        get
        {
            if (_cover is null && !_isLoading && UnreadableReason.Length == 0)
            {
                _isLoading = true;
                _ = LoadAsync();
            }

            return _cover;
        }
    }

    /// <summary>The cell's Open action, bound to its context menu with <c>x:Bind</c>.</summary>
    public void Open() => _open(this);

    /// <summary>The cell's Show Details action.</summary>
    public void ShowDetails() => _details(this);

    private async Task LoadAsync()
    {
        _cover = await CoverLoader.LoadAsync(Record.Id);
        PropertyChanged?.Invoke(this, new PropertyChangedEventArgs(nameof(Cover)));
    }
}

/// <summary>
/// Decodes covers through the core, two at a time, and keeps the most recent few hundred. The cover
/// is the first page, decoded at the cell's size; a page that cannot be decoded leaves the placeholder.
/// </summary>
internal static class CoverLoader
{
    /// <summary>The longest edge a cover is decoded at: the largest cell size at 200 percent.</summary>
    public const int CoverEdge = 480;

    private const int CacheLimit = 400;

    private static readonly SemaphoreSlim Gate = new(2);
    private static readonly Dictionary<string, ImageSource> Cache = new(StringComparer.OrdinalIgnoreCase);
    private static readonly Queue<string> Order = new();

    public static async Task<ImageSource?> LoadAsync(string path)
    {
        if (Cache.TryGetValue(path, out var cached))
        {
            return cached;
        }

        await Gate.WaitAsync();
        try
        {
            var decoded = await Task.Run(() => Decode(path));
            if (decoded is null)
            {
                return null;
            }

            var bitmap = new WriteableBitmap(decoded.Value.Width, decoded.Value.Height);
            using (var stream = bitmap.PixelBuffer.AsStream())
            {
                await stream.WriteAsync(decoded.Value.Bgra);
            }

            bitmap.Invalidate();
            Remember(path, bitmap);
            return bitmap;
        }
        finally
        {
            Gate.Release();
        }
    }

    private static (int Width, int Height, byte[] Bgra)? Decode(string path)
    {
        try
        {
            using var publication = ComicPublication.Open(path);
            if (publication.PageCount == 0)
            {
                return null;
            }

            var page = publication.DecodePage(0, CoverEdge);
            return (page.Width, page.Height, PagePixels.ToPremultipliedBgra(page.Rgba));
        }
        catch (StoryArcException)
        {
            return null;
        }
    }

    private static void Remember(string path, ImageSource bitmap)
    {
        Cache[path] = bitmap;
        Order.Enqueue(path);
        while (Order.Count > CacheLimit && Order.TryDequeue(out var oldest))
        {
            Cache.Remove(oldest);
        }
    }
}
