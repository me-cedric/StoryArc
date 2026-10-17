using Microsoft.UI.Xaml;
using Microsoft.UI.Xaml.Automation;
using Microsoft.UI.Xaml.Controls;
using StoryArc.Interop.Shell;
using StoryArc.Windows.Shell;

namespace StoryArc.Windows;

public sealed partial class AppMenu : UserControl
{
    /// <summary>Below this width the menu bar becomes one button (docs/designs/desktop/windows.md, section 6).</summary>
    private const double OverflowBelowDip = 720;

    public AppMenu()
    {
        InitializeComponent();
    }

    /// <summary>Builds the menus for a window of <paramref name="kind"/>; <paramref name="invoke"/> receives the command id. Calling it again rebuilds them.</summary>
    internal void Initialize(WindowKind kind, Func<string, bool> isAvailable, Action<string> invoke)
    {
        MenuBuilder.Fill(Bar, kind, isAvailable, invoke);
        OverflowButton.Flyout = MenuBuilder.Overflow(kind, isAvailable, invoke);
        AutomationProperties.SetName(OverflowButton, Strings.Get("reader_menu", "Menu"));
    }

    /// <summary>The menu bar is hidden in full screen until the pointer moves; the shortcuts stay on the window.</summary>
    internal void SetChromeVisible(bool isVisible) =>
        Visibility = isVisible ? Visibility.Visible : Visibility.Collapsed;

    private void OnSizeChanged(object sender, SizeChangedEventArgs args)
    {
        var isNarrow = args.NewSize.Width < OverflowBelowDip;
        Bar.Visibility = isNarrow ? Visibility.Collapsed : Visibility.Visible;
        OverflowButton.Visibility = isNarrow ? Visibility.Visible : Visibility.Collapsed;
    }
}
