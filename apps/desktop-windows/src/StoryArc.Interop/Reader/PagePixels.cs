namespace StoryArc.Interop.Reader;

/// <summary>
/// From the core's decoded page to what WinUI draws (desktop-clients task 2.40). The core writes
/// RGBA, not premultiplied; a <c>WriteableBitmap</c> and a <c>SoftwareBitmap</c> in
/// <c>BitmapPixelFormat.Bgra8</c> with <c>BitmapAlphaMode.Premultiplied</c> want BGRA with each colour
/// multiplied by its alpha. Pure, so the conversion is tested on any host.
/// </summary>
public static class PagePixels
{
    /// <summary>The largest edge the reader asks the core for, whatever the window and the zoom: a page past it is drawn scaled.</summary>
    public const int MaxDecodeEdge = 8192;

    /// <summary>The smallest edge worth decoding at; a smaller ask would show a blurred page while the window grows.</summary>
    public const int MinDecodeEdge = 256;

    /// <summary>A new buffer: <paramref name="rgba"/> as premultiplied BGRA, the same size.</summary>
    public static byte[] ToPremultipliedBgra(ReadOnlySpan<byte> rgba)
    {
        if (rgba.Length % 4 != 0)
        {
            throw new ArgumentException("RGBA pixels come in groups of four bytes.", nameof(rgba));
        }

        var bgra = new byte[rgba.Length];
        for (var index = 0; index < rgba.Length; index += 4)
        {
            var alpha = rgba[index + 3];
            bgra[index] = Premultiply(rgba[index + 2], alpha);
            bgra[index + 1] = Premultiply(rgba[index + 1], alpha);
            bgra[index + 2] = Premultiply(rgba[index], alpha);
            bgra[index + 3] = alpha;
        }

        return bgra;
    }

    /// <summary>
    /// The longest edge to decode a page at for a window of <paramref name="viewport"/> device-independent
    /// pixels on a display of <paramref name="rasterScale"/> at <paramref name="zoom"/>: enough for every
    /// screen pixel the page can cover, so a zoom in is sharp and a fit decodes no more than it shows.
    /// </summary>
    public static int DecodeEdge(Extent viewport, double rasterScale, double zoom)
    {
        var longest = Math.Max(viewport.Width, viewport.Height) * Math.Max(1, rasterScale) * Math.Max(1, zoom);
        if (double.IsNaN(longest) || longest <= 0)
        {
            return MinDecodeEdge;
        }

        return (int)Math.Clamp(Math.Ceiling(longest), MinDecodeEdge, MaxDecodeEdge);
    }

    private static byte Premultiply(byte colour, byte alpha) =>
        alpha == 255 ? colour : (byte)(((colour * alpha) + 127) / 255);
}
