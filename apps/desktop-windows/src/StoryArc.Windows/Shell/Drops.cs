using Microsoft.UI.Xaml;
using Windows.ApplicationModel.DataTransfer;

namespace StoryArc.Windows.Shell;

/// <summary>
/// The drop targets of the library and reader windows (desktop-clients task 2.42; desktop-experience
/// "Dropping files and folders on the app"). Only storage items are taken: text or an image that is
/// not a file is not accepted, so nothing happens and no error appears. What the drop holds goes to
/// <see cref="AppHost.OpenPaths"/> as paths, the same road as the command line and Explorer.
/// </summary>
internal static class Drops
{
    /// <summary><c>DragOver</c>: accept a copy when the data holds files or folders, refuse anything else silently.</summary>
    public static void Accept(DragEventArgs args)
    {
        if (args.DataView.Contains(StandardDataFormats.StorageItems))
        {
            args.AcceptedOperation = DataPackageOperation.Copy;
            args.DragUIOverride.IsCaptionVisible = false;
        }
        else
        {
            args.AcceptedOperation = DataPackageOperation.None;
        }
    }

    /// <summary><c>Drop</c>: the paths of the dropped files and folders, or none when the drop is not files.</summary>
    public static async Task<IReadOnlyList<string>> PathsAsync(DragEventArgs args)
    {
        if (!args.DataView.Contains(StandardDataFormats.StorageItems))
        {
            return [];
        }

        var deferral = args.GetDeferral();
        try
        {
            var items = await args.DataView.GetStorageItemsAsync();
            return items
                .Select(item => item.Path)
                .Where(path => !string.IsNullOrEmpty(path))
                .ToList();
        }
        catch (Exception error) when (error is UnauthorizedAccessException or System.Runtime.InteropServices.COMException)
        {
            return [];
        }
        finally
        {
            deferral.Complete();
        }
    }
}
