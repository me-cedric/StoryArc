using System.Security.Cryptography;
using System.Text;
using System.Text.Json;
using StoryArc.Interop;
using StoryArc.Interop.Epub;
using StoryArc.Interop.Tests.Support;

namespace StoryArc.Interop.Tests.Epub;

/// <summary>
/// The EPUB half of the wave 4 seam through the wrapper, and the host over the pinned bundle with the
/// core's manifest and positions (desktop-clients task 4.16 over 4.3): the fixture book of
/// <c>packages/test-fixtures/ebooks</c> opens, its manifest's self link is the URL the host serves it
/// at, its positions are the phones' two, its cover comes with its media type, and the bundle served
/// at <c>/storyarc-epub.js</c> is byte for byte the file whose digest <c>pin.json</c> records.
/// </summary>
public sealed class EpubSeamTests
{
    private static byte[] Bundle() => File.ReadAllBytes(Corpus.RepositoryPath("apps/desktop-web/epub/dist/storyarc-epub.js"));

    private static (EpubPublication Epub, EpubHost Host) OpenFixture()
    {
        var path = Corpus.Path("ebooks/fixture.epub");
        var id = EpubHost.IdFor(path);
        var selfUrl = EpubHost.Scheme + "://" + id + EpubHost.ManifestPath;
        var epub = EpubPublication.Open(path, selfUrl);
        var host = new EpubHost(id, epub, Bundle);
        Assert.Equal(selfUrl, host.SelfUrl);
        return (epub, host);
    }

    [Fact]
    public void The_fixture_book_opens_to_the_manifest_and_positions_the_phones_read()
    {
        var (epub, host) = OpenFixture();
        using (epub)
        {
            using var manifest = JsonDocument.Parse(epub.ManifestJson());
            Assert.Equal("Fixture Publication", manifest.RootElement.GetProperty("metadata").GetProperty("title").GetString());
            Assert.Equal("reflowable", manifest.RootElement.GetProperty("metadata").GetProperty("layout").GetString());
            Assert.Equal(host.SelfUrl, manifest.RootElement.GetProperty("links")[0].GetProperty("href").GetString());
            Assert.Equal("OEBPS/ch1.xhtml", manifest.RootElement.GetProperty("readingOrder")[0].GetProperty("href").GetString());

            var positions = epub.PositionsJson();
            Assert.Equal(2, EpubProgress.Count(positions));
            using var list = JsonDocument.Parse(positions);
            Assert.Equal(2, list.RootElement[1].GetProperty("locations").GetProperty("position").GetInt32());
            Assert.Equal(0.5, list.RootElement[1].GetProperty("locations").GetProperty("totalProgression").GetDouble());
        }
    }

    [Fact]
    public void The_host_serves_the_cores_manifest_the_containers_bytes_and_the_pinned_bundle_with_the_policy()
    {
        var (epub, host) = OpenFixture();
        using (epub)
        {
            var manifest = host.Answer(host.SelfUrl, EpubRequestContext.Fetch);
            Assert.Equal(200, manifest.Status);
            Assert.Equal(EpubHost.ContentSecurityPolicy, manifest.Header("Content-Security-Policy"));
            Assert.Equal(epub.ManifestJson(), Encoding.UTF8.GetString(manifest.Body.Span));

            var cover = host.Answer(host.UrlFor("OEBPS/cover.png"), EpubRequestContext.Image);
            Assert.Equal(200, cover.Status);
            Assert.Equal("image/png", cover.MediaType);
            Assert.Equal(new byte[] { 0x89, 0x50, 0x4E, 0x47 }, cover.Body.Span[..4].ToArray());

            var chapter = host.Answer(host.UrlFor("OEBPS/ch1.xhtml"), EpubRequestContext.Frame);
            Assert.Equal("application/xhtml+xml", chapter.MediaType);
            Assert.Contains("Chapter One", Encoding.UTF8.GetString(chapter.Body.Span), StringComparison.Ordinal);

            Assert.Equal(404, host.Answer(host.UrlFor("OEBPS/missing.png"), EpubRequestContext.Image).Status);

            var bundle = host.Answer(host.Origin + "storyarc-epub.js", EpubRequestContext.Script);
            using var pin = JsonDocument.Parse(File.ReadAllText(Corpus.RepositoryPath("apps/desktop-web/epub/pin.json")));
            Assert.Equal(pin.RootElement.GetProperty("sha256").GetString(), Convert.ToHexStringLower(SHA256.HashData(bundle.Body.Span)));
            Assert.StartsWith("text/javascript", bundle.MediaType, StringComparison.Ordinal);
            Assert.Contains("StoryArcEpub", Encoding.UTF8.GetString(bundle.Body.Span), StringComparison.Ordinal);
        }
    }

    [Fact]
    public void Through_the_fake_web_view_the_fixture_book_renders_from_its_origin_and_nothing_leaves_it()
    {
        var (epub, host) = OpenFixture();
        using (epub)
        {
            var view = new FakeWebView2(host);
            view.FireAll("http://127.0.0.1:4815");
            Assert.Empty(view.Arrivals);

            Assert.Equal(EgressLock.None, view.Request(host.ReaderPageUrl, EpubRequestContext.Document));
            Assert.Equal(EgressLock.None, view.Request(host.SelfUrl, EpubRequestContext.Fetch));
            Assert.Equal(EgressLock.None, view.Request(host.UrlFor("OEBPS/ch1.xhtml"), EpubRequestContext.Fetch));
        }
    }

    [Fact]
    public void A_file_that_is_not_an_epub_is_refused_by_name_and_a_missing_resource_is_null_not_an_error()
    {
        var error = Assert.Throws<StoryArcException>(() => EpubPublication.Open(Corpus.Path("comics/single-page.cbz"), "storyarc-epub://x/manifest.json"));
        Assert.True(error.Status is StoryArcStatus.Unsupported or StoryArcStatus.Unreadable, error.Message);

        using var epub = EpubPublication.Open(Corpus.Path("ebooks/fixture.epub"), "storyarc-epub://x/manifest.json");
        Assert.Null(epub.Resource("OEBPS/nowhere.xhtml"));
        Assert.NotNull(epub.Resource("OEBPS/ch1.xhtml"));
        epub.Dispose();
        Assert.Throws<ObjectDisposedException>(() => epub.ManifestJson());
    }
}
