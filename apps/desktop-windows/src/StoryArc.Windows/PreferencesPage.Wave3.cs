using System.Globalization;
using Microsoft.UI.Xaml;
using Microsoft.UI.Xaml.Automation;
using Microsoft.UI.Xaml.Controls;
using StoryArc.Interop.Data;
using StoryArc.Interop.Export;
using StoryArc.Interop.Settings;
using StoryArc.Interop.Sync;
using StoryArc.Windows.Shell;

namespace StoryArc.Windows;

/// <summary>
/// The wave 3 rows of the settings page (desktop-clients task 3.23): downloads over an unmetered connection only, the storage of the three stores
/// each cleared on its own, the sync folder, and the diagnostic export through the file save picker.
/// </summary>
public sealed partial class PreferencesPage
{
    private static Button ActionButton(string label, Action click)
    {
        var button = new Button { Content = label };
        button.Click += (sender, args) => click();
        return button;
    }

    /// <summary>"Wi-Fi only" as a desktop reads it: over an unmetered connection only. A download the reader starts by hand still runs on a metered one.</summary>
    private ToggleSwitch UnmeteredOnlySwitch(string name, TextBlock note)
    {
        var toggle = new ToggleSwitch { IsOn = Host.Settings.Current.DownloadsUnmeteredOnly };
        toggle.Toggled += (sender, args) => Host.Settings.Update(settings => settings with { DownloadsUnmeteredOnly = toggle.IsOn });
        AutomationProperties.SetName(toggle, name);
        SetNote(note, Strings.Get("desktop_w3_downloads_metered"));
        return toggle;
    }

    /// <summary>
    /// The three stores, each with its size and cleared on its own. The note says where the data lives and that Windows does not roam it, and a
    /// full disk is named in grey with the cache to clear. The library's records are in use, so clearing them is done at the next start.
    /// </summary>
    private DropDownButton? StorageEditor(TextBlock note)
    {
        if (Host.Network is not { } network)
        {
            return null;
        }

        void Describe(string? extra)
        {
            var sizes = network.Storage.Measure();
            var lines = sizes.Select(size => StoreName(size.Kind) + " · " + DownloadQueues.Size(size.Bytes)).ToList();
            lines.Add(string.Format(CultureInfo.CurrentCulture, Strings.Get("desktop_w3_storage_where___"), Path.GetDirectoryName(StateFiles.DownloadsFolder)));
            if (network.Downloads.Queue.Rows.Any(row => row.FailureKind == "disk"))
            {
                lines.Add(Strings.Get("desktop_w3_downloads_diskFull"));
            }

            if (extra is not null)
            {
                lines.Add(extra);
            }

            SetNote(note, string.Join(Environment.NewLine, lines));
        }

        Describe(null);
        var menu = new MenuFlyout();
        foreach (var kind in Enum.GetValues<StoreKind>())
        {
            var item = new MenuFlyoutItem { Text = StoreName(kind) };
            var captured = kind;
            item.Click += async (sender, args) =>
            {
                if (await ConfirmClearAsync(captured))
                {
                    Describe(ClearStore(network, captured));
                }
            };
            menu.Items.Add(item);
        }

        var button = new DropDownButton { Content = Strings.Get("desktop_w3_storage_clear") + "…", Flyout = menu };
        AutomationProperties.SetName(button, Strings.Get("desktop_w3_storage_clear"));
        return button;
    }

    private static string StoreName(StoreKind kind) => Strings.Get(kind switch
    {
        StoreKind.Downloads => "desktop_w3_storage_downloads",
        StoreKind.Covers => "desktop_w3_storage_covers",
        _ => "desktop_w3_storage_records",
    });

    private async Task<bool> ConfirmClearAsync(StoreKind kind)
    {
        if (kind == StoreKind.Covers)
        {
            return true;
        }

        var dialog = new ContentDialog
        {
            XamlRoot = XamlRoot,
            Title = StoreName(kind),
            Content = new TextBlock
            {
                Text = Strings.Get(kind == StoreKind.Downloads ? "privacy_clear_downloads_body" : "desktop_w3_storage_clearRecordsBody"),
                TextWrapping = TextWrapping.Wrap,
            },
            PrimaryButtonText = Strings.Get("desktop_w3_storage_clear"),
            CloseButtonText = Strings.Get("shelves_cancel"),
            DefaultButton = ContentDialogButton.Close,
        };
        return await dialog.ShowAsync() == ContentDialogResult.Primary;
    }

    /// <summary>Clears one store and answers the grey line for it: what was freed, or why it could not be.</summary>
    private static string ClearStore(NetworkServices network, StoreKind kind)
    {
        if (kind == StoreKind.Records)
        {
            // The progress store is open, so its files go at the next start, before it opens again.
            _ = StateFiles.Write(StateFiles.ClearRecordsMarker, "clear");
            return Strings.Get("desktop_w3_storage_clearAtNextStart");
        }

        if (kind == StoreKind.Downloads)
        {
            foreach (var row in network.Downloads.Queue.Rows.ToList())
            {
                network.Downloads.Remove(row.Id);
            }
        }

        var result = network.Storage.Clear(kind);
        return result.Succeeded
            ? string.Format(CultureInfo.CurrentCulture, Strings.Get("desktop_w3_storage_freed___"), DownloadQueues.Size(result.FreedBytes))
            : string.Format(CultureInfo.CurrentCulture, Strings.Get("desktop_w3_storage_clearFailed___"), result.Failure);
    }

    /// <summary>The sync folder, the state of the last sync in grey, and the actions. With no folder there is no sync.</summary>
    private StackPanel? SyncEditor(TextBlock note)
    {
        if (Host.Network is not { } network)
        {
            return null;
        }

        void Describe()
        {
            var folder = Host.Settings.Current.SyncFolder;
            var state = network.Sync.State switch
            {
                SyncState.Syncing => Strings.Get("sync_status_syncing"),
                SyncState.Synced => string.Format(CultureInfo.CurrentCulture, Strings.Get("sync_status_synced_recent___"), DateTime.Now.ToString("t", CultureInfo.CurrentCulture)),
                SyncState.Unreachable => string.Format(CultureInfo.CurrentCulture, Strings.Get("sync_status_unreachable___"), folder ?? string.Empty),
                SyncState.DocumentTooNew => Strings.Get("sync_status_newer"),
                _ => string.IsNullOrEmpty(folder) ? Strings.Get("desktop_w3_sync_noFolder") : Strings.Get("sync_status_idle"),
            };
            var where = string.IsNullOrEmpty(folder)
                ? string.Empty
                : string.Format(CultureInfo.CurrentCulture, Strings.Get("desktop_w3_sync_folder___"), folder) + Environment.NewLine;
            SetNote(note, where + state);
        }

        Describe();
        network.Sync.StateChanged += () => DispatcherQueue.TryEnqueue(Describe);
        var panel = new StackPanel { Orientation = Orientation.Horizontal, Spacing = 8 };
        panel.Children.Add(ActionButton(Strings.Get("desktop_w3_sync_chooseFolder"), () => _ = ChooseSyncFolderAsync(network, Describe)));
        panel.Children.Add(ActionButton(Strings.Get("sync_now"), () =>
        {
            network.Sync.PositionChanged();
            _ = network.Sync.AtStartAsync();
        }));
        panel.Children.Add(ActionButton(Strings.Get("sync_turnOff"), () =>
        {
            Host.Settings.Update(settings => settings with { SyncFolder = null });
            Describe();
        }));
        return panel;
    }

    private async Task ChooseSyncFolderAsync(NetworkServices network, Action describe)
    {
        var picker = new Microsoft.Windows.Storage.Pickers.FolderPicker(Host.OpenLibrary().PickerWindowId);
        var picked = await picker.PickSingleFolderAsync();
        if (picked is null)
        {
            return;
        }

        Host.Settings.Update(settings => settings with { SyncFolder = picked.Path });
        describe();
        _ = network.Sync.AtStartAsync();
    }

    /// <summary>
    /// The diagnostic export: the report is shown in full with every credential and host name already removed, a save dialog asks where to put it,
    /// and a place that cannot be written is named with the reason and another is offered. Cancelling writes nothing and the text is dropped.
    /// </summary>
    private async Task ShowDiagnosticAsync()
    {
        if (Host.Network is not { } network)
        {
            return;
        }

        var text = await Task.Run(network.DiagnosticText);
        var report = new TextBox
        {
            Text = text,
            IsReadOnly = true,
            AcceptsReturn = true,
            TextWrapping = TextWrapping.NoWrap,
            FontFamily = new Microsoft.UI.Xaml.Media.FontFamily("Cascadia Mono"),
            MinWidth = 460,
            MinHeight = 280,
            MaxHeight = 420,
        };
        ScrollViewer.SetHorizontalScrollBarVisibility(report, ScrollBarVisibility.Auto);
        ScrollViewer.SetVerticalScrollBarVisibility(report, ScrollBarVisibility.Auto);
        var problem = new TextBlock
        {
            TextWrapping = TextWrapping.Wrap,
            Visibility = Visibility.Collapsed,
            Foreground = (Microsoft.UI.Xaml.Media.Brush)Application.Current.Resources["TextFillColorSecondaryBrush"],
        };
        var panel = new StackPanel { Spacing = 8 };
        panel.Children.Add(new TextBlock { Text = Strings.Get("privacy_diagnostic_note"), TextWrapping = TextWrapping.Wrap });
        panel.Children.Add(report);
        panel.Children.Add(problem);
        var dialog = new ContentDialog
        {
            XamlRoot = XamlRoot,
            Title = Strings.Get("privacy_diagnostic"),
            Content = panel,
            PrimaryButtonText = Strings.Get("desktop_w3_diagnostic_save"),
            CloseButtonText = Strings.Get("desktop_w3_diagnostic_close"),
            DefaultButton = ContentDialogButton.Primary,
        };
        string? savedTo = null;
        dialog.PrimaryButtonClick += async (sender, args) =>
        {
            var deferral = args.GetDeferral();
            try
            {
                var picker = new Microsoft.Windows.Storage.Pickers.FileSavePicker(Host.OpenLibrary().PickerWindowId)
                {
                    SuggestedFileName = "StoryArc diagnostic",
                    DefaultFileExtension = ".txt",
                };
                var picked = await picker.PickSaveFileAsync();
                var result = DiagnosticFile.Write(text, picked?.Path);
                switch (result.Outcome)
                {
                    case ExportOutcome.Saved:
                        savedTo = result.Location;
                        break;
                    case ExportOutcome.CannotWrite:
                        args.Cancel = true;
                        problem.Text = string.Format(CultureInfo.CurrentCulture, Strings.Get("desktop_w3_diagnostic_cannotWrite___"), result.Location, result.Reason);
                        problem.Visibility = Visibility.Visible;
                        break;
                    default:
                        // The reader cancelled the save dialog: nothing is written, the dialog closes and the text is dropped.
                        break;
                }
            }
            finally
            {
                deferral.Complete();
            }
        };

        _ = await dialog.ShowAsync();
        if (savedTo is not null)
        {
            var saved = new ContentDialog
            {
                XamlRoot = XamlRoot,
                Content = new TextBlock
                {
                    Text = string.Format(CultureInfo.CurrentCulture, Strings.Get("desktop_w3_diagnostic_saved___"), savedTo),
                    TextWrapping = TextWrapping.Wrap,
                },
                CloseButtonText = Strings.Get("settings_done"),
            };
            _ = await saved.ShowAsync();
        }
    }
}
