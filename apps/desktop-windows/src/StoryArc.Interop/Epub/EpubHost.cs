using System.Globalization;
using System.Text;

namespace StoryArc.Interop.Epub;

/// <summary>
/// What a request in the web view is for, the way WebView2's <c>CoreWebView2WebResourceContext</c>
/// names it, kept platform-free so the host rules test on any OS.
/// </summary>
public enum EpubRequestContext
{
    /// <summary>A top-level navigation.</summary>
    Document,

    /// <summary>A frame's document.</summary>
    Frame,
    Image,
    Stylesheet,
    Script,
    Font,
    Media,
    Fetch,
    XmlHttpRequest,

    /// <summary>A beacon or a ping.</summary>
    Ping,

    /// <summary>A WebSocket handshake. WebView2 may not raise <c>WebResourceRequested</c> for it; the policy carries that case.</summary>
    WebSocket,
    Other,
}

/// <summary>What the host answers a request with: a status, its reason, the body and the header block WebView2 takes.</summary>
public sealed record EpubResponse(int Status, string Reason, string MediaType, ReadOnlyMemory<byte> Body, IReadOnlyList<KeyValuePair<string, string>> Headers)
{
    /// <summary>The raw header block <c>CoreWebView2Environment.CreateWebResourceResponse</c> takes, one header a line.</summary>
    public string HeaderBlock => string.Join("\n", Headers.Select(header => header.Key + ": " + header.Value));

    public string? Header(string name) =>
        Headers.FirstOrDefault(header => string.Equals(header.Key, name, StringComparison.OrdinalIgnoreCase)).Value;

    public bool IsDenied => Status == 403;
}

/// <summary>
/// The WebView2 host of the EPUB renderer, as pure rules (desktop-clients task 4.16; design.md
/// Decision 6; ADR-0015). One publication is one origin on the app's own scheme,
/// <c>storyarc-epub://&lt;id&gt;/</c>, registered on a custom environment, and every request the web
/// view makes comes here: the reader page, the pinned bundle, the core's manifest and positions,
/// and the container's resources by path, each answered with the Content-Security-Policy. Anything
/// off that origin is refused with 403 and a navigation to it is cancelled, so the eight egress
/// vectors of ADR-0015 arrive nowhere. The window applies these rules to <c>WebResourceRequested</c>,
/// <c>NavigationStarting</c> and <c>FrameNavigationStarting</c>.
/// </summary>
public sealed class EpubHost
{
    /// <summary>The scheme, registered through <c>CoreWebView2CustomSchemeRegistration</c> with an authority and treated as secure.</summary>
    public const string Scheme = "storyarc-epub";

    public const string ReaderPagePath = "/index.html";
    public const string ReaderScriptPath = "/reader.js";
    public const string BundlePath = "/storyarc-epub.js";
    public const string ManifestPath = "/manifest.json";
    public const string PositionsPath = "/positions.json";

    /// <summary>
    /// The policy on every response. <c>'self'</c> is the publication's own origin on the app's scheme,
    /// which cannot name a network host, so the fetch directives (connect, img, font, media, frame)
    /// deny every way out while the renderer still fetches chapters from the manifest's origin and
    /// loads them as <c>blob:</c> frames. Scripts and styles inline are allowed because the toolkit
    /// and a publication's own markup use them, and neither directive governs egress.
    /// </summary>
    public const string ContentSecurityPolicy =
        "default-src 'none'; script-src 'self' blob: 'unsafe-inline'; style-src 'self' blob: 'unsafe-inline'; " +
        "img-src 'self' blob: data:; font-src 'self' blob: data:; media-src 'self' blob:; connect-src 'self'; " +
        "frame-src 'self' blob:; child-src 'self' blob:; worker-src 'self' blob:; " +
        "object-src 'none'; base-uri 'none'; form-action 'none'; frame-ancestors 'none'";

    private readonly string _publicationId;
    private readonly Func<string> _manifest;
    private readonly Func<string> _positions;
    private readonly Func<string, EpubResource?> _resource;
    private readonly Func<byte[]> _bundle;

    /// <param name="publicationId">The origin's host: letters, digits and dashes only, lower case.</param>
    /// <param name="manifest">The core's manifest JSON, built with <see cref="SelfUrl"/> as its self link.</param>
    /// <param name="positions">The core's positions JSON.</param>
    /// <param name="resource">The container's resource at a path, or <c>null</c>.</param>
    /// <param name="bundle">The pinned <c>storyarc-epub.js</c>.</param>
    public EpubHost(string publicationId, Func<string> manifest, Func<string> positions, Func<string, EpubResource?> resource, Func<byte[]> bundle)
    {
        if (publicationId.Length == 0 || !publicationId.All(c => char.IsAsciiLetterLower(c) || char.IsAsciiDigit(c) || c == '-'))
        {
            throw new ArgumentException("A publication id is lower-case letters, digits and dashes.", nameof(publicationId));
        }

        _publicationId = publicationId;
        _manifest = manifest;
        _positions = positions;
        _resource = resource;
        _bundle = bundle;
    }

    /// <summary>An origin host for a publication path: a digest of it, so the id names no file and is the same across launches.</summary>
    public static string IdFor(string publicationPath) =>
        Convert.ToHexStringLower(System.Security.Cryptography.SHA256.HashData(Encoding.UTF8.GetBytes(publicationPath)))[..32];

    public EpubHost(string publicationId, EpubPublication epub, Func<byte[]> bundle)
        : this(publicationId, epub.ManifestJson, epub.PositionsJson, epub.Resource, bundle)
    {
    }

    /// <summary>The publication's origin, with its trailing slash.</summary>
    public string Origin => Scheme + "://" + _publicationId + "/";

    /// <summary>The address the reader page loads at.</summary>
    public string ReaderPageUrl => Origin + ReaderPagePath[1..];

    /// <summary>The manifest's own address: pass it to <see cref="EpubPublication.Open"/> as the self URL.</summary>
    public string SelfUrl => Origin + ManifestPath[1..];

    /// <summary>Whether <paramref name="uri"/> is on this publication's origin.</summary>
    public bool IsOwn(Uri uri) =>
        string.Equals(uri.Scheme, Scheme, StringComparison.OrdinalIgnoreCase) &&
        string.Equals(uri.Host, _publicationId, StringComparison.OrdinalIgnoreCase);

    /// <summary>
    /// The navigation filter. A top-level navigation is allowed only within this origin; a frame may
    /// also load the <c>blob:</c> documents the toolkit builds and the empty page. Everything else,
    /// http and https first, is cancelled: a chapter link out of the publication reaches the host as
    /// a <c>link</c> message instead.
    /// </summary>
    public bool AllowsNavigation(string url, bool isFrame)
    {
        if (!Uri.TryCreate(url, UriKind.Absolute, out var uri))
        {
            return false;
        }

        if (IsOwn(uri))
        {
            return true;
        }

        if (!isFrame)
        {
            return false;
        }

        return uri.Scheme == "about" ? uri.OriginalString is "about:blank" or "about:srcdoc"
            : uri.Scheme == "blob" && uri.OriginalString.StartsWith("blob:" + Origin, StringComparison.OrdinalIgnoreCase);
    }

    /// <summary>
    /// Whether the web view asks the host about this URL at all: WebView2 raises <c>WebResourceRequested</c>
    /// for network schemes and registered custom schemes, not for <c>blob:</c>, <c>data:</c> or <c>about:</c>.
    /// </summary>
    public static bool IsIntercepted(Uri uri) =>
        uri.Scheme is "http" or "https" or "ws" or "wss" or Scheme;

    /// <summary>
    /// The answer to one <c>WebResourceRequested</c> (the filter is <c>*</c> over every context). A
    /// request off this origin is 403 with no body; on it, the path decides. <paramref name="rangeHeader"/>
    /// is the request's <c>Range</c>, honoured with 206 and <c>Content-Range</c> the way an HTTP server
    /// would, which a media element inside a publication needs.
    /// </summary>
    public EpubResponse Answer(string url, EpubRequestContext context, string? rangeHeader = null)
    {
        if (!Uri.TryCreate(url, UriKind.Absolute, out var uri) || !IsOwn(uri))
        {
            return Deny();
        }

        var path = Uri.UnescapeDataString(uri.AbsolutePath);
        switch (path)
        {
            case "/":
            case ReaderPagePath:
                return Whole(200, "OK", "text/html; charset=utf-8", Encoding.UTF8.GetBytes(ReaderPage), rangeHeader);
            case ReaderScriptPath:
                return Whole(200, "OK", "text/javascript; charset=utf-8", Encoding.UTF8.GetBytes(ReaderScript), rangeHeader);
            case BundlePath:
                return Whole(200, "OK", "text/javascript; charset=utf-8", _bundle(), rangeHeader);
            case ManifestPath:
                return Whole(200, "OK", "application/webpub+json; charset=utf-8", Encoding.UTF8.GetBytes(_manifest()), rangeHeader);
            case PositionsPath:
                return Whole(200, "OK", "application/json; charset=utf-8", Encoding.UTF8.GetBytes(_positions()), rangeHeader);
        }

        var href = path.TrimStart('/');
        if (href.Length == 0 || href.Split('/').Contains(".."))
        {
            return NotFound();
        }

        var resource = _resource(href);
        return resource is null ? NotFound() : Whole(200, "OK", resource.MediaType, resource.Bytes, rangeHeader);
    }

    /// <summary>The path the container's resource <paramref name="href"/> is served at, absolute on this origin.</summary>
    public string UrlFor(string href) => Origin + string.Join('/', href.Split('/').Select(Uri.EscapeDataString));

    private static EpubResponse Deny() => new(403, "Forbidden", "text/plain", ReadOnlyMemory<byte>.Empty, Secured("text/plain", 0));

    private static EpubResponse NotFound() => new(404, "Not Found", "text/plain", ReadOnlyMemory<byte>.Empty, Secured("text/plain", 0));

    private static EpubResponse Whole(int status, string reason, string mediaType, byte[] body, string? rangeHeader)
    {
        if (rangeHeader is not null && TryParseRange(rangeHeader, body.Length, out var start, out var end))
        {
            var slice = new ReadOnlyMemory<byte>(body, start, end - start + 1);
            var headers = Secured(mediaType, slice.Length);
            headers.Add(new("Accept-Ranges", "bytes"));
            headers.Add(new("Content-Range", string.Create(CultureInfo.InvariantCulture, $"bytes {start}-{end}/{body.Length}")));
            return new EpubResponse(206, "Partial Content", mediaType, slice, headers);
        }

        if (rangeHeader is not null && rangeHeader.StartsWith("bytes=", StringComparison.OrdinalIgnoreCase))
        {
            var headers = Secured("text/plain", 0);
            headers.Add(new("Content-Range", string.Create(CultureInfo.InvariantCulture, $"bytes */{body.Length}")));
            return new EpubResponse(416, "Range Not Satisfiable", "text/plain", ReadOnlyMemory<byte>.Empty, headers);
        }

        var whole = Secured(mediaType, body.Length);
        whole.Add(new("Accept-Ranges", "bytes"));
        return new EpubResponse(status, reason, mediaType, body, whole);
    }

    /// <summary>The headers every response carries: the type, the length, the policy, and no caching across sessions.</summary>
    private static List<KeyValuePair<string, string>> Secured(string mediaType, int length) =>
    [
        new("Content-Type", mediaType),
        new("Content-Length", length.ToString(CultureInfo.InvariantCulture)),
        new("Content-Security-Policy", ContentSecurityPolicy),
        new("Cache-Control", "no-store"),
        new("X-Content-Type-Options", "nosniff"),
    ];

    /// <summary>One <c>bytes=start-end</c> range (also <c>start-</c> and <c>-suffix</c>); the first range when several are asked.</summary>
    internal static bool TryParseRange(string header, int length, out int start, out int end)
    {
        start = 0;
        end = -1;
        if (!header.StartsWith("bytes=", StringComparison.OrdinalIgnoreCase) || length == 0)
        {
            return false;
        }

        var first = header[6..].Split(',')[0].Trim();
        var dash = first.IndexOf('-', StringComparison.Ordinal);
        if (dash < 0)
        {
            return false;
        }

        var left = first[..dash].Trim();
        var right = first[(dash + 1)..].Trim();
        if (left.Length == 0)
        {
            if (!int.TryParse(right, NumberStyles.None, CultureInfo.InvariantCulture, out var suffix) || suffix == 0)
            {
                return false;
            }

            start = Math.Max(0, length - suffix);
            end = length - 1;
            return true;
        }

        if (!int.TryParse(left, NumberStyles.None, CultureInfo.InvariantCulture, out start) || start >= length)
        {
            return false;
        }

        if (right.Length == 0)
        {
            end = length - 1;
            return true;
        }

        if (!int.TryParse(right, NumberStyles.None, CultureInfo.InvariantCulture, out end) || end < start)
        {
            return false;
        }

        end = Math.Min(end, length - 1);
        return true;
    }

    /// <summary>The reader page: one sized container, the bundle, and the page's own script. No inline script, so <c>script-src</c> needs none.</summary>
    internal const string ReaderPage =
        "<!doctype html>\n<html lang=\"en\"><head><meta charset=\"utf-8\">" +
        "<meta name=\"viewport\" content=\"width=device-width, initial-scale=1\">" +
        "<title>StoryArc</title>" +
        "<style>html,body{margin:0;height:100%;overflow:hidden;background:transparent}#reader{position:absolute;inset:0}</style>" +
        "</head><body><div id=\"reader\"></div>" +
        "<script src=\"/storyarc-epub.js\"></script><script src=\"/reader.js\"></script></body></html>\n";

    /// <summary>
    /// The page's script: fetches the manifest and the positions from this origin, opens the renderer in the
    /// container, posts to the host through <c>chrome.webview</c> (the bundle's own door) and hands the host's
    /// messages to <c>receive</c>. The host's first message may arrive before <c>ready</c>; it is queued.
    /// </summary>
    internal const string ReaderScript =
        "(function(){'use strict';\n" +
        "var queue=[];var reader=null;\n" +
        "function receive(message){if(reader){reader.receive(message)}else{queue.push(message)}}\n" +
        "window.chrome.webview.addEventListener('message',function(event){receive(event.data)});\n" +
        "Promise.all([fetch('/manifest.json').then(function(r){return r.json()}),fetch('/positions.json').then(function(r){return r.json()})])\n" +
        ".then(function(parts){var locator=window.__storyarcLocator||null;\n" +
        "return StoryArcEpub.open({container:document.getElementById('reader'),manifest:parts[0],positions:parts[1],locator:locator})})\n" +
        ".then(function(opened){reader=opened;queue.forEach(function(m){reader.receive(m)});queue=[]})\n" +
        ".catch(function(error){window.chrome.webview.postMessage(JSON.stringify({type:'host-error',seq:0,message:String(error)}))});\n" +
        "})();\n";
}
