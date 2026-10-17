using StoryArc.Interop.Opening;
using Windows.UI.StartScreen;

namespace StoryArc.Windows.Shell;

/// <summary>
/// The Jump List of the taskbar and the Start menu (desktop-clients task 2.42; desktop-experience
/// "Recent items in the system's launcher"). <c>Windows.UI.StartScreen.JumpList</c> is open to a
/// packaged desktop app: <c>JumpList.LoadCurrentAsync</c>, replace the items, <c>SaveAsync</c>. Each
/// item carries its path, quoted, as its arguments, so choosing it launches the app with that path,
/// which the single instance redirection hands to the running app. The system's own Recent group is
/// off, because it would list files the app never opened through this list.
/// </summary>
internal static class JumpLists
{
    /// <summary>Whether this system offers a Jump List at all; where it does not, Continue reading still shows the same publications.</summary>
    public static bool IsSupported()
    {
        try
        {
            return JumpList.IsSupported();
        }
        catch (Exception error) when (error is System.Runtime.InteropServices.COMException or InvalidOperationException)
        {
            return false;
        }
    }

    /// <summary>Writes <paramref name="recent"/> to the Jump List, newest first. A list that cannot be written is left as it was.</summary>
    public static async Task UpdateAsync(RecentItems recent)
    {
        if (!IsSupported())
        {
            return;
        }

        try
        {
            var list = await JumpList.LoadCurrentAsync();
            list.SystemGroupKind = JumpListSystemGroupKind.None;
            list.Items.Clear();
            var group = Strings.Get("menu_openRecent", "Open Recent");
            foreach (var item in recent.Items)
            {
                var entry = JumpListItem.CreateWithArguments(LaunchArguments.Quote(item.Path), item.Title);
                entry.GroupName = group;
                entry.Description = item.Path;
                list.Items.Add(entry);
            }

            await list.SaveAsync();
        }
        catch (Exception error) when (error is System.Runtime.InteropServices.COMException or UnauthorizedAccessException)
        {
            // The shell refused the write; the in-app recent list and Continue reading still hold the items.
        }
    }
}
