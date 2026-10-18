using System.Text.Json;
using StoryArc.Interop;
using StoryArc.Interop.Epub;
using StoryArc.Interop.Playback;

namespace StoryArc.Windows.Shell;

/// <summary>
/// An EPUB the core has opened for an <see cref="EpubReaderWindow"/> (desktop-clients task 4.16): the
/// handle, the host rules bound to it, the positions list and the identity the progress store files
/// it under. The window owns it and disposes it when it closes.
/// </summary>
/// <param name="Id">The file path: the key of the window registry, the session and the recent list.</param>
internal sealed record OpenedEpub(string Id, EpubPublication Handle, EpubHost Host, string Title, string? Author, string PositionsJson, int PositionCount, CoreIdentity Identity, IReadOnlyList<ReadingOrderEntry> ReadingOrder) : IDisposable
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

            // Filed under the file's content digest, as a comic is, so a moved or renamed book keeps its place; a record
            // written earlier under the "path-" placeholder takes the real digest on its next save (the core migrates it).
            var identity = FileIdentity.Of(path);
            var author = metadata.ValueKind == JsonValueKind.Object && metadata.TryGetProperty("author", out var authorNode)
                ? authorNode.ValueKind == JsonValueKind.String ? authorNode.GetString() : authorNode.ValueKind == JsonValueKind.Array && authorNode.GetArrayLength() > 0 ? authorNode[0].ToString() : null
                : null;
            var toc = TocTitles(manifest.RootElement);
            var order = manifest.RootElement.TryGetProperty("readingOrder", out var orderNode) && orderNode.ValueKind == JsonValueKind.Array
                ? orderNode.EnumerateArray().Select(link => link.GetProperty("href").GetString() ?? string.Empty).Where(href => href.Length > 0)
                    .Select((href, index) => new ReadingOrderEntry(index, href, toc.GetValueOrDefault(href) ?? toc.GetValueOrDefault(href.Split('#')[0]) ?? Path.GetFileNameWithoutExtension(href))).ToList()
                : [];
            return new OpenedEpub(path, handle, host, title, author, positions, Math.Max(1, EpubProgress.Count(positions)), identity, order);
        }
        catch
        {
            handle.Dispose();
            throw;
        }
    });

    /// <summary>
    /// The sentences of the reading-order item <paramref name="index"/>, for the voice: the chapter's XHTML through the core,
    /// its markup stripped, split at sentence ends. A resource the container lacks reads as no sentences.
    /// </summary>
    public IReadOnlyList<Sentence> SentencesOf(int index)
    {
        if (index < 0 || index >= ReadingOrder.Count)
        {
            return [];
        }

        var entry = ReadingOrder[index];
        var resource = Handle.Resource(entry.Href.Split('#')[0]);
        if (resource is null)
        {
            return [];
        }

        var locator = System.Text.Json.Nodes.JsonNode.Parse("{}")!.AsObject();
        locator["href"] = entry.Href;
        var locatorJson = locator.ToJsonString();
        return SentenceSplitter.Split(XhtmlText.Strip(System.Text.Encoding.UTF8.GetString(resource.Bytes)))
            .Select(text => new Sentence(text, index, locatorJson))
            .ToList();
    }

    /// <summary>The chapters as the player lists them: one a reading-order item, a second long each, so the list has an order and names.</summary>
    public IReadOnlyList<PlaybackChapter> Chapters() =>
        ReadingOrder.Select(entry => new PlaybackChapter(entry.Title, TimeSpan.FromSeconds(entry.Index), TimeSpan.FromSeconds(1))).ToList();

    /// <summary>The title the table of contents gives each href; the first entry wins when two name one href.</summary>
    private static Dictionary<string, string?> TocTitles(JsonElement root)
    {
        var titles = new Dictionary<string, string?>(StringComparer.Ordinal);
        if (!root.TryGetProperty("toc", out var toc) || toc.ValueKind != JsonValueKind.Array)
        {
            return titles;
        }

        foreach (var link in toc.EnumerateArray())
        {
            if (link.TryGetProperty("href", out var href) && href.ValueKind == JsonValueKind.String && href.GetString() is { Length: > 0 } key)
            {
                _ = titles.TryAdd(key, link.TryGetProperty("title", out var title) && title.ValueKind == JsonValueKind.String ? title.GetString() : null);
            }
        }

        return titles;
    }

    public void Dispose() => Handle.Dispose();
}

/// <summary>One item of the reading order: its index, its container href and the title the table of contents gives it, or its file name.</summary>
internal sealed record ReadingOrderEntry(int Index, string Href, string Title);
