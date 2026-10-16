using System.Text.Json;
using System.Text.Json.Serialization;

namespace StoryArc.Interop.Shell;

/// <summary>
/// A display that is connected now: its identifier and its bounds in screen pixels. On Windows
/// the values come from <c>Microsoft.UI.Windowing.DisplayArea</c> (<c>DisplayId</c> and
/// <c>OuterBounds</c>); this record keeps the pure model free of that type so it tests on any host.
/// </summary>
public sealed record DisplayBounds(string Id, int X, int Y, int Width, int Height);

/// <summary>The frame of a window in screen pixels: where it is and how big it is.</summary>
public sealed record WindowFrame(int X, int Y, int Width, int Height)
{
    /// <summary>Whether the whole frame lies inside <paramref name="display"/>.</summary>
    public bool IsInside(DisplayBounds display) =>
        X >= display.X
        && Y >= display.Y
        && X + Width <= display.X + display.Width
        && Y + Height <= display.Y + display.Height;

    /// <summary>
    /// The frame fitted to the displays connected now, so the window opens fully visible on a
    /// display that exists (desktop-experience, "A display that is gone"). A frame already inside a
    /// display is kept. Otherwise the display named by <paramref name="displayId"/> is used when it
    /// is still connected, and the first display when it is not; the frame is clamped to that
    /// display's bounds and never below the minimum size. With no display known, the size is
    /// clamped to the minimum and the position is kept.
    /// </summary>
    public WindowFrame FitTo(IReadOnlyList<DisplayBounds> displays, string? displayId, int minWidth, int minHeight)
    {
        var width = Math.Max(Width, minWidth);
        var height = Math.Max(Height, minHeight);
        if (displays.Count == 0)
        {
            return new WindowFrame(X, Y, width, height);
        }

        var sized = new WindowFrame(X, Y, width, height);
        if (displays.Any(sized.IsInside))
        {
            return sized;
        }

        var target = displays.FirstOrDefault(display => display.Id == displayId) ?? displays[0];
        width = Math.Min(width, Math.Max(target.Width, minWidth));
        height = Math.Min(height, Math.Max(target.Height, minHeight));
        var x = Math.Clamp(X, target.X, Math.Max(target.X, target.X + target.Width - width));
        var y = Math.Clamp(Y, target.Y, Math.Max(target.Y, target.Y + target.Height - height));
        return new WindowFrame(x, y, width, height);
    }
}

/// <summary>What the app remembers about the library window between two runs.</summary>
public sealed record LibraryWindowState(WindowFrame Frame, bool IsMaximized, string? DisplayId);

/// <summary>
/// What the app remembers about one reader window: the publication it reads, its frame, and the
/// page it was on. The page is also in the progress store; it is here so a crash restores the
/// window to the page it showed even when the store's last write is older.
/// </summary>
public sealed record ReaderWindowState(string PublicationId, WindowFrame Frame, bool IsMaximized, string? DisplayId, int Page);

/// <summary>
/// Every window the app had open when it last saved: the library window and the readers, in the
/// order they were opened. The app writes it on every window change and reads it at launch
/// (desktop-experience, "Windows come back after a quit or a crash").
/// </summary>
public sealed record SessionState(LibraryWindowState? Library, IReadOnlyList<ReaderWindowState> Readers)
{
    /// <summary>The state of an app that has never saved: no window to restore.</summary>
    public static SessionState Empty { get; } = new(null, []);

    /// <summary>The JSON text, ready to write to the session file.</summary>
    public string Save() => JsonSerializer.Serialize(this, SessionStateJsonContext.Default.SessionState);

    /// <summary>
    /// Reads the JSON text. Anything missing, empty or damaged gives <see cref="Empty"/>, so a bad
    /// file never stops the library window from opening.
    /// </summary>
    public static SessionState Restore(string? text)
    {
        if (string.IsNullOrWhiteSpace(text))
        {
            return Empty;
        }

        try
        {
            var state = JsonSerializer.Deserialize(text, SessionStateJsonContext.Default.SessionState);
            return state is null ? Empty : state with { Readers = state.Readers ?? [] };
        }
        catch (JsonException)
        {
            return Empty;
        }
    }

    /// <summary>The same session with one reader's state replaced, or added when it is new.</summary>
    public SessionState WithReader(ReaderWindowState reader)
    {
        var readers = Readers.Where(existing => existing.PublicationId != reader.PublicationId).ToList();
        readers.Add(reader);
        return this with { Readers = readers };
    }

    /// <summary>The same session without the reader of <paramref name="publicationId"/>.</summary>
    public SessionState WithoutReader(string publicationId) =>
        this with { Readers = Readers.Where(existing => existing.PublicationId != publicationId).ToList() };
}

/// <summary>
/// Which saved readers open again at launch, and which do not. A publication that has been
/// removed or whose source is offline does not open; the library names it in grey and its page
/// stays in the progress store (desktop-experience, "A publication that cannot be reopened").
/// </summary>
public sealed record RestorationPlan(IReadOnlyList<ReaderWindowState> Reopen, IReadOnlyList<string> Skipped)
{
    public static RestorationPlan From(SessionState session, Func<string, bool> canReopen)
    {
        var reopen = new List<ReaderWindowState>();
        var skipped = new List<string>();
        foreach (var reader in session.Readers)
        {
            if (canReopen(reader.PublicationId))
            {
                reopen.Add(reader);
            }
            else
            {
                skipped.Add(reader.PublicationId);
            }
        }

        return new RestorationPlan(reopen, skipped);
    }
}

/// <summary>The sizes a window opens at when nothing is saved, in device-independent pixels.</summary>
public static class WindowDefaults
{
    public const int LibraryWidth = 1100;
    public const int LibraryHeight = 720;
    public const int ReaderWidth = 900;
    public const int ReaderHeight = 1100;

    /// <summary>The narrowest useful snap (docs/designs/desktop/windows.md, section 3).</summary>
    public const int MinWidth = 480;
    public const int MinHeight = 360;
}

/// <summary>
/// System.Text.Json source generation (design.md, Decision 5: records are parsed with no
/// reflection, so trimming works).
/// </summary>
[JsonSourceGenerationOptions(WriteIndented = true, PropertyNamingPolicy = JsonKnownNamingPolicy.CamelCase)]
[JsonSerializable(typeof(SessionState))]
internal sealed partial class SessionStateJsonContext : JsonSerializerContext;
