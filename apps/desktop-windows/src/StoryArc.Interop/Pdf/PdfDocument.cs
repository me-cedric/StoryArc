using System.Text.Json;
using System.Text.Json.Serialization;

namespace StoryArc.Interop.Pdf;

/// <summary>A page's size in PDF points.</summary>
public sealed record PdfPageSize(float Width, float Height);

/// <summary>One rectangle of a search hit, in PDF points with the origin at the bottom left, as PDFium reports it.</summary>
public sealed record PdfRect(
    [property: JsonPropertyName("left")] float Left,
    [property: JsonPropertyName("bottom")] float Bottom,
    [property: JsonPropertyName("right")] float Right,
    [property: JsonPropertyName("top")] float Top);

/// <summary>Every hit of a search on one page.</summary>
public sealed record PdfSearchHit(
    [property: JsonPropertyName("page")] int Page,
    [property: JsonPropertyName("rects")] IReadOnlyList<PdfRect> Rects);

/// <summary>One entry of the outline; <see cref="Page"/> is zero-based and <c>null</c> when the entry points nowhere.</summary>
public sealed record PdfOutlineEntry(
    [property: JsonPropertyName("title")] string Title,
    [property: JsonPropertyName("page")] int? Page,
    [property: JsonPropertyName("children")] IReadOnlyList<PdfOutlineEntry> Children);

[JsonSourceGenerationOptions(DefaultIgnoreCondition = JsonIgnoreCondition.WhenWritingNull)]
[JsonSerializable(typeof(List<PdfSearchHit>))]
[JsonSerializable(typeof(List<PdfOutlineEntry>))]
internal sealed partial class PdfJsonContext : JsonSerializerContext;

/// <summary>
/// The PDF engine of the core (<c>storyarc_pdf_engine_start</c>): PDFium bound at run time on one
/// thread. The first start decides the library for the process; a library that cannot be found
/// throws with <see cref="StoryArcStatus.Unsupported"/> and every folder tried in the message.
/// </summary>
public static unsafe class PdfEngine
{
    /// <summary>
    /// Starts the engine with the library in <paramref name="libraryDirectory"/>, or, for <c>null</c>, where
    /// the core looks on its own: <c>STORYARC_PDFIUM_DIR</c>, beside the executable, then the system.
    /// </summary>
    public static void Start(string? libraryDirectory = null)
    {
        var bytes = NativeCore.Utf8(libraryDirectory ?? string.Empty);
        fixed (byte* data = bytes)
        {
            NativeCore.Check(NativeMethods.storyarc_pdf_engine_start(data, (nuint)bytes.Length), "storyarc_pdf_engine_start");
        }
    }
}

/// <summary>
/// A PDF the core has opened through ranged reads (<c>storyarc_pdf_open</c>, desktop-clients task 4.17
/// over lane C's 4.4): pages render to RGBA at a longest-edge limit, text comes per page, search is
/// case folded with rectangles in PDF points, and the outline is nested. A page past the end throws
/// with <see cref="StoryArcStatus.InvalidArgument"/>; a file PDFium cannot open with
/// <see cref="StoryArcStatus.Unreadable"/>.
/// </summary>
public sealed unsafe class PdfDocument : CoreHandle
{
    private PdfDocument()
    {
    }

    public static PdfDocument Open(string path)
    {
        var bytes = NativeCore.Utf8(path);
        void* opened = null;
        fixed (byte* data = bytes)
        {
            NativeCore.Check(NativeMethods.storyarc_pdf_open(data, (nuint)bytes.Length, &opened), "storyarc_pdf_open");
        }

        var document = new PdfDocument();
        document.Adopt(opened);
        return document;
    }

    public int PageCount => Use(pointer =>
    {
        uint count = 0;
        NativeCore.Check(NativeMethods.storyarc_pdf_page_count((void*)pointer, &count), "storyarc_pdf_page_count");
        return checked((int)count);
    });

    public PdfPageSize PageSize(int index)
    {
        ArgumentOutOfRangeException.ThrowIfNegative(index);
        return Use(pointer =>
        {
            float width = 0;
            float height = 0;
            NativeCore.Check(NativeMethods.storyarc_pdf_page_size((void*)pointer, (uint)index, &width, &height), "storyarc_pdf_page_size");
            return new PdfPageSize(width, height);
        });
    }

    /// <summary>Renders page <paramref name="index"/> to RGBA, not premultiplied, at most <paramref name="maxPixelSize"/> on its longest edge, or one pixel a point for zero.</summary>
    public DecodedPage RenderPage(int index, int maxPixelSize = 0)
    {
        ArgumentOutOfRangeException.ThrowIfNegative(index);
        ArgumentOutOfRangeException.ThrowIfNegative(maxPixelSize);
        return Use(pointer =>
        {
            StoryArcBuffer pixels = default;
            uint width = 0;
            uint height = 0;
            var status = NativeMethods.storyarc_pdf_render_page((void*)pointer, (uint)index, (uint)maxPixelSize, &pixels, &width, &height);
            NativeCore.Check(status, "storyarc_pdf_render_page");
            return new DecodedPage(checked((int)width), checked((int)height), NativeCore.Take(pixels));
        });
    }

    /// <summary>The page's text in content order; empty for a page with no text layer.</summary>
    public string PageText(int index)
    {
        ArgumentOutOfRangeException.ThrowIfNegative(index);
        return Use(pointer =>
        {
            StoryArcBuffer buffer = default;
            NativeCore.Check(NativeMethods.storyarc_pdf_page_text((void*)pointer, (uint)index, &buffer), "storyarc_pdf_page_text");
            return NativeCore.TakeString(buffer);
        });
    }

    /// <summary>Whether any page carries text, so the app hides selection and search for a scanned file rather than offering them empty.</summary>
    public bool HasTextLayer => Use(pointer =>
    {
        var flag = 0;
        NativeCore.Check(NativeMethods.storyarc_pdf_has_text_layer((void*)pointer, &flag), "storyarc_pdf_has_text_layer");
        return flag == 1;
    });

    public string SearchJson(string query)
    {
        var bytes = NativeCore.Utf8(query);
        return Use(pointer =>
        {
            StoryArcBuffer buffer = default;
            fixed (byte* data = bytes)
            {
                NativeCore.Check(NativeMethods.storyarc_pdf_search((void*)pointer, data, (nuint)bytes.Length, &buffer), "storyarc_pdf_search");
            }

            return NativeCore.TakeString(buffer);
        });
    }

    /// <summary>Every page with <paramref name="query"/>, case folded, with the rectangles of each hit in PDF points.</summary>
    public IReadOnlyList<PdfSearchHit> Search(string query) =>
        JsonSerializer.Deserialize(SearchJson(query), PdfJsonContext.Default.ListPdfSearchHit) ?? [];

    public string OutlineJson() => Use(pointer =>
    {
        StoryArcBuffer buffer = default;
        NativeCore.Check(NativeMethods.storyarc_pdf_outline((void*)pointer, &buffer), "storyarc_pdf_outline");
        return NativeCore.TakeString(buffer);
    });

    /// <summary>The outline, nested; empty when the file declares none.</summary>
    public IReadOnlyList<PdfOutlineEntry> Outline() =>
        JsonSerializer.Deserialize(OutlineJson(), PdfJsonContext.Default.ListPdfOutlineEntry) ?? [];

    protected override bool ReleaseHandle()
    {
        NativeMethods.storyarc_pdf_free((void*)handle);
        return true;
    }
}
