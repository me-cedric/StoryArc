namespace StoryArc.Interop.Shell;

/// <summary>
/// Which commands something in the app answers today. A command the table lists but nothing
/// answers yet shows disabled in the menu, never enabled and silent (desktop-experience, "A
/// command that does not apply"). Each later task adds its ids here when it wires the handler.
/// </summary>
public static class CommandRouting
{
    private static readonly HashSet<string> Everywhere = new(StringComparer.Ordinal) { "closeWindow", "quit", "settings" };

    private static readonly HashSet<string> ReaderOnly = new(StringComparer.Ordinal) { "fullScreen" };

    public static bool IsHandled(string commandId, WindowKind window) =>
        Everywhere.Contains(commandId) || (window == WindowKind.Reader && ReaderOnly.Contains(commandId));
}
