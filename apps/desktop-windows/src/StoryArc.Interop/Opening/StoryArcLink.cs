using StoryArc.Interop.Library;
using StoryArc.Interop.Sources;

namespace StoryArc.Interop.Opening;

/// <summary>What a <c>storyarc://</c> link turns into once it is held against the library.</summary>
public enum LinkOutcome
{
    /// <summary>The link names a publication the library holds: it opens in a reader window.</summary>
    OpenPublication,

    /// <summary>The link names a source the app holds: the library window shows the sources page.</summary>
    ShowSource,

    /// <summary>The link names a publication or a source the app does not hold: the app says so and changes nothing.</summary>
    NotFound,

    /// <summary>The link names nothing to open, or something else than a name: nothing runs and nothing changes.</summary>
    Refused,
}

/// <summary>The decision for one link. <paramref name="Id"/> is the record's or source's id when something opens; <paramref name="Name"/> is what the link asked for.</summary>
public sealed record LinkAction(LinkOutcome Outcome, string? Id = null, string? Name = null);

/// <summary>
/// The app's own address scheme (desktop-clients task 5.8; desktop-experience "Opening a link or a
/// command"). Two forms open something: <c>storyarc://publication/&lt;title or id&gt;</c> and
/// <c>storyarc://source/&lt;name or id&gt;</c>, the name percent-encoded. Anything else, an unknown
/// kind, a path of several parts, no name, is refused whole. A query or a fragment after a name is
/// ignored: the link is a name to open and never a command, so nothing here reads a setting, runs
/// a program or writes data. Pure: the host passes the library's records and sources.
/// </summary>
public static class StoryArcLink
{
    public const string Scheme = "storyarc";

    /// <summary>Whether a command-line argument or a launch string is a link rather than a path.</summary>
    public static bool IsLink(string? argument) =>
        argument is not null && argument.StartsWith(Scheme + ":", StringComparison.OrdinalIgnoreCase);

    public static LinkAction Resolve(string link, IEnumerable<LibraryRecord> records, IEnumerable<FolderSource> sources)
    {
        var refused = new LinkAction(LinkOutcome.Refused);
        if (!Uri.TryCreate(link, UriKind.Absolute, out var uri)
            || !string.Equals(uri.Scheme, Scheme, StringComparison.OrdinalIgnoreCase))
        {
            return refused;
        }

        var segments = uri.AbsolutePath.Split('/', StringSplitOptions.RemoveEmptyEntries);
        if (segments.Length != 1)
        {
            return refused;
        }

        var name = Uri.UnescapeDataString(segments[0]).Trim();
        if (name.Length == 0)
        {
            return refused;
        }

        switch (uri.Host)
        {
            case "publication":
                var record = records.FirstOrDefault(item => Is(name, item.Id, item.Title));
                return record is null
                    ? new LinkAction(LinkOutcome.NotFound, Name: name)
                    : new LinkAction(LinkOutcome.OpenPublication, record.Id, name);
            case "source":
                var source = sources.FirstOrDefault(item => Is(name, item.Id, item.Name));
                return source is null
                    ? new LinkAction(LinkOutcome.NotFound, Name: name)
                    : new LinkAction(LinkOutcome.ShowSource, source.Id, name);
            default:
                return refused;
        }
    }

    private static bool Is(string wanted, string id, string title) =>
        string.Equals(wanted, id, StringComparison.OrdinalIgnoreCase)
        || string.Equals(wanted, title, StringComparison.OrdinalIgnoreCase);
}
