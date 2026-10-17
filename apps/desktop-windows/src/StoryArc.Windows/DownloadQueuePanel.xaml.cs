using System.Globalization;
using Microsoft.UI.Xaml;
using Microsoft.UI.Xaml.Controls;
using StoryArc.Interop.Data;
using StoryArc.Interop.Downloads;
using StoryArc.Interop.Network;
using StoryArc.Windows.Shell;

namespace StoryArc.Windows;

/// <summary>
/// The download queue (desktop-clients task 3.23). A row that waits says why in grey: the connection is metered and the download was not started by
/// hand, there is no connection, the reader paused it, the disk is full, or the limit is reached. A failure that a retry may mend says it will try
/// again; one it cannot says what is wrong. Nothing here is red and nothing posts a notification.
/// </summary>
public sealed partial class DownloadQueuePanel : UserControl
{
    private NetworkServices? _network;

    public DownloadQueuePanel()
    {
        InitializeComponent();
    }

    internal void Initialize(NetworkServices network)
    {
        _network = network;
        PauseAllButton.Content = Strings.Get("downloads_pauseAll");
        ResumeAllButton.Content = Strings.Get("downloads_resumeAll");
        EmptyNote.Text = Strings.Get("desktop_w3_downloads_queueEmpty");
        network.Changed += Rebuild;
        Rebuild();
    }

    /// <summary>The queue's rows, redrawn: the unfinished ones in the reader's order.</summary>
    internal void Rebuild()
    {
        if (_network is not { } network)
        {
            return;
        }

        var rows = network.Downloads.Queue.Rows.Where(row => row.Status != DownloadStatus.Finished).ToList();
        MeteredNote.Text = Strings.Get("desktop_w3_downloads_metered");
        MeteredNote.Visibility = network.Connection == ConnectionState.Metered ? Visibility.Visible : Visibility.Collapsed;
        EmptyNote.Visibility = rows.Count == 0 ? Visibility.Visible : Visibility.Collapsed;
        PauseAllButton.IsEnabled = rows.Count > 0;
        ResumeAllButton.IsEnabled = rows.Count > 0;
        Rows.Children.Clear();
        foreach (var row in rows)
        {
            Rows.Children.Add(Row(network, row));
        }
    }

    private static Border Row(NetworkServices network, DownloadRow row)
    {
        var isActive = network.Downloads.Active.Contains(row.Id);
        var text = new StackPanel { Spacing = 2 };
        text.Children.Add(new TextBlock { Text = row.Title, TextTrimming = TextTrimming.CharacterEllipsis });
        text.Children.Add(new TextBlock
        {
            Text = StateLine(network, row, isActive),
            TextWrapping = TextWrapping.Wrap,
            Style = (Style)Application.Current.Resources["CaptionTextBlockStyle"],
            Foreground = (Microsoft.UI.Xaml.Media.Brush)Application.Current.Resources["TextFillColorTertiaryBrush"],
        });
        if (isActive)
        {
            var progress = network.Downloads.ProgressOf(row.Id);
            text.Children.Add(new ProgressBar
            {
                IsIndeterminate = progress?.Fraction is null,
                Value = (progress?.Fraction ?? 0) * 100,
                Maximum = 100,
            });
        }

        var actions = new StackPanel { Orientation = Orientation.Horizontal, Spacing = 6 };
        var id = row.Id;
        if (isActive)
        {
            actions.Children.Add(MakeButton(Strings.Get("downloads_pause"), () => network.Downloads.Pause(id)));
        }
        else if (row.Status is DownloadStatus.Paused or DownloadStatus.Queued)
        {
            actions.Children.Add(MakeButton(Strings.Get("downloads_resume"), () => network.Downloads.Resume(id)));
        }
        else if (row.Status == DownloadStatus.Failed)
        {
            actions.Children.Add(MakeButton(Strings.Get("downloads_retry"), () => network.Downloads.Resume(id)));
        }

        actions.Children.Add(MakeButton(Strings.Get("downloads_remove"), () => network.Downloads.Remove(id)));

        var grid = new Grid { ColumnSpacing = 12 };
        grid.ColumnDefinitions.Add(new ColumnDefinition { Width = new GridLength(1, GridUnitType.Star) });
        grid.ColumnDefinitions.Add(new ColumnDefinition { Width = GridLength.Auto });
        grid.Children.Add(text);
        Grid.SetColumn(actions, 1);
        grid.Children.Add(actions);
        return new Border { Child = grid, Padding = new Thickness(0, 4, 0, 4) };
    }

    /// <summary>The grey line of a row: how far it is, or why it waits, or what failed.</summary>
    internal static string StateLine(NetworkServices network, DownloadRow row, bool isActive)
    {
        if (isActive)
        {
            var parts = new List<string>();
            if (network.Downloads.ProgressOf(row.Id) is { } progress)
            {
                parts.Add(progress.Total is { } total and > 0
                    ? string.Format(
                        CultureInfo.CurrentCulture,
                        Strings.Get("downloads_progress__lld______"),
                        (int)Math.Round(100.0 * progress.Received / total),
                        DownloadQueues.Size((long)progress.Received),
                        DownloadQueues.Size(total))
                    : string.Format(CultureInfo.CurrentCulture, Strings.Get("downloads_progress_unsized___"), DownloadQueues.Size((long)progress.Received)));
            }

            if (network.Downloads.LastAttemptOf(row.Id) is { } how && how != Resumption.Fresh)
            {
                parts.Add(Strings.Get(how == Resumption.Resumed ? "downloads_attempt_resumed" : "downloads_attempt_restarted"));
            }

            return string.Join(" · ", parts);
        }

        return row.Status switch
        {
            DownloadStatus.Paused => row.Pause switch
            {
                "waitingForUnmetered" => Strings.Get("desktop_w3_downloads_waitingForUnmetered"),
                "waitingForNetwork" => Strings.Get("desktop_w3_downloads_waitingForConnection"),
                "outOfSpace" => Strings.Get("downloads_paused_outOfSpace"),
                _ => Strings.Get("downloads_paused_byReader"),
            },
            DownloadStatus.Failed => FailureLine(network, row),
            _ => row.DownloadedBytes > 0
                ? string.Format(CultureInfo.CurrentCulture, Strings.Get("downloads_progress_unsized___"), DownloadQueues.Size(row.DownloadedBytes))
                : Strings.Get("desktop_w3_downloads_queued"),
        };
    }

    private static string FailureLine(NetworkServices network, DownloadRow row) => row.FailureKind switch
    {
        "disk" => Strings.Get("desktop_w3_downloads_diskFull"),
        "server" when row.FailureDetail is "401" or "403" => Strings.Get("desktop_w3_downloads_signInNeeded"),
        "unreadable" => Strings.Get("catalogue_acquire_unreadable"),
        "unsupported" => string.Format(CultureInfo.CurrentCulture, Strings.Get("catalogue_acquire_unsupported"), row.FailureDetail ?? string.Empty),
        _ when network.Downloads.AttemptsOf(row.Id) is > 0 and < DownloadBackoff.AttemptLimit => Strings.Get("desktop_w3_downloads_willRetry"),
        _ => Strings.Get("downloads_failure_unknown"),
    };

    private static Button MakeButton(string label, Action click)
    {
        var button = new Button { Content = label };
        button.Click += (sender, args) => click();
        return button;
    }

    private void OnPauseAll(object sender, RoutedEventArgs args) => _network?.Downloads.PauseAll();

    private void OnResumeAll(object sender, RoutedEventArgs args) => _network?.Downloads.ResumeAll();
}
