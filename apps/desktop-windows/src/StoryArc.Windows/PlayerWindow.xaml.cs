using System.Globalization;
using Microsoft.UI.Xaml;
using Microsoft.UI.Xaml.Automation;
using Microsoft.UI.Xaml.Controls;
using Microsoft.UI.Xaml.Controls.Primitives;
using Microsoft.UI.Xaml.Media.Imaging;
using StoryArc.Interop.Playback;
using StoryArc.Interop.Shell;
using StoryArc.Windows.Shell;

namespace StoryArc.Windows;

/// <summary>
/// The player window (desktop-clients task 4.20) over <see cref="PlaybackService"/>: it draws what
/// <see cref="PlayerModel"/> says and sends it what the listener does. Playback outlives it: closing
/// the window leaves the session running, and the compact bar in the library opens it again.
/// </summary>
public sealed partial class PlayerWindow : Window, IPublicationWindow
{
    private const int PlayerWidth = 420;
    private const int PlayerHeight = 640;

    private readonly AppHost _host;
    private readonly PlaybackService _playback;
    private readonly string _publicationId;
    private bool _isDrawing;
    private string? _coverShown;
    private int _chapterRowsShown = -1;

    internal PlayerWindow(AppHost host, PlaybackService playback, string publicationId, ReaderWindowState? restored)
    {
        _host = host;
        _playback = playback;
        _publicationId = publicationId;
        InitializeComponent();

        Title = Strings.Get("player_nowPlaying", "Now playing");
        AppTitleBar.Title = Title;
        ExtendsContentIntoTitleBar = true;
        SetTitleBar(AppTitleBar);
        AppWindow.SetIcon("Assets/AppIcon.ico");
        if (restored is not null)
        {
            WindowPlacement.Restore(AppWindow, restored.Frame, restored.DisplayId, restored.IsMaximized);
        }
        else
        {
            WindowPlacement.OpenAtDefault(AppWindow, PlayerWidth, PlayerHeight);
        }

        Menu.Initialize(WindowKind.Player, IsAvailable, Invoke);
        MenuBuilder.AttachAccelerators(Root, WindowKind.Player, IsAvailable, Invoke);

        AutomationProperties.SetName(BackButton, string.Format(CultureInfo.CurrentCulture, Strings.Get("player_skip_back___", "{0} back"), PlayerModel.Clock(Skips.Back)));
        AutomationProperties.SetName(ForwardButton, string.Format(CultureInfo.CurrentCulture, Strings.Get("player_skip_forward___", "{0} forward"), PlayerModel.Clock(Skips.Forward)));
        AutomationProperties.SetName(Scrubber, Strings.Get("player_position", "Position"));
        AutomationProperties.SetName(SpeedBox, Strings.Get("player_speed", "Speed"));
        AutomationProperties.SetName(SleepBox, Strings.Get("player_sleep", "Sleep timer"));
        ChaptersTitle.Text = Strings.Get("player_chapters", "Chapters");

        foreach (var rate in PlaybackSpeed.Offered)
        {
            SpeedBox.Items.Add(new ComboBoxItem { Content = string.Format(CultureInfo.CurrentCulture, Strings.Get("player_speed_value___", "{0}×"), PlaybackSpeed.Label(rate)), Tag = rate });
        }

        SleepBox.Items.Add(new ComboBoxItem { Content = Strings.Get("player_sleep_off", "Off"), Tag = null });
        foreach (var duration in SleepTimer.Durations)
        {
            SleepBox.Items.Add(new ComboBoxItem { Content = PlayerModel.Clock(duration), Tag = new SleepTimer(duration) });
        }

        SleepBox.Items.Add(new ComboBoxItem { Content = Strings.Get("player_sleep_endOfChapter", "End of chapter"), Tag = SleepTimer.EndOfChapter });

        _playback.Changed += Draw;
        Closed += (sender, args) => _playback.Changed -= Draw;
        Draw();
    }

    public string PublicationId => _publicationId;

    public ReaderWindowState State() => new(
        _publicationId,
        WindowPlacement.FrameOf(AppWindow),
        WindowPlacement.IsMaximized(AppWindow),
        WindowPlacement.DisplayIdOf(AppWindow),
        (int)_playback.Model.Position.TotalSeconds + 1);

    public void Run(string commandId)
    {
        switch (commandId)
        {
            case "playPause":
                _playback.TogglePlayPause();
                break;
            case "skipBack":
                _playback.SkipBack();
                break;
            case "skipForward":
                _playback.SkipForward();
                break;
            case "nextChapter":
                _playback.Model.NextChapter();
                break;
            case "previousChapter":
                _playback.Model.PreviousChapter();
                break;
        }
    }

    private void Draw()
    {
        var model = _playback.Model;
        _isDrawing = true;
        try
        {
            var item = model.Item;
            TitleText.Text = item?.Title ?? string.Empty;
            var transport = model.Transport();
            ChapterText.Text = transport?.Subtitle ?? (model.LastEnd == EndReason.None ? string.Empty : Strings.Get("player_finished_stopped", "Playback stopped"));
            var duration = item?.Duration ?? TimeSpan.Zero;
            Scrubber.Maximum = Math.Max(1, duration.TotalSeconds);
            Scrubber.Value = model.Position.TotalSeconds;
            Scrubber.IsEnabled = model.IsActive && item?.Kind == PlaybackKind.Narrated;
            ElapsedText.Text = PlayerModel.Clock(model.Position);
            RemainingText.Text = "−" + PlayerModel.Clock(duration - model.Position);
            AutomationProperties.SetHelpText(Scrubber, PlayerModel.Clock(model.Position));

            var isPlaying = model.Session.IsPlaying;
            PlayGlyph.Glyph = isPlaying ? "" : "";
            AutomationProperties.SetName(PlayButton, isPlaying ? Strings.Get("player_pause", "Pause") : Strings.Get("player_play", "Play"));
            PlayButton.IsEnabled = model.IsActive;
            BackButton.IsEnabled = model.IsActive;
            ForwardButton.IsEnabled = model.IsActive;

            SelectTag(SpeedBox, tag => tag is double rate && Math.Abs(rate - model.Speed) < 0.001);
            var sleeping = model.Sleep;
            SelectTag(SleepBox, tag => sleeping is null ? tag is null : tag is SleepTimer timer && timer == sleeping.Timer);
            if (sleeping is { } sleep)
            {
                SleepText.Text = string.Format(CultureInfo.CurrentCulture, Strings.Get("player_sleep_remaining___", "{0} left"), PlayerModel.Clock(sleep.Remaining));
                SleepText.Visibility = Visibility.Visible;
            }
            else
            {
                SleepText.Visibility = Visibility.Collapsed;
            }

            if (item?.CoverPath != _coverShown)
            {
                _coverShown = item?.CoverPath;
                Cover.Source = _coverShown is { } path && File.Exists(path) ? new BitmapImage(new Uri(path)) : null;
            }

            DrawChapters(model);
        }
        finally
        {
            _isDrawing = false;
        }
    }

    private void DrawChapters(PlayerModel model)
    {
        var rows = model.ChapterRows();
        var current = model.CurrentChapter ?? -1;
        if (rows.Count != ChapterList.Items.Count || _chapterRowsShown != current)
        {
            _chapterRowsShown = current;
            ChapterList.Items.Clear();
            foreach (var row in rows)
            {
                var mark = row.Mark switch
                {
                    ChapterMark.Finished => Strings.Get("player_chapter_finished", "Finished"),
                    ChapterMark.InProgress => Strings.Get("player_chapter_inProgress", "In progress"),
                    _ => string.Empty,
                };
                var remaining = row.Remaining is { } left ? string.Format(CultureInfo.CurrentCulture, Strings.Get("player_chapter_remaining___", "{0} left"), PlayerModel.Clock(left)) : string.Empty;
                var detail = string.Join(" · ", new[] { PlayerModel.Clock(row.Duration), mark, remaining }.Where(part => part.Length > 0));
                var item = new ListViewItem
                {
                    Content = new StackPanel
                    {
                        Children =
                        {
                            new TextBlock { Text = row.Title, FontWeight = row.Mark == ChapterMark.InProgress ? Microsoft.UI.Text.FontWeights.SemiBold : Microsoft.UI.Text.FontWeights.Normal },
                            new TextBlock { Text = detail, Style = (Style)Application.Current.Resources["CaptionTextBlockStyle"] },
                        },
                    },
                    Tag = row.Index,
                };
                // A screen reader hears the chapter, its duration, its mark and the remaining time as one control (audio-playback, "Chapters").
                AutomationProperties.SetName(item, row.Title + ", " + detail);
                ChapterList.Items.Add(item);
            }
        }

        ChaptersTitle.Visibility = rows.Count == 0 ? Visibility.Collapsed : Visibility.Visible;
    }

    private static void SelectTag(ComboBox box, Func<object?, bool> matches)
    {
        for (var index = 0; index < box.Items.Count; index++)
        {
            if (box.Items[index] is ComboBoxItem item && matches(item.Tag))
            {
                if (box.SelectedIndex != index)
                {
                    box.SelectedIndex = index;
                }

                return;
            }
        }
    }

    private void OnPlayPause(object sender, RoutedEventArgs args) => _playback.TogglePlayPause();

    private void OnSkipBack(object sender, RoutedEventArgs args) => _playback.SkipBack();

    private void OnSkipForward(object sender, RoutedEventArgs args) => _playback.SkipForward();

    private void OnScrubbed(object sender, RangeBaseValueChangedEventArgs args)
    {
        if (!_isDrawing && Scrubber.IsEnabled)
        {
            _playback.SeekTo(TimeSpan.FromSeconds(args.NewValue));
        }
    }

    private void OnSpeedChanged(object sender, SelectionChangedEventArgs args)
    {
        if (!_isDrawing && SpeedBox.SelectedItem is ComboBoxItem { Tag: double rate })
        {
            _playback.Model.SetSpeed(rate);
        }
    }

    private void OnSleepChanged(object sender, SelectionChangedEventArgs args)
    {
        if (!_isDrawing && SleepBox.SelectedItem is ComboBoxItem item)
        {
            _playback.Model.SetSleep(item.Tag as SleepTimer);
        }
    }

    private void OnChapterClick(object sender, ItemClickEventArgs args)
    {
        if (args.ClickedItem is ListViewItem { Tag: int index } && _playback.Model.Item is { } item && index < item.Chapters.Count)
        {
            _playback.SeekTo(item.Chapters[index].Start);
        }
    }

    private static bool IsAvailable(string commandId) =>
        CommandRouting.IsHandled(commandId, WindowKind.Player) || commandId is "playPause" or "skipBack" or "skipForward" or "nextChapter" or "previousChapter";

    private void Invoke(string commandId) => _host.Invoke(commandId, this);
}
