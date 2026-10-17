using StoryArc.Interop;
using StoryArc.Interop.Epub;
using StoryArc.Interop.Pdf;

namespace StoryArc.Windows.Shell;

/// <summary>
/// A publication the core has opened for a reader window: the handle that owns it, its record, its
/// page count, and the call that decodes one page at a longest-edge limit. A comic decodes through
/// <see cref="ComicPublication"/> (wave 2); a PDF renders through <see cref="PdfDocument"/> and also
/// carries its text model for the contents pane (desktop-clients task 4.17). The reader window owns
/// it and disposes it when it closes.
/// </summary>
/// <param name="Id">The file path: the key of the window registry, the session and the recent list.</param>
/// <param name="Decode">Page index from zero and the longest edge in pixels (zero for the page's own size) to RGBA.</param>
/// <param name="Pdf">The contents pane model of a PDF, or <c>null</c> for a comic.</param>
internal sealed record OpenedPublication(string Id, IDisposable Handle, CorePublication Record, int PageCount, Func<int, int, DecodedPage> Decode, PdfPaneModel? Pdf) : IDisposable
{
    /// <summary>
    /// Opens the comic at <paramref name="path"/> through the core, off the interface thread. A refusal throws
    /// <see cref="StoryArcException"/> with the core's sentence, which names the format (CB7 among them).
    /// </summary>
    public static Task<OpenedPublication> OpenAsync(string path) => Task.Run(() =>
    {
        var handle = ComicPublication.Open(path);
        try
        {
            return new OpenedPublication(path, handle, handle.Metadata(), handle.PageCount, handle.DecodePage, Pdf: null);
        }
        catch
        {
            handle.Dispose();
            throw;
        }
    });

    /// <summary>
    /// Opens the PDF at <paramref name="path"/> through the core's PDF engine, off the interface thread. The
    /// outline and the text-layer flag are read once here, on the worker, so the window never asks the
    /// engine on the interface thread for them. A file PDFium cannot open throws with
    /// <see cref="StoryArcStatus.Unreadable"/>; a machine without the PDFium library with <see cref="StoryArcStatus.Unsupported"/>.
    /// </summary>
    public static Task<OpenedPublication> OpenPdfAsync(string path) => Task.Run(() =>
    {
        var handle = PdfDocument.Open(path);
        try
        {
            var pageCount = handle.PageCount;
            var pane = new PdfPaneModel(handle.HasTextLayer, handle.Outline(), handle.Search);

            // The seam has no identity or metadata export for a PDF yet (a gap for the core owner): the record is
            // filed under the path, and the title is the file's name, as the phones show a PDF with no metadata.
            var identity = new CoreIdentity(ContentDigest: "path-" + EpubHost.IdFor(path), NormalizedPath: path);
            var record = new CorePublication(identity, "pdf", Path.GetFileNameWithoutExtension(path), PageCount: pageCount);
            return new OpenedPublication(path, handle, record, pageCount, handle.RenderPage, pane);
        }
        catch
        {
            handle.Dispose();
            throw;
        }
    });

    public void Dispose() => Handle.Dispose();
}
