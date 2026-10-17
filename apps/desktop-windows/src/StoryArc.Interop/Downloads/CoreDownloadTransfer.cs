using StoryArc.Interop.Data;
using StoryArc.Interop.Network;

namespace StoryArc.Interop.Downloads;

/// <summary>Where a source's files come from and who may receive its credential: the source's root, which alone receives it, and the credential.</summary>
public sealed record DownloadAccess(string Origin, string? Username = null, string? Password = null, string? Token = null)
{
    /// <summary>Never prints the password or the token.</summary>
    public override string ToString() => "DownloadAccess { Origin = " + Origin + " }";
}

/// <summary>
/// The transfer the app uses: the core's <c>storyarc_download_fetch</c> on a client of its own. One client per transfer, because a
/// download holds its handle for as long as it runs and the seam allows one thread at a time per handle; every client starts from the
/// same <see cref="PinBook"/>, so a certificate the reader pinned is trusted by each.
/// </summary>
public sealed class CoreDownloadTransfer(
    CoreRuntime runtime,
    PinBook pins,
    string folder,
    Func<string?, DownloadAccess?> accessOf) : IDownloadTransfer
{
    public DownloadLanding Fetch(DownloadRow row, IProgress<DownloadProgress> progress, CancelToken cancel)
    {
        using var http = CoreHttp.Create(runtime, pins);
        var access = accessOf(row.SourceId);
        var request = new DownloadRequest(
            folder,
            row.Id,
            row.Title,
            row.Remote,
            Origin: access?.Origin,
            Username: access?.Username,
            Password: access?.Password,
            Token: access?.Token);
        return http.Fetch(request, progress, cancel);
    }
}
