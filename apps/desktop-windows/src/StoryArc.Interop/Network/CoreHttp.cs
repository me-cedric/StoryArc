using System.Text.Json;
using System.Text.Json.Nodes;
using System.Text.Json.Serialization;

namespace StoryArc.Interop.Network;

/// <summary>One certificate the reader accepted for a host, after the app showed the fingerprint.</summary>
public sealed record CertificatePin(string Host, string Fingerprint);

/// <summary>
/// The certificates the reader accepted, per host, shared by every HTTP client of the app. A fingerprint
/// is public, so the book is a plain file beside the source records. Each new client (one per download,
/// see <see cref="CoreHttp"/>) is handed the whole book, so a pin made on one reaches the next.
/// </summary>
public sealed class PinBook
{
    private readonly Lock _gate = new();
    private readonly List<CertificatePin> _pins = [];

    /// <summary>Every pin, for saving beside the source records.</summary>
    public IReadOnlyList<CertificatePin> All()
    {
        lock (_gate)
        {
            return [.. _pins];
        }
    }

    /// <summary>
    /// Records an acceptance, in the form the core compares: a lower-case host and an upper-case fingerprint. The same host and
    /// fingerprint twice is one pin. Answers the pin as kept.
    /// </summary>
    public CertificatePin Add(string host, string fingerprint)
    {
        var pin = new CertificatePin(host.ToLowerInvariant(), fingerprint.ToUpperInvariant());
        lock (_gate)
        {
            if (!_pins.Contains(pin))
            {
                _pins.Add(pin);
            }
        }

        return pin;
    }

    /// <summary>Forgets every pin of <paramref name="host"/>, which is what removing its source asks.</summary>
    public void Remove(string host)
    {
        lock (_gate)
        {
            _ = _pins.RemoveAll(pin => pin.Host == host.ToLowerInvariant());
        }
    }

    public string Save() => JsonSerializer.Serialize(All().ToList(), NetworkJsonContext.Default.ListCertificatePin);

    public static PinBook Restore(string? text)
    {
        var book = new PinBook();
        if (string.IsNullOrWhiteSpace(text))
        {
            return book;
        }

        try
        {
            foreach (var pin in JsonSerializer.Deserialize(text, NetworkJsonContext.Default.ListCertificatePin) ?? [])
            {
                _ = book.Add(pin.Host, pin.Fingerprint);
            }
        }
        catch (JsonException)
        {
            // A damaged file is an empty book: the reader sees the fingerprint again and pins it again.
        }

        return book;
    }
}

/// <summary>
/// What the core said when a certificate is not trusted: the host, and the fingerprint the reader may
/// pin after seeing it. The core words it in the message of an <see cref="StoryArcStatus.Unauthorized"/>
/// failure (storyarc-core <c>OpdsError::Untrusted</c>).
/// </summary>
public sealed record CertificateChallenge(string Host, string Fingerprint)
{
    private const string Marker = " presented a certificate this system does not trust; its fingerprint is ";

    /// <summary>The challenge in <paramref name="message"/>, or <c>null</c> when it is a refused sign-in instead.</summary>
    public static CertificateChallenge? TryParse(string? message)
    {
        if (message is null)
        {
            return null;
        }

        var at = message.IndexOf(Marker, StringComparison.Ordinal);
        if (at <= 0)
        {
            return null;
        }

        var host = message[..at].Trim();
        var fingerprint = message[(at + Marker.Length)..].Trim();
        return host.Length == 0 || fingerprint.Length == 0 ? null : new CertificateChallenge(host, fingerprint);
    }
}

/// <summary>
/// The HTTP client every catalogue, Kavita server and download shares in the core (<c>storyarc_http_new</c>).
///
/// The seam's rule is one thread at a time per handle, and a download holds its handle for as long as it
/// runs, so the app makes one client for browsing and one per download instead of sharing one: a second
/// download or a catalogue page never waits behind the first. Each client starts from the same
/// <see cref="PinBook"/>, which is why the book lives in the app and not in the core.
/// </summary>
public sealed unsafe partial class CoreHttp : CoreHandle
{
    private CoreHttp()
    {
    }

    public static CoreHttp Create(CoreRuntime runtime, PinBook pins)
    {
        var pointer = runtime.Borrow(runtimePointer =>
        {
            void* opened = null;
            NativeCore.Check(NativeMethods.storyarc_http_new((void*)runtimePointer, &opened), "storyarc_http_new");
            return (nint)opened;
        });
        var http = new CoreHttp { Pins = pins };
        http.Adopt((void*)pointer);
        http.Retain(runtime);
        foreach (var pin in pins.All())
        {
            http.PinInCore(pin.Host, pin.Fingerprint);
        }

        return http;
    }

    /// <summary>The book this client was made from and adds to.</summary>
    public PinBook Pins { get; private init; } = new();

    /// <summary>
    /// Accepts the certificate with <paramref name="fingerprint"/> for <paramref name="host"/>, after the reader saw
    /// it. The pin also goes to the <see cref="Pins"/> book so the next client starts with it.
    /// </summary>
    public void Pin(string host, string fingerprint)
    {
        var pin = Pins.Add(host, fingerprint);
        PinInCore(pin.Host, pin.Fingerprint);
    }

    private void PinInCore(string host, string fingerprint)
    {
        var hostBytes = NativeCore.Utf8(host);
        var printBytes = NativeCore.Utf8(fingerprint);
        _ = Use(pointer =>
        {
            fixed (byte* hostData = hostBytes)
            fixed (byte* printData = printBytes)
            {
                NativeCore.Check(
                    NativeMethods.storyarc_http_pin((void*)pointer, hostData, (nuint)hostBytes.Length, printData, (nuint)printBytes.Length),
                    "storyarc_http_pin");
            }

            return true;
        });
    }

    protected override bool ReleaseHandle()
    {
        NativeMethods.storyarc_http_free((void*)handle);
        ReleaseOwner();
        return true;
    }
}

[JsonSourceGenerationOptions(PropertyNamingPolicy = JsonKnownNamingPolicy.CamelCase)]
[JsonSerializable(typeof(List<CertificatePin>))]
[JsonSerializable(typeof(OpdsPage))]
[JsonSerializable(typeof(KavitaLibrary[]))]
[JsonSerializable(typeof(KavitaSeries[]))]
[JsonSerializable(typeof(KavitaVolume[]))]
[JsonSerializable(typeof(KavitaChapter))]
[JsonSerializable(typeof(SmbIdentity))]
[JsonSerializable(typeof(SmbEntry[]))]
internal sealed partial class NetworkJsonContext : JsonSerializerContext;

internal static class JsonText
{
    /// <summary>A JSON object from the pairs given, a <c>null</c> value written as JSON null, which the core reads as absent.</summary>
    public static string Object(params (string Name, JsonNode? Value)[] fields)
    {
        var node = new JsonObject();
        foreach (var (name, value) in fields)
        {
            node[name] = value;
        }

        return node.ToJsonString();
    }
}
