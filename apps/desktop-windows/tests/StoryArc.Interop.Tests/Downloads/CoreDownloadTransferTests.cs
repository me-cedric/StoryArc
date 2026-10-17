using StoryArc.Interop.Data;
using StoryArc.Interop.Downloads;
using StoryArc.Interop.Network;
using StoryArc.Interop.Tests.Support;

namespace StoryArc.Interop.Tests.Downloads;

/// <summary>The coordinator over the core's own transfer, end to end against a loopback server: the file lands, and the credential goes to the source's origin only.</summary>
public sealed class CoreDownloadTransferTests
{
    [Fact]
    public async Task A_queued_download_lands_in_the_folder_through_the_core_and_the_row_finishes()
    {
        var body = File.ReadAllBytes(Corpus.Path("comics/natural-sort.cbz"));
        var requests = new List<LocalRequest>();
        using var server = new LocalServer(request =>
        {
            lock (requests)
            {
                requests.Add(request);
            }

            return new LocalResponse(200, body, "application/vnd.comicbook+zip");
        });
        using var folder = Corpus.TemporaryFolder();
        using var runtime = CoreRuntime.Create();
        var landed = new TaskCompletionSource<DownloadLanding>();
        var transfer = new CoreDownloadTransfer(
            runtime,
            new PinBook(),
            folder.FullPath,
            sourceId => sourceId == "opds" ? new DownloadAccess(server.Root, "ada", "lovelace") : null);
        using var coordinator = new DownloadCoordinator(
            transfer,
            DownloadQueue.Empty,
            new DownloadEnvironment(
                () => ConnectionState.Unmetered,
                () => new DownloadPolicySettings(),
                () => 0,
                () => DateTimeOffset.UnixEpoch,
                _ => { },
                (wait, cancel) => Task.CompletedTask));
        coordinator.Landed += (row, landing) => landed.TrySetResult(landing);
        coordinator.Start();

        coordinator.Add("opds:1", "Natural Sort", server.Root + "natural-sort.cbz", "opds", body.Length, byHand: false);
        var landing = await landed.Task.WaitAsync(TimeSpan.FromSeconds(30));
        await coordinator.WhenIdleAsync();

        Assert.Equal(body, File.ReadAllBytes(landing.Path));
        Assert.Equal(DownloadStatus.Finished, coordinator.Queue.Get("opds:1")!.Status);
        Assert.Equal(body.Length, StorageBytes.Of(folder.FullPath));
        LocalRequest sent;
        lock (requests)
        {
            sent = Assert.Single(requests);
        }

        Assert.StartsWith("Basic ", sent.Headers["authorization"], StringComparison.Ordinal);
    }

    [Fact]
    public async Task A_source_with_no_access_sends_no_credential()
    {
        var body = File.ReadAllBytes(Corpus.Path("comics/single-page.cbz"));
        var headers = new List<IReadOnlyDictionary<string, string>>();
        using var server = new LocalServer(request =>
        {
            lock (headers)
            {
                headers.Add(request.Headers);
            }

            return new LocalResponse(200, body, "application/vnd.comicbook+zip");
        });
        using var folder = Corpus.TemporaryFolder();
        using var runtime = CoreRuntime.Create();
        var transfer = new CoreDownloadTransfer(runtime, new PinBook(), folder.FullPath, _ => null);
        using var cancel = new CancelToken();
        var row = new DownloadRow("p", "Single", server.Root, null, DownloadStatus.Queued, null, null, null, 0, null, 0, null, false, 0, null);

        var landing = await Task.Run(() => transfer.Fetch(row, new Progress<DownloadProgress>(), cancel));

        Assert.Equal(body.Length, landing.Length);
        lock (headers)
        {
            Assert.DoesNotContain("authorization", Assert.Single(headers).Keys);
        }
    }
}
