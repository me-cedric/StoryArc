using System.Globalization;
using Microsoft.UI.Xaml;
using Microsoft.UI.Xaml.Automation;
using StoryArc.Interop.Playback;
using StoryArc.Windows.Shell;

namespace StoryArc.Windows;

/// <summary>The compact player bar of the library window (desktop-clients task 4.20), drawn from <see cref="PlaybackService"/>.</summary>
public sealed partial class MainWindow
{
    private static readonly TimeSpan NoticeFor = TimeSpan.FromSeconds(6);
    private DispatcherTimer? _noticeTimer;
    private string? _notice;

    private void InitializePlayerBar()
    {
        AutomationProperties.SetName(PlayerBarOpen, Strings.Get("player_open", "Open the player"));
        if (_host.Playback is not { } playback)
        {
            return;
        }

        playback.Changed += DrawPlayerBar;
        playback.VoiceStopped += title =>
        {
            // Told once that the voice stopped, rather than discovering it by silence (read-aloud, "Opening a different publication").
            _notice = string.Format(CultureInfo.CurrentCulture, Strings.Get("player_voice_stopped___", "Stopped reading \u201c{0}\u201d aloud."), title);
            _noticeTimer ??= new DispatcherTimer { Interval = NoticeFor };
            _noticeTimer.Tick -= OnNoticeElapsed;
            _noticeTimer.Tick += OnNoticeElapsed;
            _noticeTimer.Start();
            DrawPlayerBar();
        };
        Closed += (sender, args) =>
        {
            playback.Changed -= DrawPlayerBar;
            _noticeTimer?.Stop();
        };
        DrawPlayerBar();
    }

    private void OnNoticeElapsed(object? sender, object args)
    {
        _noticeTimer?.Stop();
        _notice = null;
        DrawPlayerBar();
    }

    private void DrawPlayerBar()
    {
        var model = _host.Playback?.Model;
        var line = model?.CompactLine(Strings.Get("player_nowPlaying_value______", "{0}, {1}"));
        if (line is null && _notice is null)
        {
            PlayerBar.Visibility = Visibility.Collapsed;
            return;
        }

        PlayerBar.Visibility = Visibility.Visible;
        PlayerBarText.Text = _notice ?? line ?? string.Empty;
        var isActive = model?.IsActive == true;
        PlayerBarPlay.Visibility = isActive ? Visibility.Visible : Visibility.Collapsed;
        PlayerBarOpen.Visibility = isActive ? Visibility.Visible : Visibility.Collapsed;
        var isPlaying = model?.Session.IsPlaying == true;
        PlayerBarGlyph.Glyph = isPlaying ? "\uE769" : "\uE768";
        AutomationProperties.SetName(PlayerBarPlay, isPlaying ? Strings.Get("player_pause", "Pause") : Strings.Get("player_play", "Play"));
        // Announced as one element naming what is playing (audio-playback, "The compact bar under a screen reader").
        AutomationProperties.SetName(PlayerBar, Strings.Get("player_nowPlaying", "Now playing") + ": " + (line ?? string.Empty));
    }

    private void OnPlayerBarPlay(object sender, RoutedEventArgs args) => _host.Playback?.TogglePlayPause();

    private void OnPlayerBarOpen(object sender, RoutedEventArgs args) => _host.OpenPlayer();
}
