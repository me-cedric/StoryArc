using System.Text.Json;
using System.Text.Json.Serialization;
using StoryArc.Interop.Credentials;
using StoryArc.Interop.Data;
using StoryArc.Interop.Network;

namespace StoryArc.Interop.Sources;

/// <summary>The three kinds of network source. A folder on disk is a <see cref="FolderSource"/>.</summary>
[JsonConverter(typeof(JsonStringEnumConverter<NetworkSourceKind>))]
public enum NetworkSourceKind
{
    /// <summary>An SMB share, spoken to by the core's own client and not the system redirector.</summary>
    NetworkShare,

    /// <summary>An OPDS catalogue, in either dialect.</summary>
    OpdsCatalogue,

    /// <summary>A Kavita server, signed in with an API key.</summary>
    KavitaServer,
}

/// <summary>
/// One network source as its record holds it: an id, what the reader called it, the address, and the user name when there
/// is one. The record holds no credential and no address that carries one: the password, the token or the API key is in the
/// vault under <see cref="Id"/>, and that is the only reference (desktop-experience, "Saving a password").
/// </summary>
public sealed record NetworkSource(string Id, NetworkSourceKind Kind, string Name, string Address, int? Port = null, string? Username = null)
{
    /// <summary>The credential fields this kind of source can hold, for the vault and for removing them with the source.</summary>
    [JsonIgnore]
    public IReadOnlyList<string> CredentialFields => Kind switch
    {
        NetworkSourceKind.KavitaServer => [CredentialField.ApiKey],
        NetworkSourceKind.OpdsCatalogue => [CredentialField.Password, CredentialField.Token],
        _ => [CredentialField.Password],
    };

    /// <summary>The kind as a library document names it.</summary>
    [JsonIgnore]
    public string DocumentKind => Kind switch
    {
        NetworkSourceKind.KavitaServer => "kavitaServer",
        NetworkSourceKind.OpdsCatalogue => "opdsCatalog",
        _ => "networkShare",
    };
}

/// <summary>An address as typed, split into the address to keep and the credentials that were typed into it.</summary>
public sealed record TypedAddress(string Address, string? Username, string? Password)
{
    /// <summary>
    /// Splits <c>user:password@host</c> out of <paramref name="typed"/>. A reader may paste an address with its sign-in in it; the
    /// sign-in then goes to the vault and the record keeps the address without it. <c>smb://reader:hunter2@nas/comics</c> and
    /// <c>https://ada:lovelace@books.example/opds</c> both split; so does a Windows <c>\\host\share</c>, which has none.
    /// </summary>
    public static TypedAddress From(string typed)
    {
        var text = typed.Trim();
        var scheme = text.IndexOf("://", StringComparison.Ordinal);
        if (scheme < 0)
        {
            return new TypedAddress(text, null, null);
        }

        var authorityStart = scheme + 3;
        var authorityEnd = text.IndexOf('/', authorityStart);
        var authority = authorityEnd < 0 ? text[authorityStart..] : text[authorityStart..authorityEnd];
        var at = authority.LastIndexOf('@');
        if (at < 0)
        {
            return new TypedAddress(text, null, null);
        }

        var userinfo = authority[..at];
        var rest = authorityEnd < 0 ? string.Empty : text[authorityEnd..];
        var clean = text[..authorityStart] + authority[(at + 1)..] + rest;
        var colon = userinfo.IndexOf(':');
        return colon < 0
            ? new TypedAddress(clean, Uri.UnescapeDataString(userinfo), null)
            : new TypedAddress(clean, Uri.UnescapeDataString(userinfo[..colon]), Uri.UnescapeDataString(userinfo[(colon + 1)..]));
    }

    /// <summary>The host of the address, for the name a source shows when the reader gave none.</summary>
    public string Host
    {
        get
        {
            var text = Address.Replace('\\', '/').TrimStart('/');
            var scheme = text.IndexOf("://", StringComparison.Ordinal);
            if (scheme >= 0)
            {
                text = text[(scheme + 3)..];
            }

            var end = text.IndexOfAny(['/', ':']);
            return end < 0 ? text : text[..end];
        }
    }
}

/// <summary>
/// The network sources the reader added. Saved as plain JSON beside the folder sources: there is nothing in it to protect
/// but the addresses, and the one place a credential could slip in, a typed address, is cleaned by <see cref="TypedAddress"/> before
/// it gets here.
/// </summary>
public sealed record NetworkSourceList(IReadOnlyList<NetworkSource> Sources)
{
    public static NetworkSourceList Empty { get; } = new([]);

    /// <summary>
    /// The list with a source added. <paramref name="typed"/> is the address as the reader typed it; any sign-in inside it comes back in
    /// <see cref="AddedSource.Typed"/> for the vault and is not in the source. The id is new and lower case.
    /// </summary>
    public AddedSource Adding(NetworkSourceKind kind, string name, string typed, string? username = null, int? port = null)
    {
        var credentials = TypedAddress.From(typed);
        var shownName = string.IsNullOrWhiteSpace(name) ? credentials.Host : name.Trim();
        var source = new NetworkSource(
            Guid.NewGuid().ToString("D").ToLowerInvariant(),
            kind,
            shownName,
            credentials.Address,
            port,
            string.IsNullOrWhiteSpace(username) ? credentials.Username : username.Trim());
        return new AddedSource(new NetworkSourceList([.. Sources, source]), source, credentials);
    }

    /// <summary>
    /// The list with the network sources of a merged library document added, those not already here. A source another device added
    /// arrives with its address and without any credential. A local folder is another machine's path and is left out.
    /// </summary>
    public NetworkSourceList Adopting(IEnumerable<DocumentSource> documentSources)
    {
        var known = Sources.Select(source => source.Id).ToHashSet();
        var added = new List<NetworkSource>();
        foreach (var source in documentSources)
        {
            NetworkSourceKind? kind = source.Kind switch
            {
                "networkShare" => NetworkSourceKind.NetworkShare,
                "opdsCatalog" => NetworkSourceKind.OpdsCatalogue,
                "kavitaServer" => NetworkSourceKind.KavitaServer,
                _ => null,
            };
            if (kind is { } adopted && source.Locator is { Length: > 0 } locator && known.Add(source.Id))
            {
                var typed = TypedAddress.From(locator);
                added.Add(new NetworkSource(source.Id, adopted, source.DisplayName, typed.Address, Port: null, Username: typed.Username));
            }
        }

        return added.Count == 0 ? this : new NetworkSourceList([.. Sources, .. added]);
    }

    public NetworkSourceList Without(string id) => new([.. Sources.Where(source => source.Id != id)]);

    public NetworkSourceList Renaming(string id, string name) =>
        new([.. Sources.Select(source => source.Id == id && !string.IsNullOrWhiteSpace(name) ? source with { Name = name.Trim() } : source)]);

    public NetworkSource? Find(string id) => Sources.FirstOrDefault(source => source.Id == id);

    /// <summary>The sources as a library document carries them, with <paramref name="needSignIn"/> naming those this device holds no credential for.</summary>
    public IReadOnlyList<DocumentSource> ToDocumentSources(ISet<string> needSignIn) =>
        [.. Sources.Select(source => new DocumentSource(source.Id, source.Name, source.DocumentKind, source.Address, needSignIn.Contains(source.Id)))];

    public string Save() => JsonSerializer.Serialize(this, NetworkSourcesJsonContext.Default.NetworkSourceList);

    public static NetworkSourceList Restore(string? text)
    {
        if (string.IsNullOrWhiteSpace(text))
        {
            return Empty;
        }

        try
        {
            return JsonSerializer.Deserialize(text, NetworkSourcesJsonContext.Default.NetworkSourceList) is { Sources: { } sources }
                ? new NetworkSourceList(sources)
                : Empty;
        }
        catch (JsonException)
        {
            return Empty;
        }
    }
}

/// <summary>A source added to the list, and the sign-in that was typed inside its address, for the vault.</summary>
public sealed record AddedSource(NetworkSourceList List, NetworkSource Source, TypedAddress Typed);

[JsonSourceGenerationOptions(WriteIndented = true, PropertyNamingPolicy = JsonKnownNamingPolicy.CamelCase)]
[JsonSerializable(typeof(NetworkSourceList))]
internal sealed partial class NetworkSourcesJsonContext : JsonSerializerContext;

/// <summary>What is wrong with a source, named apart from the others: each is grey, never red, and the other sources stay usable.</summary>
public enum SourceProblem
{
    /// <summary>The host did not answer. The source returns by itself when it does.</summary>
    HostUnreachable,

    /// <summary>The server answered and has no share, or no page, of that name.</summary>
    NotFound,

    /// <summary>The server refused the sign-in: the source needs the reader's credential again.</summary>
    SignInRejected,

    /// <summary>The certificate is not trusted; the reader may pin it after seeing its fingerprint.</summary>
    CertificateNotTrusted,

    /// <summary>The server speaks only SMB 1, which the app refuses by name and never falls back to.</summary>
    Smb1Only,

    /// <summary>The share requires encryption and the connection could not provide it.</summary>
    EncryptionRequired,

    /// <summary>The credential store refused, or the credential is too long for it: the source needs a sign-in.</summary>
    CredentialNotKept,

    /// <summary>The answer was not what a source of that kind sends.</summary>
    Unexpected,
}

/// <summary>
/// A source's problem with the sentence the core gave for it, which names the server setting to change for SMB 1 and
/// for encryption, and the certificate to pin when one is not trusted.
/// </summary>
public sealed record SourceFailure(SourceProblem Problem, string? Remedy, CertificateChallenge? Certificate)
{
    /// <summary>Reads a failed seam call as the problem it names. Every case maps; none is an error colour.</summary>
    public static SourceFailure Of(StoryArcException error)
    {
        var message = error.CoreMessage;
        if (CertificateChallenge.TryParse(message) is { } certificate)
        {
            return new SourceFailure(SourceProblem.CertificateNotTrusted, message, certificate);
        }

        var problem = error.Status switch
        {
            StoryArcStatus.Unreachable => SourceProblem.HostUnreachable,
            StoryArcStatus.NotFound => SourceProblem.NotFound,
            StoryArcStatus.Unauthorized => SourceProblem.SignInRejected,
            StoryArcStatus.Storage => SourceProblem.CredentialNotKept,
            StoryArcStatus.Unsupported when message?.Contains("SMB 1", StringComparison.OrdinalIgnoreCase) == true => SourceProblem.Smb1Only,
            StoryArcStatus.Unsupported when message?.Contains("encrypt", StringComparison.OrdinalIgnoreCase) == true => SourceProblem.EncryptionRequired,
            _ => SourceProblem.Unexpected,
        };
        return new SourceFailure(problem, message, null);
    }
}
