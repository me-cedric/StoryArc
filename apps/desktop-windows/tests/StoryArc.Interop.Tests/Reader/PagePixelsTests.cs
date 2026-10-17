using StoryArc.Interop.Reader;

namespace StoryArc.Interop.Tests.Reader;

/// <summary>The core's RGBA to WinUI's premultiplied BGRA, and the size a page is decoded at (task 2.40).</summary>
public sealed class PagePixelsTests
{
    [Fact]
    public void An_opaque_pixel_swaps_red_and_blue_and_keeps_its_values()
    {
        Assert.Equal(new byte[] { 30, 20, 10, 255 }, PagePixels.ToPremultipliedBgra(new byte[] { 10, 20, 30, 255 }));
    }

    [Fact]
    public void A_translucent_pixel_is_multiplied_by_its_alpha_and_a_clear_one_is_black()
    {
        Assert.Equal(new byte[] { 0, 50, 100, 128 }, PagePixels.ToPremultipliedBgra(new byte[] { 200, 100, 0, 128 }));
        Assert.Equal(new byte[] { 0, 0, 0, 0 }, PagePixels.ToPremultipliedBgra(new byte[] { 200, 100, 50, 0 }));
    }

    [Fact]
    public void A_buffer_that_is_not_whole_pixels_is_refused()
    {
        Assert.Throws<ArgumentException>(() => PagePixels.ToPremultipliedBgra(new byte[] { 1, 2, 3 }));
    }

    [Fact]
    public void A_decoded_corpus_page_converts_whole()
    {
        using var publication = ComicPublication.Open(Corpus.Path("comics/large-page.cbz"));
        var page = publication.DecodePage(0, 300);

        var bgra = PagePixels.ToPremultipliedBgra(page.Rgba);

        Assert.Equal(page.Width * page.Height * 4, bgra.Length);
        Assert.Equal(page.Rgba[2], bgra[0]);
        Assert.Equal(page.Rgba[0], bgra[2]);
    }

    [Theory]
    [InlineData(900.0, 1100.0, 1.5, 1.0, 1650)]
    [InlineData(900.0, 1100.0, 1.0, 2.0, 2200)]
    [InlineData(900.0, 1100.0, 2.0, 6.0, 8192)]
    [InlineData(0.0, 0.0, 1.0, 1.0, 256)]
    [InlineData(100.0, 120.0, 1.0, 1.0, 256)]
    public void The_decode_edge_covers_every_screen_pixel_within_the_limits(double width, double height, double scale, double zoom, int expected)
    {
        Assert.Equal(expected, PagePixels.DecodeEdge(new Extent(width, height), scale, zoom));
    }
}
