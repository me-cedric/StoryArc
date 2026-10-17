namespace StoryArc.Interop.Shell;

/// <summary>The menus of the menu bar, in their order (docs/designs/desktop/windows.md, section 6).</summary>
public enum MenuName
{
    File,
    Edit,
    View,
    Go,
    Reader,
    Help,
}

/// <summary>The kind of window a command is asked from.</summary>
public enum WindowKind
{
    Library,
    Reader,

    /// <summary>The audiobook player window of wave 4. Its commands are in the table so the menu has its shape now.</summary>
    Player,
}

/// <summary>
/// A key of a shortcut, platform-free so the table tests on any host. The app maps each to a
/// <c>Windows.System.VirtualKey</c>; the OEM keys (plus, minus, comma, slash) map to the virtual-key
/// codes the enum does not name.
/// </summary>
public enum ShortcutKey
{
    None,
    A,
    B,
    C,
    D,
    F,
    G,
    H,
    I,
    L,
    O,
    Q,
    R,
    T,
    W,
    Comma,
    Plus,
    Minus,
    Zero,
    One,
    Two,
    Three,
    Nine,
    Slash,
    F3,
    F5,
    F11,
    Left,
    Right,
    Home,
    End,
    Space,
}

[Flags]
public enum ShortcutModifiers
{
    None = 0,
    Control = 1,
    Shift = 2,
    Alt = 4,
}

/// <summary>One key combination. <see cref="Display"/> is the text the menu shows beside the command.</summary>
public sealed record Shortcut(ShortcutKey Key, ShortcutModifiers Modifiers)
{
    public static Shortcut Control(ShortcutKey key) => new(key, ShortcutModifiers.Control);

    public static Shortcut ControlShift(ShortcutKey key) => new(key, ShortcutModifiers.Control | ShortcutModifiers.Shift);

    public static Shortcut Alt(ShortcutKey key) => new(key, ShortcutModifiers.Alt);

    public static Shortcut Plain(ShortcutKey key) => new(key, ShortcutModifiers.None);

    public string Display
    {
        get
        {
            var parts = new List<string>(4);
            if (Modifiers.HasFlag(ShortcutModifiers.Control))
            {
                parts.Add("Ctrl");
            }

            // "?" is already the shifted slash, so Ctrl+Shift+/ reads Ctrl+? as the design writes it.
            if (Modifiers.HasFlag(ShortcutModifiers.Shift) && Key != ShortcutKey.Slash)
            {
                parts.Add("Shift");
            }

            if (Modifiers.HasFlag(ShortcutModifiers.Alt))
            {
                parts.Add("Alt");
            }

            parts.Add(KeyLabel(Key));
            return string.Join("+", parts);
        }
    }

    private static string KeyLabel(ShortcutKey key) => key switch
    {
        ShortcutKey.Comma => ",",
        ShortcutKey.Plus => "+",
        ShortcutKey.Minus => "−",
        ShortcutKey.Zero => "0",
        ShortcutKey.One => "1",
        ShortcutKey.Two => "2",
        ShortcutKey.Three => "3",
        ShortcutKey.Nine => "9",
        ShortcutKey.Slash => "?",
        ShortcutKey.Left => "←",
        ShortcutKey.Right => "→",
        _ => key.ToString(),
    };
}

/// <summary>
/// One command of the menu bar. <see cref="Label"/> is the English text; <see cref="LabelKey"/>
/// is the resource name the generated string catalogue may carry for it, read first and falling
/// back to the label. <see cref="Windows"/> says in which windows the command applies: elsewhere
/// its entry is shown disabled and not removed, so the menu has the same shape in every window
/// (desktop-experience, "A command that does not apply").
/// </summary>
public sealed record AppCommand(
    string Id,
    MenuName Menu,
    string Label,
    Shortcut? Shortcut,
    Shortcut? AlternateShortcut,
    IReadOnlySet<WindowKind> Scope,
    bool SeparatorBefore = false)
{
    public string LabelKey => "menu_" + Id;

    public bool AppliesIn(WindowKind window) => Scope.Contains(window);
}

/// <summary>
/// The command list of task 2.10, as docs/designs/desktop/windows.md section 6 lays it out for
/// Windows. Shortcuts use Control. Windows has no Quit key of its own: Quit sits in the File menu
/// with no accelerator, Alt+F4 closes the window (the system's own key), and Control+W closes the
/// window (desktop-experience, "The standard shortcuts").
/// </summary>
public static class CommandTable
{
    private static readonly IReadOnlySet<WindowKind> Everywhere = new HashSet<WindowKind> { WindowKind.Library, WindowKind.Reader, WindowKind.Player };
    private static readonly IReadOnlySet<WindowKind> LibraryOnly = new HashSet<WindowKind> { WindowKind.Library };
    private static readonly IReadOnlySet<WindowKind> ReaderOnly = new HashSet<WindowKind> { WindowKind.Reader };
    private static readonly IReadOnlySet<WindowKind> PlayerOnly = new HashSet<WindowKind> { WindowKind.Player };
    private static readonly IReadOnlySet<WindowKind> ReaderAndPlayer = new HashSet<WindowKind> { WindowKind.Reader, WindowKind.Player };

    public static IReadOnlyList<AppCommand> All { get; } =
    [
        // File
        new("openFile", MenuName.File, "Open File…", Shortcut.Control(ShortcutKey.O), null, Everywhere),
        new("openRecent", MenuName.File, "Open Recent", null, null, Everywhere),
        new("addSource", MenuName.File, "Add Source…", Shortcut.ControlShift(ShortcutKey.A), null, Everywhere),
        new("refreshSources", MenuName.File, "Refresh Sources", Shortcut.Control(ShortcutKey.R), Shortcut.Plain(ShortcutKey.F5), Everywhere),
        new("closeWindow", MenuName.File, "Close Window", Shortcut.Control(ShortcutKey.W), null, Everywhere, SeparatorBefore: true),
        new("settings", MenuName.File, "Settings…", Shortcut.Control(ShortcutKey.Comma), null, Everywhere),
        new("quit", MenuName.File, "Quit StoryArc", null, null, Everywhere, SeparatorBefore: true),

        // Edit
        new("copy", MenuName.Edit, "Copy", Shortcut.Control(ShortcutKey.C), null, Everywhere),
        new("selectAll", MenuName.Edit, "Select All", Shortcut.Control(ShortcutKey.A), null, Everywhere),
        new("find", MenuName.Edit, "Find", Shortcut.Control(ShortcutKey.F), null, Everywhere, SeparatorBefore: true),
        new("findNext", MenuName.Edit, "Find Next", Shortcut.Control(ShortcutKey.G), Shortcut.Plain(ShortcutKey.F3), Everywhere),
        new("findPrevious", MenuName.Edit, "Find Previous", Shortcut.ControlShift(ShortcutKey.G), null, Everywhere),

        // View
        new("viewGrid", MenuName.View, "View as Grid", Shortcut.ControlShift(ShortcutKey.One), null, LibraryOnly),
        new("viewList", MenuName.View, "View as List", Shortcut.ControlShift(ShortcutKey.Two), null, LibraryOnly),
        new("largerCovers", MenuName.View, "Larger Covers", Shortcut.Control(ShortcutKey.Plus), null, LibraryOnly, SeparatorBefore: true),
        new("smallerCovers", MenuName.View, "Smaller Covers", Shortcut.Control(ShortcutKey.Minus), null, LibraryOnly),
        new("automaticCoverSize", MenuName.View, "Automatic Cover Size", Shortcut.Control(ShortcutKey.Zero), null, LibraryOnly),
        new("toggleSidebar", MenuName.View, "Show or Hide Sidebar", Shortcut.Control(ShortcutKey.B), null, LibraryOnly, SeparatorBefore: true),
        new("fullScreen", MenuName.View, "Enter or Exit Full Screen", Shortcut.Plain(ShortcutKey.F11), null, Everywhere),

        // Go
        new("back", MenuName.Go, "Back", Shortcut.Alt(ShortcutKey.Left), null, LibraryOnly),
        new("forward", MenuName.Go, "Forward", Shortcut.Alt(ShortcutKey.Right), null, LibraryOnly),
        new("goHome", MenuName.Go, "Home", Shortcut.Control(ShortcutKey.One), null, LibraryOnly, SeparatorBefore: true),
        new("goLibrary", MenuName.Go, "Library", Shortcut.Control(ShortcutKey.Two), null, LibraryOnly),
        new("goDownloads", MenuName.Go, "Downloads", Shortcut.Control(ShortcutKey.Three), null, LibraryOnly),
        new("continueReading", MenuName.Go, "Continue Reading", Shortcut.ControlShift(ShortcutKey.C), null, LibraryOnly, SeparatorBefore: true),
        new("showDetails", MenuName.Go, "Show Details", Shortcut.Control(ShortcutKey.I), null, LibraryOnly),

        // Reader
        new("nextPage", MenuName.Reader, "Next Page", Shortcut.Plain(ShortcutKey.Right), null, ReaderOnly),
        new("previousPage", MenuName.Reader, "Previous Page", Shortcut.Plain(ShortcutKey.Left), null, ReaderOnly),
        new("firstPage", MenuName.Reader, "First Page", Shortcut.Plain(ShortcutKey.Home), null, ReaderOnly),
        new("lastPage", MenuName.Reader, "Last Page", Shortcut.Plain(ShortcutKey.End), null, ReaderOnly),
        new("goToPage", MenuName.Reader, "Go to Page…", Shortcut.Control(ShortcutKey.L), null, ReaderOnly),
        new("nextChapter", MenuName.Reader, "Next Chapter or Issue", Shortcut.Control(ShortcutKey.Right), null, ReaderAndPlayer, SeparatorBefore: true),
        new("previousChapter", MenuName.Reader, "Previous Chapter or Issue", Shortcut.Control(ShortcutKey.Left), null, ReaderAndPlayer),
        new("singlePage", MenuName.Reader, "Single Page", Shortcut.ControlShift(ShortcutKey.One), null, ReaderOnly, SeparatorBefore: true),
        new("twoPages", MenuName.Reader, "Two Pages", Shortcut.ControlShift(ShortcutKey.Two), null, ReaderOnly),
        new("scroll", MenuName.Reader, "Scroll", Shortcut.ControlShift(ShortcutKey.Three), null, ReaderOnly),
        new("zoomIn", MenuName.Reader, "Zoom In or Larger Text", Shortcut.Control(ShortcutKey.Plus), null, ReaderOnly, SeparatorBefore: true),
        new("zoomOut", MenuName.Reader, "Zoom Out or Smaller Text", Shortcut.Control(ShortcutKey.Minus), null, ReaderOnly),
        new("fitPage", MenuName.Reader, "Fit Page", Shortcut.Control(ShortcutKey.Zero), null, ReaderOnly),
        new("fitWidth", MenuName.Reader, "Fit Width", Shortcut.Control(ShortcutKey.Nine), null, ReaderOnly),
        new("originalSize", MenuName.Reader, "Original Size", Shortcut.ControlShift(ShortcutKey.Zero), null, ReaderOnly),
        new("showContents", MenuName.Reader, "Show Contents", Shortcut.Control(ShortcutKey.T), null, ReaderOnly, SeparatorBefore: true),
        new("appearance", MenuName.Reader, "Appearance", Shortcut.ControlShift(ShortcutKey.T), null, ReaderOnly),
        new("bookmarkPage", MenuName.Reader, "Bookmark This Page", Shortcut.Control(ShortcutKey.D), null, ReaderOnly),
        new("toggleControls", MenuName.Reader, "Show or Hide Controls", Shortcut.ControlShift(ShortcutKey.H), null, ReaderOnly),
        new("readAloud", MenuName.Reader, "Read Aloud", Shortcut.ControlShift(ShortcutKey.L), null, ReaderOnly),
        new("playPause", MenuName.Reader, "Play or Pause", Shortcut.Plain(ShortcutKey.Space), null, PlayerOnly, SeparatorBefore: true),
        new("skipBack", MenuName.Reader, "Skip Back 15 s", Shortcut.Plain(ShortcutKey.Left), null, PlayerOnly),
        new("skipForward", MenuName.Reader, "Skip Forward 30 s", Shortcut.Plain(ShortcutKey.Right), null, PlayerOnly),

        // Help
        new("keyboardShortcuts", MenuName.Help, "Keyboard Shortcuts", Shortcut.ControlShift(ShortcutKey.Slash), null, Everywhere),
        new("whatsNew", MenuName.Help, "What's New…", null, null, Everywhere),
        new("acknowledgements", MenuName.Help, "Acknowledgements…", null, null, Everywhere),
        new("reportProblem", MenuName.Help, "Report a Problem…", null, null, Everywhere, SeparatorBefore: true),
    ];

    /// <summary>The commands of one menu, in their order.</summary>
    public static IEnumerable<AppCommand> InMenu(MenuName menu) => All.Where(command => command.Menu == menu);

    public static AppCommand Get(string id) =>
        All.FirstOrDefault(command => command.Id == id)
        ?? throw new KeyNotFoundException($"No command named {id}.");

    /// <summary>Whether <paramref name="command"/> is enabled in a window of <paramref name="window"/>.</summary>
    public static bool IsEnabled(AppCommand command, WindowKind window) => command.AppliesIn(window);

    /// <summary>
    /// The shortcuts live in one window at a time: a key that two enabled commands of the same
    /// window both claim would fire one of them at random. This is what the test pins.
    /// </summary>
    public static IEnumerable<(Shortcut Shortcut, AppCommand First, AppCommand Second)> Collisions(WindowKind window)
    {
        var enabled = All.Where(command => IsEnabled(command, window)).ToList();
        for (var i = 0; i < enabled.Count; i++)
        {
            for (var j = i + 1; j < enabled.Count; j++)
            {
                foreach (var shortcut in enabled[i].Shortcuts())
                {
                    if (enabled[j].Shortcuts().Contains(shortcut))
                    {
                        yield return (shortcut, enabled[i], enabled[j]);
                    }
                }
            }
        }
    }

    private static IEnumerable<Shortcut> Shortcuts(this AppCommand command)
    {
        if (command.Shortcut is not null)
        {
            yield return command.Shortcut;
        }

        if (command.AlternateShortcut is not null)
        {
            yield return command.AlternateShortcut;
        }
    }
}
