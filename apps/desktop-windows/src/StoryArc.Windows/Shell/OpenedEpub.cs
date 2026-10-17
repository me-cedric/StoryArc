using System.Text.Json;
using StoryArc.Interop;
using StoryArc.Interop.Epub;

namespace StoryArc.Windows.Shell;

/// <summary>
/// An EPUB the core has opened for an <see cref="EpubReaderWindow"/> (desktop-clients task 4.16): the
/// handle, the host rules bound to it, the positions list and the identity the progress store files
/// it under. The window owns it and disposes it when it closes.
/// </summary>
/// <param name="Id">The file path: the key of the window registry, the session and the recent list.</param>
internal sealed record OpenedEpub(string Id, EpubPublication Handle, EpubHost Host, string Title, string PositionsJson, int PositionCount, CoreIdentity Identity) : IDisposable
{
    /// <summary>The pinned renderer, copied beside the app by the project file from <c>apps/desktop-web/epub/dist</c>.</summary>
    private static readonly Lazy<byte[]> Bundle = new(() => File.ReadAllBytes(Path.Combine(AppContext.BaseDirectory, "Assets", "storyarc-epub.js")));

    /// <summary>
    /// Opens <paramref name="path"/> through the core, off the interface thread. A file that is not an EPUB or
    /// has no package document throws <see cref="StoryArcException"/> with the core's sentence.
    /// </summary>
    public static Task<OpenedEpub> OpenAsync(string path) => Task.Run(() =>
    {
        var id = EpubHost.IdFor(path);
        var handle = EpubPublication.Open(path, EpubHost.Scheme + "://" + id + EpubHost.ManifestPath);
        try
        {
            var host = new EpubHost(id, handle, () => Bundle.Value);
            var positions = handle.PositionsJson();
            using var manifest = JsonDocument.Parse(handle.ManifestJson());
            var title = manifest.RootElement.TryGetProperty("metadata", out var metadata) && metadata.TryGetProperty("title", out var name) && name.ValueKind == JsonValueKind.String
                ? name.GetString() ?? Path.GetFileNameWithoutExtension(path)
                : Path.GetFileNameWithoutExtension(path);

            // The seam has no identity export for an EPUB yet (a gap for the core owner), so the record is filed under the
            // file's path, which is what the session and the recent list key on too.
            var identity = new CoreIdentity(ContentDigest: "path-" + id, NormalizedPath: path);
            return new OpenedEpub(path, handle, host, title, positions, Math.Max(1, EpubProgress.Count(positions)), identity);
        }
        catch
        {
            handle.Dispose();
            throw;
        }
    });

    public void Dispose() => Handle.Dispose();
}
