using StoryArc.Interop;

namespace StoryArc.Windows.Shell;

/// <summary>
/// A publication the core has opened for a reader window: the handle that decodes its pages, its
/// record and its page count. The reader window owns it and disposes it when it closes.
/// </summary>
/// <param name="Id">The file path: the key of the window registry, the session and the recent list.</param>
internal sealed record OpenedPublication(string Id, ComicPublication Handle, CorePublication Record, int PageCount) : IDisposable
{
    /// <summary>
    /// Opens <paramref name="path"/> through the core, off the interface thread. A refusal throws
    /// <see cref="StoryArcException"/> with the core's sentence, which names the format (CB7 among them).
    /// </summary>
    public static Task<OpenedPublication> OpenAsync(string path) => Task.Run(() =>
    {
        var handle = ComicPublication.Open(path);
        try
        {
            return new OpenedPublication(path, handle, handle.Metadata(), handle.PageCount);
        }
        catch
        {
            handle.Dispose();
            throw;
        }
    });

    public void Dispose() => Handle.Dispose();
}
