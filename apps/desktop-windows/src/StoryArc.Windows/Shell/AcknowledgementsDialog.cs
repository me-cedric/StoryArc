using Microsoft.UI.Xaml;
using Microsoft.UI.Xaml.Controls;
using StoryArc.Interop.Settings;

namespace StoryArc.Windows.Shell;

/// <summary>
/// The licence notices in the About group and the Help menu (desktop-clients task 6.3): the generated
/// <c>THIRD_PARTY_NOTICES.md</c> the build copies beside the executable, shown read-only. A build that
/// lacks the file says so in the dialog, as the other desktops do.
/// </summary>
internal static class AcknowledgementsDialog
{
    public static async Task ShowAsync(XamlRoot root)
    {
        var notices = await Task.Run(() => Acknowledgements.Load(Path.Combine(AppContext.BaseDirectory, Acknowledgements.FileName)));
        FrameworkElement content = notices is null
            ? new TextBlock { Text = Strings.Get("about_acknowledgements_unreadable"), TextWrapping = TextWrapping.Wrap }
            : new TextBox
            {
                Text = notices.Text,
                IsReadOnly = true,
                AcceptsReturn = true,
                TextWrapping = TextWrapping.Wrap,
                MinWidth = 520,
                MaxHeight = 420,
            };
        var dialog = new ContentDialog
        {
            XamlRoot = root,
            Title = Strings.Get("about_acknowledgements"),
            Content = content,
            CloseButtonText = Strings.Get("settings_done"),
        };
        _ = await dialog.ShowAsync();
    }
}
