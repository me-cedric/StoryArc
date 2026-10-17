using Microsoft.UI.Xaml;
using Microsoft.UI.Xaml.Automation;
using Microsoft.UI.Xaml.Controls;
using Microsoft.UI.Xaml.Input;
using StoryArc.Interop.Shell;
using Windows.System;

namespace StoryArc.Windows.Shell;

/// <summary>
/// Builds the menus from <see cref="CommandTable"/>, so the menu bar, the "..." overflow of a
/// narrow window and the reader's menu are one list (desktop-clients task 2.38). Each item is a
/// <c>Microsoft.UI.Xaml.Controls.MenuFlyoutItem</c> that shows its key in
/// <c>KeyboardAcceleratorTextOverride</c>. The keys themselves are
/// <c>Microsoft.UI.Xaml.Input.KeyboardAccelerator</c>s on the window's root (<see cref="AttachAccelerators"/>),
/// so they keep working while the menu bar is hidden in full screen and are registered once.
/// </summary>
/// <remarks>
/// A plain key (the arrows, Home, End, Space) is never a global accelerator: it would take the key
/// from every text field in the window, and desktop-experience "A shortcut while typing" says a
/// letter or arrow edits the text. Those keys reach the reader through its own KeyDown and the
/// mapper of task 2.39, which knows whether a text field has focus. Copy and Select All are the
/// same: the focused control answers Control+C and Control+A itself.
/// </remarks>
internal static class MenuBuilder
{
    private static readonly HashSet<string> HandledByTheFocusedControl = new(StringComparer.Ordinal) { "copy", "selectAll" };

    private static readonly IReadOnlyDictionary<MenuName, (string Key, string Label, string AccessKey)> Menus = new Dictionary<MenuName, (string, string, string)>
    {
        [MenuName.File] = ("menu_file", "File", "F"),
        [MenuName.Edit] = ("menu_edit", "Edit", "E"),
        [MenuName.View] = ("menu_view", "View", "V"),
        [MenuName.Go] = ("menu_go", "Go", "G"),
        [MenuName.Reader] = ("menu_reader", "Reader", "R"),
        [MenuName.Help] = ("menu_help", "Help", "H"),
    };

    /// <summary>
    /// Fills a <c>MenuBar</c> with the six menus. A command is enabled when its window kind applies
    /// and <paramref name="isAvailable"/> says something answers it; the rest show disabled, so the
    /// menu has the same shape in every window.
    /// </summary>
    public static void Fill(MenuBar bar, WindowKind window, Func<string, bool> isAvailable, Action<string> invoke)
    {
        bar.Items.Clear();
        foreach (var menu in Enum.GetValues<MenuName>())
        {
            var (key, label, accessKey) = Menus[menu];
            var item = new MenuBarItem { Title = Strings.Get(key, label), AccessKey = accessKey };
            AutomationProperties.SetAutomationId(item, "Menu_" + menu);
            FillItems(item.Items, menu, window, isAvailable, invoke);
            bar.Items.Add(item);
        }
    }

    /// <summary>
    /// The same six menus as sub-menus of one flyout: the "..." button of a window narrower than
    /// 720 and the reader's menu. Its items carry the key text only, like the menu bar's.
    /// </summary>
    public static MenuFlyout Overflow(WindowKind window, Func<string, bool> isAvailable, Action<string> invoke)
    {
        var flyout = new MenuFlyout();
        foreach (var menu in Enum.GetValues<MenuName>())
        {
            var (key, label, _) = Menus[menu];
            var sub = new MenuFlyoutSubItem { Text = Strings.Get(key, label) };
            AutomationProperties.SetAutomationId(sub, "Overflow_" + menu);
            FillItems(sub.Items, menu, window, isAvailable, invoke);
            flyout.Items.Add(sub);
        }

        return flyout;
    }

    /// <summary>Attaches the shortcuts of every command enabled in <paramref name="window"/> to <paramref name="root"/>, once each.</summary>
    public static void AttachAccelerators(UIElement root, WindowKind window, Func<string, bool> isAvailable, Action<string> invoke)
    {
        foreach (var command in CommandTable.All.Where(command => CommandTable.IsEnabled(command, window) && isAvailable(command.Id)))
        {
            foreach (var accelerator in Accelerators(command))
            {
                var id = command.Id;
                accelerator.Invoked += (sender, args) =>
                {
                    invoke(id);
                    args.Handled = true;
                };
                root.KeyboardAccelerators.Add(accelerator);
            }
        }
    }

    private static void FillItems(IList<MenuFlyoutItemBase> items, MenuName menu, WindowKind window, Func<string, bool> isAvailable, Action<string> invoke)
    {
        foreach (var command in CommandTable.InMenu(menu))
        {
            if (command.SeparatorBefore && items.Count > 0)
            {
                items.Add(new MenuFlyoutSeparator());
            }

            items.Add(Item(command, window, isAvailable, invoke));
        }
    }

    private static MenuFlyoutItem Item(AppCommand command, WindowKind window, Func<string, bool> isAvailable, Action<string> invoke)
    {
        var isEnabled = CommandTable.IsEnabled(command, window) && isAvailable(command.Id);
        var item = new MenuFlyoutItem
        {
            Text = Strings.Get(command.LabelKey, command.Label),
            IsEnabled = isEnabled,
        };
        AutomationProperties.SetAutomationId(item, "Command_" + command.Id);
        var id = command.Id;
        item.Click += (sender, args) => invoke(id);

        if (command.Shortcut is { } shortcut)
        {
            item.KeyboardAcceleratorTextOverride = shortcut.Display;
        }

        return item;
    }

    private static IEnumerable<KeyboardAccelerator> Accelerators(AppCommand command)
    {
        if (HandledByTheFocusedControl.Contains(command.Id))
        {
            yield break;
        }

        foreach (var shortcut in new[] { command.Shortcut, command.AlternateShortcut })
        {
            if (shortcut is null || !IsGlobal(shortcut))
            {
                continue;
            }

            foreach (var key in VirtualKeys(shortcut.Key))
            {
                yield return new KeyboardAccelerator
                {
                    Key = key,
                    Modifiers = Modifiers(shortcut.Modifiers),
                };
            }
        }
    }

    private static bool IsGlobal(Shortcut shortcut) =>
        shortcut.Modifiers != ShortcutModifiers.None
        || shortcut.Key is ShortcutKey.F3 or ShortcutKey.F5 or ShortcutKey.F11;

    private static VirtualKeyModifiers Modifiers(ShortcutModifiers modifiers)
    {
        var result = VirtualKeyModifiers.None;
        if (modifiers.HasFlag(ShortcutModifiers.Control))
        {
            result |= VirtualKeyModifiers.Control;
        }

        if (modifiers.HasFlag(ShortcutModifiers.Shift))
        {
            result |= VirtualKeyModifiers.Shift;
        }

        if (modifiers.HasFlag(ShortcutModifiers.Alt))
        {
            // Windows.System.VirtualKeyModifiers names Alt "Menu".
            result |= VirtualKeyModifiers.Menu;
        }

        return result;
    }

    /// <summary>
    /// The virtual keys of a shortcut key. <c>Windows.System.VirtualKey</c> names the letters,
    /// digits, arrows and function keys; the OEM keys carry their virtual-key codes (winuser.h:
    /// VK_OEM_PLUS 0xBB, VK_OEM_COMMA 0xBC, VK_OEM_MINUS 0xBD, VK_OEM_2 0xBF, the slash). Plus,
    /// minus and zero also answer on the number pad.
    /// </summary>
    private static IEnumerable<VirtualKey> VirtualKeys(ShortcutKey key) => key switch
    {
        ShortcutKey.A => [VirtualKey.A],
        ShortcutKey.B => [VirtualKey.B],
        ShortcutKey.C => [VirtualKey.C],
        ShortcutKey.D => [VirtualKey.D],
        ShortcutKey.F => [VirtualKey.F],
        ShortcutKey.G => [VirtualKey.G],
        ShortcutKey.H => [VirtualKey.H],
        ShortcutKey.I => [VirtualKey.I],
        ShortcutKey.L => [VirtualKey.L],
        ShortcutKey.O => [VirtualKey.O],
        ShortcutKey.Q => [VirtualKey.Q],
        ShortcutKey.R => [VirtualKey.R],
        ShortcutKey.T => [VirtualKey.T],
        ShortcutKey.W => [VirtualKey.W],
        ShortcutKey.Comma => [(VirtualKey)0xBC],
        ShortcutKey.Plus => [VirtualKey.Add, (VirtualKey)0xBB],
        ShortcutKey.Minus => [VirtualKey.Subtract, (VirtualKey)0xBD],
        ShortcutKey.Zero => [VirtualKey.Number0, VirtualKey.NumberPad0],
        ShortcutKey.One => [VirtualKey.Number1],
        ShortcutKey.Two => [VirtualKey.Number2],
        ShortcutKey.Three => [VirtualKey.Number3],
        ShortcutKey.Nine => [VirtualKey.Number9],
        ShortcutKey.Slash => [(VirtualKey)0xBF],
        ShortcutKey.F3 => [VirtualKey.F3],
        ShortcutKey.F5 => [VirtualKey.F5],
        ShortcutKey.F11 => [VirtualKey.F11],
        ShortcutKey.Left => [VirtualKey.Left],
        ShortcutKey.Right => [VirtualKey.Right],
        ShortcutKey.Home => [VirtualKey.Home],
        ShortcutKey.End => [VirtualKey.End],
        ShortcutKey.Space => [VirtualKey.Space],
        _ => [],
    };
}
