using System.Runtime.InteropServices;
using StoryArc.Interop;
using StoryArc.Interop.Pdf;
using StoryArc.Interop.Tests.Support;
using Xunit.Abstractions;

namespace StoryArc.Interop.Tests.Pdf;

/// <summary>
/// The PDF half of the wave 4 seam through the wrapper, the same cases as the core's <c>tests/pdf.rs</c>
/// and the Linux lane's 4.11 (desktop-clients task 4.17 over 4.4), against the corpus PDFs. PDFium is
/// bound at run time: the tests look for it in <c>STORYARC_PDFIUM_DIR</c> or under
/// <c>.build/pdfium/&lt;platform&gt;</c>, where <c>pnpm pdfium:fetch</c> puts the pinned one, and skip by
/// name when neither holds it, which today is the CI test job until it fetches the library.
/// </summary>
public sealed class PdfSeamTests(ITestOutputHelper output)
{
    private static readonly Lazy<string?> StartFailure = new(TryStartEngine);

    /// <summary>Starts the engine once for the process; the reason it could not, or <c>null</c>.</summary>
    private static string? TryStartEngine()
    {
        var directory = Environment.GetEnvironmentVariable("STORYARC_PDFIUM_DIR");
        if (string.IsNullOrEmpty(directory))
        {
            var os = OperatingSystem.IsWindows() ? "win" : OperatingSystem.IsMacOS() ? "mac" : "linux";
            var arch = RuntimeInformation.ProcessArchitecture == Architecture.Arm64 ? "arm64" : "x64";
            var candidate = Corpus.RepositoryPath($".build/pdfium/{os}-{arch}/{(os == "win" ? "bin" : "lib")}");
            directory = Directory.Exists(candidate) ? candidate : null;
        }

        try
        {
            PdfEngine.Start(directory);
            return null;
        }
        catch (StoryArcException error) when (error.Status == StoryArcStatus.Unsupported && directory is null)
        {
            return "no PDFium library on this machine, run pnpm pdfium:fetch (" + error.CoreMessage + ")";
        }
    }

    /// <summary>Opens a corpus PDF, or <c>null</c> after saying why the case is skipped.</summary>
    private PdfDocument? Open(string file)
    {
        if (StartFailure.Value is { } reason)
        {
            _ = Skip.Because(output, reason);
            return null;
        }

        return PdfDocument.Open(Corpus.Path(file));
    }

    [Fact]
    public void The_text_pdf_reads_as_the_phones_read_it()
    {
        using var document = Open("comics/text-pages.pdf");
        if (document is null)
        {
            return;
        }

        Assert.Equal(3, document.PageCount);
        Assert.Equal(new PdfPageSize(612, 792), document.PageSize(0));
        Assert.True(document.HasTextLayer);
        var texts = Enumerable.Range(0, 3).Select(index => document.PageText(index).Trim()).ToList();
        Assert.Equal(new[] { "Chapter One", "Chapter Two", "Chapter Three" }, texts);

        var outline = document.Outline();
        Assert.Equal(new[] { "Chapter One", "Chapter Two", "Chapter Three" }, outline.Select(entry => entry.Title));
        Assert.Equal(new int?[] { 0, 1, 2 }, outline.Select(entry => entry.Page));
        Assert.All(outline, entry => Assert.Empty(entry.Children));
    }

    [Fact]
    public void A_page_drawn_to_fit_a_larger_view_is_enlarged_where_the_plain_render_stops_at_one_pixel_a_point()
    {
        using var document = Open("comics/text-pages.pdf");
        if (document is null)
        {
            return;
        }

        var plain = document.RenderPage(0, 1584);
        var fitted = document.RenderPageToFit(0, 1584);

        Assert.Equal(792, plain.Height);
        Assert.Equal(1584, fitted.Height);
        Assert.Equal(plain.Width * 2, fitted.Width);
        Assert.Equal(fitted.Width * fitted.Height * 4, fitted.Rgba.Length);
    }

    [Fact]
    public void Search_finds_a_phrase_on_its_page_with_its_rectangles()
    {
        using var document = Open("comics/text-pages.pdf");
        if (document is null)
        {
            return;
        }

        var hit = Assert.Single(document.Search("chapter two"));
        Assert.Equal(1, hit.Page);
        var rect = hit.Rects[0];
        Assert.True(rect.Right > rect.Left && rect.Top > rect.Bottom, rect.ToString());
        // The text sits at 72, 700 in a 612 by 792 page, origin bottom left.
        Assert.InRange(rect.Left, 70f, 80f);
        Assert.True(rect.Bottom > 690 && rect.Top < 730, rect.ToString());

        Assert.Equal(new[] { 0, 1, 2 }, document.Search("Chapter").Select(each => each.Page));
        Assert.Empty(document.Search("  "));
        Assert.Empty(document.Search("nowhere"));
    }

    [Fact]
    public void The_image_pdf_reads_as_a_comic_with_no_text_layer()
    {
        using var document = Open("comics/image-pages.pdf");
        if (document is null)
        {
            return;
        }

        Assert.Equal(3, document.PageCount);
        Assert.Equal(new PdfPageSize(200, 300), document.PageSize(0));
        Assert.False(document.HasTextLayer);
        Assert.Equal(string.Empty, document.PageText(0).Trim());
        Assert.Empty(document.Outline());

        var bounded = document.RenderPage(0, maxPixelSize: 150);
        Assert.Equal((100, 150), (bounded.Width, bounded.Height));
        Assert.Equal(100 * 150 * 4, bounded.Rgba.Length);
        var full = document.RenderPage(0);
        Assert.Equal((200, 300), (full.Width, full.Height));
        for (var pixel = 3; pixel < full.Rgba.Length; pixel += 4)
        {
            Assert.Equal(255, full.Rgba[pixel]);
        }
    }

    [Fact]
    public void A_page_past_the_end_is_named_rather_than_rendered()
    {
        using var document = Open("comics/text-pages.pdf");
        if (document is null)
        {
            return;
        }

        Assert.Equal(StoryArcStatus.InvalidArgument, Assert.Throws<StoryArcException>(() => document.RenderPage(3)).Status);
        Assert.Equal(StoryArcStatus.InvalidArgument, Assert.Throws<StoryArcException>(() => document.PageText(9)).Status);
        Assert.Equal(StoryArcStatus.InvalidArgument, Assert.Throws<StoryArcException>(() => document.PageSize(3)).Status);
    }

    [Fact]
    public void Bytes_that_are_not_a_pdf_are_unreadable_and_a_closed_document_is_not_reached()
    {
        if (StartFailure.Value is { } reason)
        {
            _ = Skip.Because(output, reason);
            return;
        }

        var error = Assert.Throws<StoryArcException>(() => PdfDocument.Open(Corpus.Path("comics/single-page.cbz")));
        Assert.Equal(StoryArcStatus.Unreadable, error.Status);

        var document = PdfDocument.Open(Corpus.Path("comics/image-pages.pdf"));
        document.Dispose();
        Assert.Throws<ObjectDisposedException>(() => document.PageCount);
    }

    [Fact]
    public void The_search_and_outline_shapes_parse_as_the_core_writes_them()
    {
        var hits = System.Text.Json.JsonSerializer.Deserialize(
            """[{"page":1,"rects":[{"left":72.0,"bottom":695.5,"right":140.25,"top":712.0}]}]""",
            PdfJsonContext.Default.ListPdfSearchHit);
        Assert.NotNull(hits);
        Assert.Equal(new PdfRect(72, 695.5f, 140.25f, 712), Assert.Single(Assert.Single(hits).Rects));

        var outline = System.Text.Json.JsonSerializer.Deserialize(
            """[{"title":"Part","page":null,"children":[{"title":"One","page":0,"children":[]}]},{"title":"Two","children":[]}]""",
            PdfJsonContext.Default.ListPdfOutlineEntry);
        Assert.NotNull(outline);
        Assert.Equal(2, outline.Count);
        Assert.Null(outline[0].Page);
        Assert.Equal(0, Assert.Single(outline[0].Children).Page);
        Assert.Null(outline[1].Page);
    }
}
