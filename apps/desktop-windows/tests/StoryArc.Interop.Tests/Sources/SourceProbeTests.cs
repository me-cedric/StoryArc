using System.Text;
using StoryArc.Interop.Network;
using StoryArc.Interop.Sources;
using StoryArc.Interop.Tests.Support;
using Xunit.Abstractions;

namespace StoryArc.Interop.Tests.Sources;

/// <summary>Checking a source against its server, the way the add sheet and Test do (desktop-clients task 3.21): each answer and each failure named apart.</summary>
public sealed class SourceProbeTests(ITestOutputHelper output)
{
    private const string Feed = """<feed xmlns="http://www.w3.org/2005/Atom"><title>Tiny</title></feed>""";

    private static NetworkSource Source(NetworkSourceKind kind, string address, int? port = null) =>
        new("11111111-1111-1111-1111-111111111111", kind, "Source", address, port);

    [Fact]
    public void A_catalogue_that_answers_is_connected()
    {
        using var runtime = CoreRuntime.Create();
        using var http = CoreHttp.Create(runtime, new PinBook());
        using var server = LocalServer.Serving(Encoding.UTF8.GetBytes(Feed), "application/atom+xml");

        var check = SourceProbe.Check(runtime, http, Source(NetworkSourceKind.OpdsCatalogue, server.Root), SourceSecrets.None);

        Assert.True(check.IsConnected);
        Assert.Null(check.Failure);
    }

    [Fact]
    public void A_catalogue_a_kavita_server_and_a_share_that_do_not_answer_are_each_unreachable_and_grey()
    {
        using var runtime = CoreRuntime.Create();
        using var http = CoreHttp.Create(runtime, new PinBook());

        var opds = SourceProbe.Check(runtime, http, Source(NetworkSourceKind.OpdsCatalogue, "http://127.0.0.1:4999/"), SourceSecrets.None);
        var kavita = SourceProbe.Check(runtime, http, Source(NetworkSourceKind.KavitaServer, "http://127.0.0.1:4999"), new SourceSecrets(ApiKey: "k"));
        var share = SourceProbe.Check(runtime, http, Source(NetworkSourceKind.NetworkShare, "smb://127.0.0.1/comics", 4999), SourceSecrets.None);

        Assert.All(new[] { opds, kavita, share }, check =>
        {
            Assert.False(check.IsConnected);
            Assert.Equal(SourceProblem.HostUnreachable, check.Failure!.Problem);
        });
    }

    [Fact]
    public void An_address_that_is_not_an_address_is_named_unexpected_not_a_crash()
    {
        using var runtime = CoreRuntime.Create();
        using var http = CoreHttp.Create(runtime, new PinBook());

        var check = SourceProbe.Check(runtime, http, Source(NetworkSourceKind.NetworkShare, "nothing"), SourceSecrets.None);

        Assert.False(check.IsConnected);
        Assert.NotNull(check.Failure);
    }

    [Fact]
    public void The_kavita_mock_accepts_its_key_and_refuses_another_as_a_sign_in_problem()
    {
        using var corpus = Corpus.TemporaryFolder();
        corpus.Copy("comics/natural-sort.cbz");
        using var mock = MockServer.TryStart("kavita-server.mjs", corpus.FullPath, out var reason);
        if (mock is null && Skip.Because(output, reason))
        {
            return;
        }

        using var runtime = CoreRuntime.Create();
        using var http = CoreHttp.Create(runtime, new PinBook());
        var address = $"http://127.0.0.1:{mock!.Port}";

        Assert.True(SourceProbe.Check(runtime, http, Source(NetworkSourceKind.KavitaServer, address), new SourceSecrets(ApiKey: "storyarc-test-key")).IsConnected);
        var refused = SourceProbe.Check(runtime, http, Source(NetworkSourceKind.KavitaServer, address), new SourceSecrets(ApiKey: "wrong"));
        Assert.Equal(SourceProblem.SignInRejected, refused.Failure!.Problem);
    }
}
