using StoryArc.Interop.Epub;

namespace StoryArc.Interop.Tests.Support;

/// <summary>The eight ways out of a publication, in the order of ADR-0015 and the egress page.</summary>
public enum EgressVector
{
    Image,
    ScriptedImage,
    Fetch,
    Request,
    Beacon,
    Socket,
    Frame,
    Navigation,
}

/// <summary>The three locks a request passes through, so a run says which one stopped a vector.</summary>
[Flags]
public enum EgressLock
{
    None = 0,

    /// <summary>The Content-Security-Policy of the reader page, applied by the engine before any request is made.</summary>
    Policy = 1,

    /// <summary>The <c>NavigationStarting</c> and <c>FrameNavigationStarting</c> handlers.</summary>
    Navigation = 2,

    /// <summary>The <c>WebResourceRequested</c> handler behind a <c>*</c> filter.</summary>
    Filter = 4,

    All = Policy | Navigation | Filter,
}

/// <summary>
/// A stand-in for WebView2's request pipeline, as its documentation describes it: the engine applies
/// the page's Content-Security-Policy, raises <c>NavigationStarting</c> for a navigation and
/// <c>FrameNavigationStarting</c> for a frame, raises <c>WebResourceRequested</c> for every request on a
/// network or registered scheme that matches the filter (a WebSocket handshake may not raise it, so it
/// is not raised here), and sends the request when every lock let it through. A request that is sent
/// to the collector is an arrival. Which locks are on is a parameter, so a test can show each lock
/// stopping what it governs on its own.
/// </summary>
public sealed class FakeWebView2
{
    private readonly EpubHost _host;
    private readonly EgressLock _locks;

    public FakeWebView2(EpubHost host, EgressLock locks = EgressLock.All)
    {
        _host = host;
        _locks = locks;
    }

    public List<string> Arrivals { get; } = [];

    public Dictionary<EgressVector, EgressLock> StoppedBy { get; } = [];

    /// <summary>Fires every vector at <paramref name="collector"/> from the reader page, the way the egress page does.</summary>
    public void FireAll(string collector)
    {
        foreach (var vector in Enum.GetValues<EgressVector>())
        {
            Fire(vector, collector);
        }
    }

    public void Fire(EgressVector vector, string collector)
    {
        var (url, context) = vector switch
        {
            EgressVector.Image => (collector + "/hit/image", EpubRequestContext.Image),
            EgressVector.ScriptedImage => (collector + "/hit/scriptedImage", EpubRequestContext.Image),
            EgressVector.Fetch => (collector + "/hit/fetch", EpubRequestContext.Fetch),
            EgressVector.Request => (collector + "/hit/request", EpubRequestContext.XmlHttpRequest),
            EgressVector.Beacon => (collector + "/hit/beacon", EpubRequestContext.Ping),
            EgressVector.Socket => (collector.Replace("http", "ws", StringComparison.Ordinal) + "/hit/socket", EpubRequestContext.WebSocket),
            EgressVector.Frame => (collector + "/hit/frame", EpubRequestContext.Frame),
            EgressVector.Navigation => (collector + "/hit/navigation", EpubRequestContext.Document),
            _ => throw new ArgumentOutOfRangeException(nameof(vector)),
        };

        var stopped = Request(url, context);
        StoppedBy[vector] = stopped;
        if (stopped == EgressLock.None)
        {
            Arrivals.Add(vector + " -> " + url);
        }
    }

    /// <summary>One request through the pipeline: the first lock that stops it, or <see cref="EgressLock.None"/> when it was sent.</summary>
    public EgressLock Request(string url, EpubRequestContext context)
    {
        var uri = new Uri(url);
        if (_locks.HasFlag(EgressLock.Policy) && !ContentSecurityPolicy.Allows(EpubHost.ContentSecurityPolicy, _host.Origin, uri, context))
        {
            return EgressLock.Policy;
        }

        if (_locks.HasFlag(EgressLock.Navigation) && (context is EpubRequestContext.Document or EpubRequestContext.Frame)
            && !_host.AllowsNavigation(url, isFrame: context == EpubRequestContext.Frame))
        {
            return EgressLock.Navigation;
        }

        if (_locks.HasFlag(EgressLock.Filter) && context != EpubRequestContext.WebSocket && EpubHost.IsIntercepted(uri)
            && _host.Answer(url, context).IsDenied)
        {
            return EgressLock.Filter;
        }

        return EgressLock.None;
    }
}

/// <summary>
/// Enough of Content-Security-Policy Level 3 to evaluate the host's policy: the fetch directive of a
/// request type, its fallback to <c>child-src</c> then <c>default-src</c>, and the sources <c>'self'</c>,
/// <c>'none'</c>, a scheme (<c>blob:</c>, <c>data:</c>) and <c>*</c>. A directive the policy lacks and
/// no fallback covers allows the request, as a browser would.
/// </summary>
public static class ContentSecurityPolicy
{
    public static bool Allows(string policy, string selfOrigin, Uri request, EpubRequestContext context)
    {
        var directives = policy.Split(';', StringSplitOptions.RemoveEmptyEntries | StringSplitOptions.TrimEntries)
            .Select(part => part.Split(' ', StringSplitOptions.RemoveEmptyEntries))
            .ToDictionary(words => words[0], words => words.Skip(1).ToArray(), StringComparer.OrdinalIgnoreCase);

        foreach (var name in DirectivesFor(context))
        {
            if (directives.TryGetValue(name, out var sources))
            {
                return sources.Any(source => Matches(source, selfOrigin, request));
            }
        }

        return true;
    }

    private static IEnumerable<string> DirectivesFor(EpubRequestContext context) => context switch
    {
        EpubRequestContext.Image => ["img-src", "default-src"],
        EpubRequestContext.Stylesheet => ["style-src", "default-src"],
        EpubRequestContext.Script => ["script-src", "default-src"],
        EpubRequestContext.Font => ["font-src", "default-src"],
        EpubRequestContext.Media => ["media-src", "default-src"],
        EpubRequestContext.Fetch or EpubRequestContext.XmlHttpRequest or EpubRequestContext.Ping or EpubRequestContext.WebSocket
            => ["connect-src", "default-src"],
        EpubRequestContext.Frame => ["frame-src", "child-src", "default-src"],
        // A top-level navigation is not governed by a fetch directive; the navigation lock holds it.
        EpubRequestContext.Document => [],
        _ => ["default-src"],
    };

    private static bool Matches(string source, string selfOrigin, Uri request)
    {
        if (source == "'none'")
        {
            return false;
        }

        if (source == "*")
        {
            return request.Scheme is not ("blob" or "data" or "filesystem");
        }

        if (source == "'self'")
        {
            var self = new Uri(selfOrigin);
            return request.Scheme == self.Scheme && string.Equals(request.Host, self.Host, StringComparison.OrdinalIgnoreCase);
        }

        if (source.EndsWith(':', StringComparison.Ordinal))
        {
            return string.Equals(request.Scheme, source[..^1], StringComparison.OrdinalIgnoreCase);
        }

        // A quoted keyword ('unsafe-inline', a nonce) governs inline code, not a request.
        return false;
    }
}
