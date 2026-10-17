using System.Reflection;
using System.Text;
using StoryArc.Interop;
using StoryArc.Interop.Data;
using StoryArc.Interop.Network;
using StoryArc.Interop.Tests.Support;
using Xunit.Abstractions;

namespace StoryArc.Interop.Tests.Network;

/// <summary>
/// The wave 3 network seam through the C# wrappers (desktop-clients task 3.21): the runtime, the HTTP client and its pins,
/// SMB, OPDS, Kavita, the network state and a download. Each test starts the server it needs: a loopback server here, or the
/// mock of <c>scripts/</c> when node is on the PATH. The Samba fixture needs Docker, so the SMB tests that need it say why
/// they stopped when nothing answers, as the core's own tests do.
/// </summary>
public sealed class NetworkSeamTests(ITestOutputHelper output)
{
    /// <summary>Nothing listens here, by design (AGENTS.md, the fixture port table).</summary>
    private const int RefusedPort = 4999;

    private const string TinyFeed = """
        <feed xmlns="http://www.w3.org/2005/Atom"><title>Tiny</title>
        <entry><title>Shelf</title><id>s</id><link rel="subsection" href="/shelf" type="application/atom+xml;profile=opds-catalog"/></entry></feed>
        """;

    [Fact]
    public void Every_status_code_the_core_defines_has_a_name_here()
    {
        var constants = typeof(NativeMethods)
            .GetFields(BindingFlags.Static | BindingFlags.NonPublic | BindingFlags.Public)
            .Where(field => field.Name.StartsWith("STORYARC_ERROR_", StringComparison.Ordinal))
            .Select(field => (int)field.GetRawConstantValue()!)
            .ToList();

        Assert.NotEmpty(constants);
        Assert.All(constants, code => Assert.True(Enum.IsDefined((StoryArcStatus)code), $"status {code} has no StoryArcStatus"));
    }

    [Fact]
    public void The_network_state_is_one_of_three_and_an_undescribed_connection_is_not_metered()
    {
        using var runtime = CoreRuntime.Create();

        var state = runtime.Connection();

        Assert.True(Enum.IsDefined(state));
        // Where the system describes nothing, as on the Mac and Linux hosts of this suite, the answer is unmetered.
        if (!OperatingSystem.IsWindows())
        {
            Assert.NotEqual(ConnectionState.Metered, state);
        }
    }

    [Fact]
    public void The_runtime_outlives_every_handle_made_from_it_whatever_order_they_are_disposed_in()
    {
        var runtime = CoreRuntime.Create();
        var http = CoreHttp.Create(runtime, new PinBook());

        runtime.Dispose();
        Assert.False(runtime.IsClosed, "the client still needs the runtime");
        using var server = LocalServer.Serving(Encoding.UTF8.GetBytes(TinyFeed), "application/atom+xml");
        Assert.Equal("Tiny", http.OpdsFeed(new OpdsRequest(server.Root)).Title);

        http.Dispose();
        Assert.True(runtime.IsClosed);
    }

    [Fact]
    public void A_catalogue_page_crosses_as_a_record()
    {
        using var runtime = CoreRuntime.Create();
        using var http = CoreHttp.Create(runtime, new PinBook());
        using var server = LocalServer.Serving(Encoding.UTF8.GetBytes(TinyFeed), "application/atom+xml");

        var page = http.OpdsFeed(new OpdsRequest(server.Root));

        Assert.Equal("Tiny", page.Title);
        Assert.Equal("atom", page.Dialect);
        var shelf = Assert.Single(page.Navigation!);
        Assert.Equal("Shelf", shelf.Title);
        Assert.False(page.LocalOnly);
    }

    [Fact]
    public void A_catalogue_that_does_not_answer_is_unreachable_and_a_request_never_prints_its_password()
    {
        using var runtime = CoreRuntime.Create();
        using var http = CoreHttp.Create(runtime, new PinBook());
        var request = new OpdsRequest($"http://127.0.0.1:{RefusedPort}/", Username: "ada", Password: "lovelace-password");

        var error = Assert.Throws<StoryArcException>(() => http.OpdsFeed(request));

        Assert.Equal(StoryArcStatus.Unreachable, error.Status);
        Assert.DoesNotContain("lovelace-password", request.ToString(), StringComparison.Ordinal);
        Assert.DoesNotContain("lovelace-password", error.ToString(), StringComparison.Ordinal);
    }

    [Fact]
    public void A_wrong_kind_of_handle_is_refused_by_name()
    {
        using var runtime = CoreRuntime.Create();
        using var http = CoreHttp.Create(runtime, new PinBook());

        var error = Assert.Throws<StoryArcException>(() => http.OpdsFeed(new OpdsRequest("not an address")));

        Assert.Equal(StoryArcStatus.InvalidArgument, error.Status);
    }

    [Fact]
    public void The_catalogue_mock_serves_both_dialects_a_search_and_a_sign_in()
    {
        using var corpus = Corpus.TemporaryFolder();
        corpus.Copy("comics/natural-sort.cbz");
        corpus.Copy("comics/manga-metadata.cbz");
        using var mock = MockServer.TryStart("opds-server.mjs", corpus.FullPath, out var reason);
        if (mock is null && Skip.Because(output, reason))
        {
            return;
        }

        using var runtime = CoreRuntime.Create();
        using var http = CoreHttp.Create(runtime, new PinBook());
        var root = $"http://127.0.0.1:{mock!.Port}/opds";

        var home = http.OpdsFeed(new OpdsRequest(root));
        Assert.Equal("StoryArc Test Catalogue", home.Title);
        Assert.Contains(home.Navigation!, section => section.Title == "All publications");

        var all = http.OpdsFeed(new OpdsRequest(root, Url: $"http://127.0.0.1:{mock.Port}/opds/all"));
        // The mock lists its three scripted demonstration entries (a flaky, an unopenable and a slow transfer) ahead of the
        // corpus on the first page of "All publications", so the two copied books arrive as five.
        Assert.Equal(5, all.Publications!.Count);
        Assert.Contains(all.Publications!, entry => entry.Title == "natural-sort");
        Assert.Contains(all.Publications!, entry => entry.Title == "manga-metadata");
        Assert.All(all.Publications!, entry => Assert.True(entry.CanDownload, entry.Title + " names a file the app can open"));

        var json = http.OpdsFeed(new OpdsRequest($"http://127.0.0.1:{mock.Port}/opds2"));
        Assert.Equal("json", json.Dialect);

        var refused = Assert.Throws<StoryArcException>(() => http.OpdsFeed(new OpdsRequest($"http://127.0.0.1:{mock.Port}/private")));
        Assert.Equal(StoryArcStatus.Unauthorized, refused.Status);
        Assert.Null(CertificateChallenge.TryParse(refused.CoreMessage));

        var signedIn = http.OpdsFeed(new OpdsRequest($"http://127.0.0.1:{mock.Port}/private", Username: "ada", Password: "lovelace"));
        Assert.NotEmpty(signedIn.Publications!);
    }

    [Fact]
    public void A_certificate_the_system_does_not_trust_is_named_by_its_fingerprint_for_the_reader_to_pin()
    {
        var challenge = CertificateChallenge.TryParse(
            "nas.local presented a certificate this system does not trust; its fingerprint is AB:CD:EF");

        Assert.Equal(new CertificateChallenge("nas.local", "AB:CD:EF"), challenge);
        Assert.Null(CertificateChallenge.TryParse("the catalogue asks to sign in"));
        Assert.Null(CertificateChallenge.TryParse(null));
    }

    [Fact]
    public void A_pin_goes_to_the_book_and_every_later_client_starts_with_it()
    {
        using var runtime = CoreRuntime.Create();
        var book = new PinBook();
        using (var first = CoreHttp.Create(runtime, book))
        {
            first.Pin("NAS.local", "ab:cd");
        }

        using var second = CoreHttp.Create(runtime, book);

        var pin = Assert.Single(second.Pins.All());
        Assert.Equal(new CertificatePin("nas.local", "AB:CD"), pin);
        var restored = PinBook.Restore(book.Save());
        Assert.Equal(pin, Assert.Single(restored.All()));
        Assert.Empty(PinBook.Restore("{not json").All());
        book.Remove("nas.local");
        Assert.Empty(book.All());
    }

    [Fact]
    public void A_share_that_does_not_answer_is_unreachable_and_grey()
    {
        using var runtime = CoreRuntime.Create();

        var error = Assert.Throws<StoryArcException>(
            () => SmbShare.Connect(runtime, new SmbConnection("smb://127.0.0.1/comics", Port: RefusedPort)));

        Assert.Equal(StoryArcStatus.Unreachable, error.Status);
        Assert.Equal("storyarc_smb_connect", error.Call);
    }

    [Fact]
    public void An_address_that_is_not_a_share_is_refused()
    {
        using var runtime = CoreRuntime.Create();

        var error = Assert.Throws<StoryArcException>(() => SmbShare.Connect(runtime, new SmbConnection("nothing")));

        Assert.Equal(StoryArcStatus.InvalidArgument, error.Status);
    }

    [Fact]
    public void The_samba_fixture_reports_its_dialect_and_encryption_and_lists_its_folders()
    {
        // The fixture is `pnpm smb` (Docker or Samba on the host), port 4445 unless STORYARC_SMB_PORT says otherwise.
        var port = int.TryParse(Environment.GetEnvironmentVariable("STORYARC_SMB_PORT"), out var chosen) ? chosen : 4445;
        var user = Environment.GetEnvironmentVariable("STORYARC_SMB_USER") ?? Environment.UserName;
        using var runtime = CoreRuntime.Create();
        SmbShare share;
        try
        {
            share = SmbShare.Connect(runtime, new SmbConnection("smb://127.0.0.1/Comics", port, user, "lovelace"));
        }
        catch (StoryArcException error) when (error.Status == StoryArcStatus.Unreachable)
        {
            Skip.Because(output, $"no SMB server answers on {port} (pnpm smb needs Docker or Samba)");
            return;
        }

        using (share)
        {
            var identity = share.Identity();
            Assert.Equal("SMB 3.1.1", identity.Dialect);
            Assert.True(identity.IsEncrypted, "an SMB 3 server that supports encryption is asked for it");
            Assert.NotEmpty(share.List());
        }
    }

    [Fact]
    public void A_wrong_password_is_named_apart_from_an_unreachable_host()
    {
        var port = int.TryParse(Environment.GetEnvironmentVariable("STORYARC_SMB_PORT"), out var chosen) ? chosen : 4445;
        var user = Environment.GetEnvironmentVariable("STORYARC_SMB_USER") ?? Environment.UserName;
        using var runtime = CoreRuntime.Create();

        try
        {
            using var share = SmbShare.Connect(runtime, new SmbConnection("smb://127.0.0.1/Comics", port, user, "wrong-password"));
            Assert.Fail("a wrong password must not connect");
        }
        catch (StoryArcException error) when (error.Status == StoryArcStatus.Unreachable)
        {
            Skip.Because(output, $"no SMB server answers on {port} (pnpm smb needs Docker or Samba)");
        }
        catch (StoryArcException error)
        {
            Assert.Equal(StoryArcStatus.Unauthorized, error.Status);
        }
    }

    [Fact]
    public void The_kavita_mock_signs_in_lists_libraries_series_and_volumes_and_refuses_a_bad_key()
    {
        using var corpus = Corpus.TemporaryFolder();
        corpus.Copy("comics/natural-sort.cbz");
        corpus.Copy("comics/manga-metadata.cbz");
        using var mock = MockServer.TryStart("kavita-server.mjs", corpus.FullPath, out var reason);
        if (mock is null && Skip.Because(output, reason))
        {
            return;
        }

        using var runtime = CoreRuntime.Create();
        using var http = CoreHttp.Create(runtime, new PinBook());
        var address = $"http://127.0.0.1:{mock!.Port}";
        const string key = "storyarc-test-key";

        Assert.Equal("ada", http.KavitaConnect(address, key));
        Assert.NotEmpty(http.KavitaLibraries(address, key));
        var series = http.KavitaSeriesOf(address, key);
        Assert.Equal(2, series.Count);
        var volumes = http.KavitaVolumes(address, key, series[0].Id);
        var chapter = Assert.Single(Assert.Single(volumes).Chapters!);
        Assert.True(chapter.Pages > 0);
        Assert.NotNull(http.KavitaContinuePoint(address, key, series[0].Id));

        var refused = Assert.Throws<StoryArcException>(() => http.KavitaLibraries(address, "not-the-key"));
        Assert.Equal(StoryArcStatus.Unauthorized, refused.Status);
    }

    [Fact]
    public void A_kavita_server_that_does_not_answer_is_unreachable()
    {
        using var runtime = CoreRuntime.Create();
        using var http = CoreHttp.Create(runtime, new PinBook());

        var error = Assert.Throws<StoryArcException>(() => http.KavitaLibraries($"http://127.0.0.1:{RefusedPort}", "key"));

        Assert.Equal(StoryArcStatus.Unreachable, error.Status);
    }

    [Fact]
    public void A_download_lands_verified_and_reports_its_progress_on_the_calling_thread()
    {
        var body = File.ReadAllBytes(Corpus.Path("comics/natural-sort.cbz"));
        using var server = LocalServer.Serving(body, "application/vnd.comicbook+zip");
        using var folder = Corpus.TemporaryFolder();
        using var runtime = CoreRuntime.Create();
        using var http = CoreHttp.Create(runtime, new PinBook());
        var reports = new Reports();

        var landing = http.Fetch(new DownloadRequest(folder.FullPath, "opds:1", "Natural Sort", server.Root), reports);

        Assert.Equal(Resumption.Fresh, landing.Resumption);
        Assert.Equal(body.Length, landing.Length);
        Assert.Equal(body, File.ReadAllBytes(landing.Path));
        // The core files a download under the catalogue's title ("Natural Sort.cbz") and indexes it there, so the record
        // shows the title the catalogue gave, not the stem the bytes were served from.
        Assert.Equal("Natural Sort", landing.Publication!.DisplayTitle);
        Assert.Equal("Natural Sort.cbz", Path.GetFileName(landing.Path));
        Assert.Equal(new DownloadProgress((ulong)body.Length, body.Length), reports.Last);
        Assert.Equal(1.0, reports.Last!.Value.Fraction);
        Assert.Equal(body.Length, StorageBytes.Of(folder.FullPath));
    }

    [Fact]
    public void Bytes_that_are_not_a_publication_are_unreadable_and_a_raised_token_keeps_the_file_for_a_resume()
    {
        using var folder = Corpus.TemporaryFolder();
        using var runtime = CoreRuntime.Create();
        using var http = CoreHttp.Create(runtime, new PinBook());
        using var junk = LocalServer.Serving(Encoding.UTF8.GetBytes("this is not a book"), "application/octet-stream");

        var unreadable = Assert.Throws<StoryArcException>(
            () => http.Fetch(new DownloadRequest(folder.FullPath, "opds:2", "Junk", junk.Root)));
        Assert.Equal(StoryArcStatus.Unreadable, unreadable.Status);

        using var token = new CancelToken();
        token.Cancel();
        using var real = LocalServer.Serving(File.ReadAllBytes(Corpus.Path("comics/single-page.cbz")), "application/vnd.comicbook+zip");
        var cancelled = Assert.Throws<StoryArcException>(
            () => http.Fetch(new DownloadRequest(folder.FullPath, "opds:3", "Single", real.Root), cancel: token));
        Assert.Equal(StoryArcStatus.Cancelled, cancelled.Status);
        Assert.False(token.IsClosed, "the fetch releases its hold on the token, it does not free it");
    }

    [Fact]
    public void A_progress_handler_that_throws_never_reaches_the_core()
    {
        var body = File.ReadAllBytes(Corpus.Path("comics/single-page.cbz"));
        using var server = LocalServer.Serving(body, "application/vnd.comicbook+zip");
        using var folder = Corpus.TemporaryFolder();
        using var runtime = CoreRuntime.Create();
        using var http = CoreHttp.Create(runtime, new PinBook());

        var landing = http.Fetch(
            new DownloadRequest(folder.FullPath, "opds:4", "Single", server.Root), new Throwing());

        Assert.Equal(body.Length, landing.Length);
    }

    [Theory]
    [InlineData("\"fresh\"", Resumption.Fresh, 0UL)]
    [InlineData("\"restarted\"", Resumption.Restarted, 0UL)]
    [InlineData("{\"resumed\":{\"from\":4096}}", Resumption.Resumed, 4096UL)]
    public void The_three_ways_a_transfer_began_are_read_from_the_cores_own_shape(string json, Resumption expected, ulong from)
    {
        var (resumption, resumedFrom) = CoreHttp.ResumptionOf(System.Text.Json.Nodes.JsonNode.Parse(json));

        Assert.Equal(expected, resumption);
        Assert.Equal(from, resumedFrom);
    }

    private sealed class Reports : IProgress<DownloadProgress>
    {
        public DownloadProgress? Last { get; private set; }

        public void Report(DownloadProgress value) => Last = value;
    }

    private sealed class Throwing : IProgress<DownloadProgress>
    {
        public void Report(DownloadProgress value) => throw new InvalidOperationException("a handler that fails");
    }
}
