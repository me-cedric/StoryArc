using System.Text;
using StoryArc.Interop.Epub;
using StoryArc.Interop.Tests.Support;

namespace StoryArc.Interop.Tests.Epub;

/// <summary>
/// The WebView2 host rules of desktop-clients task 4.16, test first: the custom scheme's origin, the
/// navigation filter, the answer to every request with its Content-Security-Policy, ranges, and the
/// eight-vector egress page of ADR-0015 arriving nowhere through the fake pipeline.
/// </summary>
public sealed class EpubHostTests
{
    private const string Collector = "http://127.0.0.1:4815";

    private static readonly Dictionary<string, EpubResource> Container = new(StringComparer.Ordinal)
    {
        ["OEBPS/ch1.xhtml"] = new(Encoding.UTF8.GetBytes("<html><body>One</body></html>"), "application/xhtml+xml"),
        ["OEBPS/cover.png"] = new([0x89, 0x50, 0x4E, 0x47, 1, 2, 3, 4, 5, 6], "image/png"),
    };

    private static EpubHost Host(string id = "fixture-1") =>
        new(id, () => """{"metadata":{"title":"Fixture"}}""", () => "[]", href => Container.GetValueOrDefault(href), () => Encoding.UTF8.GetBytes("/* bundle */"));

    [Fact]
    public void The_eight_vectors_arrive_nowhere()
    {
        var view = new FakeWebView2(Host());

        view.FireAll(Collector);

        Assert.Empty(view.Arrivals);
        Assert.Equal(8, view.StoppedBy.Count);
        Assert.All(view.StoppedBy.Values, stopped => Assert.NotEqual(EgressLock.None, stopped));
    }

    [Fact]
    public void Each_lock_alone_stops_what_it_governs()
    {
        var policyOnly = new FakeWebView2(Host(), EgressLock.Policy);
        policyOnly.FireAll(Collector);
        // The policy has no say over a top-level navigation; every resource load, the socket included, is its.
        Assert.Equal(new[] { "Navigation -> " + Collector + "/hit/navigation" }, policyOnly.Arrivals);

        var filterOnly = new FakeWebView2(Host(), EgressLock.Filter);
        filterOnly.FireAll(Collector);
        // WebResourceRequested may not see a WebSocket handshake, which is why the policy carries connect-src.
        Assert.Equal(new[] { "Socket -> " + Collector.Replace("http", "ws", StringComparison.Ordinal) + "/hit/socket" }, filterOnly.Arrivals);

        var navigationOnly = new FakeWebView2(Host(), EgressLock.Navigation);
        navigationOnly.FireAll(Collector);
        Assert.Equal(EgressLock.Navigation, navigationOnly.StoppedBy[EgressVector.Navigation]);
        Assert.Equal(EgressLock.Navigation, navigationOnly.StoppedBy[EgressVector.Frame]);
    }

    [Fact]
    public void The_renderers_own_loads_pass_every_lock()
    {
        var host = Host();
        var view = new FakeWebView2(host);

        Assert.Equal(EgressLock.None, view.Request(host.ReaderPageUrl, EpubRequestContext.Document));
        Assert.Equal(EgressLock.None, view.Request(host.Origin + "storyarc-epub.js", EpubRequestContext.Script));
        Assert.Equal(EgressLock.None, view.Request(host.SelfUrl, EpubRequestContext.Fetch));
        Assert.Equal(EgressLock.None, view.Request(host.UrlFor("OEBPS/ch1.xhtml"), EpubRequestContext.Fetch));
        Assert.Equal(EgressLock.None, view.Request(host.UrlFor("OEBPS/cover.png"), EpubRequestContext.Image));
        Assert.Equal(EgressLock.None, view.Request("blob:" + host.Origin + "0c6b7f2e", EpubRequestContext.Frame));
        Assert.Equal(EgressLock.None, view.Request("about:blank", EpubRequestContext.Frame));
    }

    [Fact]
    public void A_navigation_is_allowed_only_within_the_origin_and_a_frame_also_to_its_own_blobs()
    {
        var host = Host();

        Assert.True(host.AllowsNavigation(host.ReaderPageUrl, isFrame: false));
        Assert.False(host.AllowsNavigation("https://example.com/", isFrame: false));
        Assert.False(host.AllowsNavigation("storyarc-epub://other-book/index.html", isFrame: false));
        Assert.False(host.AllowsNavigation("blob:" + host.Origin + "x", isFrame: false));
        Assert.True(host.AllowsNavigation("blob:" + host.Origin + "x", isFrame: true));
        Assert.False(host.AllowsNavigation("blob:storyarc-epub://other-book/x", isFrame: true));
        Assert.False(host.AllowsNavigation("about:settings", isFrame: true));
        Assert.False(host.AllowsNavigation("not a url", isFrame: true));
    }

    [Fact]
    public void Every_answer_carries_the_policy_and_an_off_origin_request_is_refused_with_no_body()
    {
        var host = Host();

        foreach (var url in new[] { host.ReaderPageUrl, host.Origin, host.Origin + "reader.js", host.Origin + "storyarc-epub.js", host.SelfUrl, host.Origin + "positions.json", host.UrlFor("OEBPS/ch1.xhtml") })
        {
            var answer = host.Answer(url, EpubRequestContext.Fetch);
            Assert.Equal(200, answer.Status);
            Assert.Equal(EpubHost.ContentSecurityPolicy, answer.Header("Content-Security-Policy"));
            Assert.Equal("no-store", answer.Header("Cache-Control"));
            Assert.Equal(answer.Body.Length.ToString(System.Globalization.CultureInfo.InvariantCulture), answer.Header("Content-Length"));
        }

        var denied = host.Answer(Collector + "/hit/fetch", EpubRequestContext.Fetch);
        Assert.True(denied.IsDenied);
        Assert.Equal(0, denied.Body.Length);
        Assert.Equal(EpubHost.ContentSecurityPolicy, denied.Header("Content-Security-Policy"));

        var otherBook = host.Answer("storyarc-epub://other-book/OEBPS/ch1.xhtml", EpubRequestContext.Fetch);
        Assert.True(otherBook.IsDenied);
    }

    [Fact]
    public void A_resource_is_served_with_its_declared_type_and_a_missing_one_is_404()
    {
        var host = Host();

        var cover = host.Answer(host.UrlFor("OEBPS/cover.png"), EpubRequestContext.Image);
        Assert.Equal("image/png", cover.MediaType);
        Assert.Equal(Container["OEBPS/cover.png"].Bytes, cover.Body.ToArray());

        var chapter = host.Answer(host.UrlFor("OEBPS/ch1.xhtml"), EpubRequestContext.Frame);
        Assert.Equal("application/xhtml+xml", chapter.Header("Content-Type"));

        Assert.Equal(404, host.Answer(host.UrlFor("OEBPS/missing.png"), EpubRequestContext.Image).Status);
        Assert.Equal(404, host.Answer(host.Origin + "OEBPS/../../secret", EpubRequestContext.Fetch).Status);
    }

    [Fact]
    public void The_manifest_is_served_at_the_self_url_the_core_was_given()
    {
        var host = Host();

        Assert.Equal("storyarc-epub://fixture-1/manifest.json", host.SelfUrl);
        var manifest = host.Answer(host.SelfUrl, EpubRequestContext.Fetch);
        Assert.Equal("application/webpub+json; charset=utf-8", manifest.MediaType);
        Assert.Contains("Fixture", Encoding.UTF8.GetString(manifest.Body.Span));
    }

    [Fact]
    public void The_reader_page_loads_the_bundle_and_its_script_from_the_origin_with_no_inline_script()
    {
        var host = Host();

        var page = Encoding.UTF8.GetString(host.Answer(host.ReaderPageUrl, EpubRequestContext.Document).Body.Span);
        Assert.Contains("<script src=\"/storyarc-epub.js\"></script>", page, StringComparison.Ordinal);
        Assert.Contains("<script src=\"/reader.js\"></script>", page, StringComparison.Ordinal);
        Assert.DoesNotContain("<script>", page, StringComparison.Ordinal);

        var script = Encoding.UTF8.GetString(host.Answer(host.Origin + "reader.js", EpubRequestContext.Script).Body.Span);
        Assert.Contains("StoryArcEpub.open(", script, StringComparison.Ordinal);
        Assert.Contains("fetch('/manifest.json')", script, StringComparison.Ordinal);
        Assert.Contains("window.chrome.webview", script, StringComparison.Ordinal);
    }

    [Theory]
    [InlineData("bytes=0-3", 206, "bytes 0-3/10", 4)]
    [InlineData("bytes=8-", 206, "bytes 8-9/10", 2)]
    [InlineData("bytes=-2", 206, "bytes 8-9/10", 2)]
    [InlineData("bytes=4-100", 206, "bytes 4-9/10", 6)]
    [InlineData("bytes=10-", 416, "bytes */10", 0)]
    [InlineData("items=0-3", 200, null, 10)]
    public void A_range_is_answered_with_the_span_asked_as_an_http_server_would(string range, int status, string? contentRange, int length)
    {
        var host = Host();

        var answer = host.Answer(host.UrlFor("OEBPS/cover.png"), EpubRequestContext.Media, range);

        Assert.Equal(status, answer.Status);
        Assert.Equal(contentRange, answer.Header("Content-Range"));
        Assert.Equal(length, answer.Body.Length);
        if (status == 206)
        {
            var range = contentRange!;
            var start = int.Parse(range[6..range.IndexOf('-', StringComparison.Ordinal)], System.Globalization.CultureInfo.InvariantCulture);
            Assert.Equal(Container["OEBPS/cover.png"].Bytes.Skip(start).Take(length), answer.Body.ToArray());
        }
    }

    [Fact]
    public void The_header_block_is_one_header_a_line_as_create_web_resource_response_takes_it()
    {
        var answer = Host().Answer(Host().SelfUrl, EpubRequestContext.Fetch);

        var lines = answer.HeaderBlock.Split('\n');
        Assert.All(lines, line => Assert.Contains(": ", line, StringComparison.Ordinal));
        Assert.Contains("Content-Security-Policy: default-src 'none'", answer.HeaderBlock, StringComparison.Ordinal);
    }

    [Fact]
    public void The_policy_lets_the_renderer_fetch_chapters_and_build_blob_frames_and_nothing_reach_a_host()
    {
        var self = "storyarc-epub://fixture-1/";

        Assert.True(ContentSecurityPolicy.Allows(EpubHost.ContentSecurityPolicy, self, new Uri(self + "OEBPS/ch1.xhtml"), EpubRequestContext.Fetch));
        Assert.True(ContentSecurityPolicy.Allows(EpubHost.ContentSecurityPolicy, self, new Uri("blob:" + self + "abc"), EpubRequestContext.Frame));
        Assert.True(ContentSecurityPolicy.Allows(EpubHost.ContentSecurityPolicy, self, new Uri("data:image/png;base64,AA=="), EpubRequestContext.Image));
        Assert.False(ContentSecurityPolicy.Allows(EpubHost.ContentSecurityPolicy, self, new Uri("https://track.example/p.png"), EpubRequestContext.Image));
        Assert.False(ContentSecurityPolicy.Allows(EpubHost.ContentSecurityPolicy, self, new Uri("wss://track.example/s"), EpubRequestContext.WebSocket));
        Assert.False(ContentSecurityPolicy.Allows(EpubHost.ContentSecurityPolicy, self, new Uri("https://cdn.example/f.woff2"), EpubRequestContext.Font));
        Assert.False(ContentSecurityPolicy.Allows(EpubHost.ContentSecurityPolicy, self, new Uri("https://example.com/"), EpubRequestContext.Other));
    }

    [Fact]
    public void A_publication_id_is_a_stable_digest_of_its_path_and_an_unsafe_id_is_refused()
    {
        var id = EpubHost.IdFor("C:\\Books\\A Book.epub");

        Assert.Equal(32, id.Length);
        Assert.Equal(id, EpubHost.IdFor("C:\\Books\\A Book.epub"));
        Assert.NotEqual(id, EpubHost.IdFor("C:\\Books\\Another.epub"));
        Assert.Matches("^[0-9a-f]{32}$", id);
        Assert.Throws<ArgumentException>(() => Host("A Book"));
        Assert.Throws<ArgumentException>(() => Host(""));
    }

    [Fact]
    public void Renderer_messages_parse_by_type_and_sequence_and_a_locator_gives_the_position()
    {
        var locator = RendererMessage.TryParse("""{"type":"locator","seq":7,"locator":{"href":"OEBPS/ch2.xhtml","locations":{"position":2,"totalProgression":0.5}}}""");

        Assert.NotNull(locator);
        Assert.Equal(("locator", 7L), (locator.Type, locator.Seq));
        Assert.Equal((2, 0.5), locator.Position());

        Assert.Null(RendererMessage.TryParse("not json"));
        Assert.Null(RendererMessage.TryParse("""{"seq":1}"""));
        Assert.Null(RendererMessage.TryParse("""{"type":"ready","seq":1}""")!.Position());

        var link = RendererMessage.TryParse("""{"type":"link","seq":9,"href":"https://example.com/more"}""");
        Assert.Equal(new Uri("https://example.com/more"), link!.OutboundLink());
        Assert.Null(RendererMessage.TryParse("""{"type":"link","seq":9,"href":"mailto:a@b"}""")!.OutboundLink());
    }

    [Fact]
    public void Host_commands_are_numbered_in_order_and_carry_their_fields()
    {
        var commands = new HostCommands();

        Assert.Equal("""{"type":"next","seq":1}""", commands.Next());
        Assert.Equal("""{"type":"previous","seq":2}""", commands.Previous());
        var search = commands.Search("s1", "whale");
        Assert.Contains("\"query\":\"whale\"", search, StringComparison.Ordinal);
        Assert.Contains("\"seq\":3", search, StringComparison.Ordinal);
        var go = commands.Go("""{"href":"OEBPS/ch1.xhtml","locations":{"position":1}}""");
        Assert.Contains("\"locator\":{\"href\":\"OEBPS/ch1.xhtml\"", go, StringComparison.Ordinal);
        var theme = commands.Theme("sepia", new Dictionary<string, string> { ["background"] = "#f4ecd8" });
        Assert.Contains("\"name\":\"sepia\"", theme, StringComparison.Ordinal);
    }

    [Fact]
    public void An_epub_position_maps_onto_the_stores_page_index_and_back_onto_a_locator()
    {
        const string positions = """[{"href":"a","locations":{"position":1}},{"href":"b","locations":{"position":2}}]""";

        Assert.Equal(2, EpubProgress.Count(positions));
        Assert.Equal(0, EpubProgress.PageIndex(1, 2));
        Assert.Equal(1, EpubProgress.PageIndex(2, 2));
        Assert.Equal(1, EpubProgress.PageIndex(9, 2));
        Assert.Equal(0, EpubProgress.PageIndex(0, 0));
        Assert.Contains("\"href\":\"b\"", EpubProgress.LocatorAt(positions, 1), StringComparison.Ordinal);
        Assert.Contains("\"href\":\"b\"", EpubProgress.LocatorAt(positions, 5), StringComparison.Ordinal);
        Assert.Null(EpubProgress.LocatorAt("[]", 0));
        Assert.Equal("Position 2 of 2", EpubProgress.Label("Position {0} of {1}", 2, 2));
    }
}
