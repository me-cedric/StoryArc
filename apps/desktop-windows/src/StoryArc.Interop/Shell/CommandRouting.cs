namespace StoryArc.Interop.Shell;

/// <summary>
/// Which commands something in the app answers today. A command the table lists but nothing
/// answers yet shows disabled in the menu, never enabled and silent (desktop-experience, "A
/// command that does not apply"). Each task adds its ids here when it wires the handler: task 2.38
/// the window commands, 2.40 the page commands, 2.42 opening a file, 2.43 the folder sources and
/// 2.47a to 2.47d the library's views and destinations.
/// </summary>
public static class CommandRouting
{
    private static readonly HashSet<string> Everywhere = new(StringComparer.Ordinal)
    {
        "closeWindow", "quit", "settings", "openFile", "addSource", "refreshSources",
    };

    private static readonly HashSet<string> LibraryOnly = new(StringComparer.Ordinal)
    {
        "find", "viewGrid", "viewList", "goHome", "goLibrary", "goDownloads", "continueReading", "showDetails",
    };

    private static readonly HashSet<string> ReaderOnly = new(StringComparer.Ordinal)
    {
        "fullScreen", "nextPage", "previousPage", "firstPage", "lastPage", "singlePage", "twoPages", "zoomIn", "zoomOut", "fitPage",
        "showContents",
    };

    public static bool IsHandled(string commandId, WindowKind window) =>
        Everywhere.Contains(commandId)
        || (window == WindowKind.Library && LibraryOnly.Contains(commandId))
        || (window == WindowKind.Reader && ReaderOnly.Contains(commandId));
}
