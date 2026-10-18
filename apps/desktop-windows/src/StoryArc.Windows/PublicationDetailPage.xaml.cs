using System.Globalization;
using Microsoft.UI.Xaml;
using Microsoft.UI.Xaml.Controls;
using Microsoft.UI.Xaml.Navigation;
using StoryArc.Interop.Library;
using StoryArc.Interop.Playback;
using StoryArc.Windows.Library;
using StoryArc.Windows.Shell;

namespace StoryArc.Windows;

/// <summary>What the library window hands the detail page when it navigates to it.</summary>
/// <param name="Open">Opens the publication in its reader window.</param>
/// <param name="SavedListening">Where a narrated book was left, or <c>null</c>.</param>
/// <param name="ListenFrom">Starts a narrated book at a chapter the listener chose.</param>
internal sealed record DetailRequest(
    LibraryRecord Record,
    bool IsSourceAvailable,
    Action<LibraryRecord> Open,
    Func<string, TimeSpan?>? SavedListening = null,
    Action<LibraryRecord, TimeSpan>? ListenFrom = null);

/// <summary>
/// The detail page of one publication (desktop-clients task 2.47d). Its content is
/// <see cref="PublicationDetail.Of"/>; this page only draws it and answers its two actions.
/// </summary>
public sealed partial class PublicationDetailPage : Page
{
    private DetailRequest? _request;
    private PublicationDetail? _detail;

    public PublicationDetailPage()
    {
        InitializeComponent();
        MoreButton.Content = Strings.Get("detail_more", "More actions");
        ShowInFolderItem.Text = Strings.Get("detail_showInFolder", "Show in folder");
    }

    protected override async void OnNavigatedTo(NavigationEventArgs e)
    {
        base.OnNavigatedTo(e);
        if (e.Parameter is not DetailRequest request)
        {
            return;
        }

        _request = request;
        var detail = PublicationDetail.Of(request.Record, request.IsSourceAvailable);
        _detail = detail;

        TitleText.Text = detail.Title;
        SubtitleText.Text = detail.Subtitle ?? string.Empty;
        SubtitleText.Visibility = detail.Subtitle is null ? Visibility.Collapsed : Visibility.Visible;
        CreditsText.Text = string.Join(", ", detail.Credits);
        SummaryText.Text = detail.Summary ?? string.Empty;
        Progress.Value = Math.Round(detail.Progress * 100);
        Progress.Visibility = detail.Progress > 0 && detail.Progress < 1 ? Visibility.Visible : Visibility.Collapsed;

        PrimaryButton.Content = detail.Action switch
        {
            DetailAction.Continue => Strings.Get("home_resume", "Resume"),
            DetailAction.ReadAgain => Strings.Get("detail_readAgain", "Read again"),
            DetailAction.Unavailable => Strings.Get("catalogue_detail_read", "Read"),
            _ => Strings.Get("catalogue_detail_read", "Read"),
        };
        PrimaryButton.IsEnabled = detail.Action != DetailAction.Unavailable;

        var folder = Path.GetFileName(detail.Folder.TrimEnd(Path.DirectorySeparatorChar)) is { Length: > 0 } name ? name : detail.Folder;
        LocationText.Text = detail.Location == DetailLocation.OnDevice
            ? $"{Strings.Get("detail_provenance_device", "On this device, readable with no network")} · {detail.Folder}"
            : string.Format(CultureInfo.CurrentCulture, Strings.Get("detail_provenance_away___", "From {0}, not answering right now"), folder);
        LocationText.Foreground = (Microsoft.UI.Xaml.Media.Brush)Application.Current.Resources[
            detail.Location == DetailLocation.OnDevice ? "TextFillColorSecondaryBrush" : "TextFillColorTertiaryBrush"];

        var reason = detail.UnavailableReason
            ?? (detail.Action == DetailAction.Unavailable ? Strings.Get("library_cell_unavailable", "Needs its library to be reachable") : null);
        UnavailableText.Text = reason ?? string.Empty;
        UnavailableText.Visibility = reason is null ? Visibility.Collapsed : Visibility.Visible;

        if (request.Record.Format == PublicationFormat.Audiobook && detail.Action != DetailAction.Unavailable && File.Exists(request.Record.Id))
        {
            await ShowAudiobookAsync(request);
        }

        if (detail.Cover == DetailCover.Wash && request.IsSourceAvailable)
        {
            var cover = await CoverLoader.LoadAsync(detail.Id);
            Cover.Source = cover;
            Wash.Source = cover;
        }
    }

    /// <summary>
    /// The audiobook's chapters, read from the file before it plays, each with its length and its mark; the primary action
    /// names the chapter it resumes inside. Looking at the list moves nothing.
    /// </summary>
    private async Task ShowAudiobookAsync(DetailRequest request)
    {
        var read = await PlaybackService.ReadChaptersAsync(request.Record.Id);
        if (read is not { } book || _request != request)
        {
            return;
        }

        var audio = AudiobookDetail.Of(book.Chapters, book.Duration, request.SavedListening?.Invoke(request.Record.Id));
        PrimaryButton.Content = audio.PrimaryLabel(
            Strings.Get("detail_listen", "Listen"),
            Strings.Get("detail_continueListening_in___", "Continue {0}"),
            Strings.Get("detail_continueListening", "Continue listening"));
        DurationText.Text = string.Format(CultureInfo.CurrentCulture, Strings.Get("detail_duration___", "Duration {0}"), PlayerModel.Clock(audio.Duration));
        ChaptersTitle.Text = Strings.Get("detail_chapters", "Chapters");
        ChaptersTitle.Visibility = audio.ListsChapters ? Visibility.Visible : Visibility.Collapsed;
        ChapterList.Visibility = audio.ListsChapters ? Visibility.Visible : Visibility.Collapsed;
        ChapterList.Items.Clear();
        if (audio.ListsChapters)
        {
            foreach (var row in audio.Rows)
            {
                var mark = row.Mark switch
                {
                    ChapterMark.Finished => Strings.Get("detail_chapter_finished", "Finished"),
                    ChapterMark.InProgress when row.Remaining is { } left => string.Format(CultureInfo.CurrentCulture, Strings.Get("detail_chapter_remaining___", "{0} left"), PlayerModel.Clock(left)),
                    _ => string.Empty,
                };
                var detail = mark.Length == 0 ? PlayerModel.Clock(row.Duration) : PlayerModel.Clock(row.Duration) + " · " + mark;
                var item = new ListViewItem
                {
                    Content = new StackPanel { Children = { new TextBlock { Text = row.Title, TextWrapping = TextWrapping.Wrap }, new TextBlock { Text = detail, Style = (Style)Application.Current.Resources["CaptionTextBlockStyle"] } } },
                    Tag = book.Chapters[row.Index].Start,
                };
                Microsoft.UI.Xaml.Automation.AutomationProperties.SetName(item, row.Title + ", " + detail);
                ChapterList.Items.Add(item);
            }
        }

        AudioSection.Visibility = Visibility.Visible;
    }

    private void OnChapterClick(object sender, ItemClickEventArgs e)
    {
        if (e.ClickedItem is ListViewItem { Tag: TimeSpan start } && _request is { ListenFrom: { } listen } request)
        {
            listen(request.Record, start);
        }
    }

    private void OnPrimary(object sender, RoutedEventArgs e)
    {
        if (_request is { } request && _detail is { Action: not DetailAction.Unavailable })
        {
            request.Open(request.Record);
        }
    }

    /// <summary>Opens Explorer on the folder with the file selected: <c>explorer.exe /select,"path"</c>.</summary>
    private void OnShowInFolder(object sender, RoutedEventArgs e)
    {
        if (_detail is null || !File.Exists(_detail.Id))
        {
            return;
        }

        try
        {
            System.Diagnostics.Process.Start(new System.Diagnostics.ProcessStartInfo("explorer.exe", $"/select,\"{_detail.Id}\"") { UseShellExecute = true });
        }
        catch (System.ComponentModel.Win32Exception)
        {
            // Explorer did not start; the location line still names the folder.
        }
    }
}
