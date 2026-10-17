using System.Text.Json;
using StoryArc.Interop.Network;

namespace StoryArc.Interop.Sources;

/// <summary>The credential a check or a request uses, read from the vault for the call and never stored with the source.</summary>
public sealed record SourceSecrets(string? Password = null, string? Token = null, string? ApiKey = null)
{
    public static SourceSecrets None { get; } = new();

    /// <summary>Never prints a credential.</summary>
    public override string ToString() => "SourceSecrets";
}

/// <summary>
/// What checking a source found: it answered (with what the connection says of itself, for a share its dialect and whether it is encrypted),
/// or the named problem. A source that does not answer is grey, never red.
/// </summary>
public sealed record SourceCheck(bool IsConnected, string? Transport, SourceFailure? Failure);

/// <summary>
/// Checks a source against its server through the core, as the add sheet and the Test action do: a share connects and states its dialect and
/// encryption, a catalogue serves its root page, a Kavita server accepts the API key. Blocks, so the app runs it off the interface thread.
/// </summary>
public static class SourceProbe
{
    public static SourceCheck Check(CoreRuntime runtime, CoreHttp http, NetworkSource source, SourceSecrets secrets)
    {
        try
        {
            switch (source.Kind)
            {
                case NetworkSourceKind.NetworkShare:
                    using (var share = SmbShare.Connect(runtime, new SmbConnection(source.Address, source.Port, source.Username, secrets.Password)))
                    {
                        var identity = share.Identity();
                        return new SourceCheck(true, identity.Dialect + (identity.IsEncrypted ? " · encrypted" : " · not encrypted"), null);
                    }

                case NetworkSourceKind.OpdsCatalogue:
                    _ = http.OpdsFeed(new OpdsRequest(source.Address, Username: source.Username, Password: secrets.Password, Token: secrets.Token));
                    return new SourceCheck(true, null, null);

                default:
                    _ = http.KavitaConnect(source.Address, secrets.ApiKey ?? string.Empty);
                    return new SourceCheck(true, null, null);
            }
        }
        catch (StoryArcException error)
        {
            return new SourceCheck(false, null, SourceFailure.Of(error));
        }
        catch (JsonException)
        {
            return new SourceCheck(false, null, new SourceFailure(SourceProblem.Unexpected, null, null));
        }
    }
}
