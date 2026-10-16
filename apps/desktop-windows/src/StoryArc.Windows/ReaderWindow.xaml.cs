using System.Diagnostics;
using System.Globalization;
using System.Runtime.InteropServices;
using Microsoft.UI.Windowing;
using Microsoft.UI.Xaml;
using Microsoft.UI.Xaml.Input;
using StoryArc.Interop.Reader;
using StoryArc.Interop.Shell;
using StoryArc.Windows.Shell;
using Windows.System;

namespace StoryArc.Windows;

/// <summary>
/// The reader window of one publication (desktop-clients tasks 2.37, 2.38 and 2.41). It opens at
/// its saved frame or at the default reader size, tells the host whenever it moves so the session
/// file stays current, and enters and leaves full screen with the <c>AppWindow</c> presenters:
/// <c>AppWindow.SetPresenter(AppWindowPresenterKind.FullScreen)</c> and back to
/// <c>AppWindowPresenterKind.Default</c> (Microsoft.UI.Windowing).
/// </summary>
public sealed partial class ReaderWindow : Window
{
    private static readonly TimeSpan ChromeTick = TimeSpan.FromMilliseconds(500);

    private readonly AppHost _host;
    private readonly FullScreenState _fullScreen = new(isSupported: true);
    private readonly Stopwatch _clock = Stopwatch.StartNew();
    private readonly DispatcherTimer _timer = new() { Interval = ChromeTick };
    private HoverChrome _chrome = new();
    private ReaderWindowState _lastWindowed;
    private readonly int _page;

    internal ReaderWindow(AppHost host, string publicationId, ReaderWindowState? restored)
    {
        _host = host;
        PublicationId = publicationId;
        _page = restored?.Page ?? 1;
        InitializeComponent();

        // The publication's title arrives with the library seam (task 2.1); its id names the window until then.
        Title = publicationId;
        AppTitleBar.Title = publicationId;
        ExtendsContentIntoTitleBar = true;
        SetTitleBar(AppTitleBar);
        AppWindow.SetIcon("Assets/AppIcon.ico");

        if (restored is not null)
        {
            WindowPlacement.Restore(AppWindow, restored.Frame, restored.DisplayId, restored.IsMaximized);
        }
        else
        {
            WindowPlacement.OpenAtDefault(AppWindow, WindowDefaults.ReaderWidth, WindowDefaults.ReaderHeight);
        }

        WindowPlacement.SetMinimumSize(AppWindow);
        PageText.Text = _page.ToString(CultureInfo.CurrentCulture);
        _lastWindowed = Snapshot();

        Menu.Initialize(WindowKind.Reader, IsAvailable, Invoke);
        MenuBuilder.AttachAccelerators(Root, WindowKind.Reader, IsAvailable, Invoke);

        AppWindow.Changed += OnAppWindowChanged;
        _timer.Tick += (sender, args) => SettleChrome();
        Closed += (sender, args) => _timer.Stop();
    }

    internal string PublicationId { get; }

    /// <summary>Full screen shows grey once the system has refused it and was never in it.</summary>
    private bool IsAvailable(string commandId) =>
        CommandRouting.IsHandled(commandId, WindowKind.Reader)
        && (commandId != "fullScreen" || _fullScreen.IsAvailable || _fullScreen.IsFullScreen);

    private void Invoke(string commandId) => _host.Invoke(commandId, this);

    /// <summary>What the session file keeps for this window: its last windowed frame and its page.</summary>
    internal ReaderWindowState State() => _lastWindowed;

    internal void ToggleFullScreen()
    {
        switch (_fullScreen.Toggle())
        {
            case FullScreenChange.Entered:
                EnterFullScreen();
                break;
            case FullScreenChange.Left:
                LeaveFullScreen();
                break;
        }
    }

    private void EnterFullScreen()
    {
        try
        {
            AppWindow.SetPresenter(AppWindowPresenterKind.FullScreen);
        }
        catch (Exception error) when (error is ArgumentException or InvalidOperationException or COMException)
        {
            Refuse();
            return;
        }

        if (AppWindow.Presenter.Kind != AppWindowPresenterKind.FullScreen)
        {
            // The window manager did not grant it: stay as we were.
            AppWindow.SetPresenter(AppWindowPresenterKind.Default);
            Refuse();
            return;
        }

        _chrome = new HoverChrome();
        _timer.Start();
        ShowChromeFor(isFullScreen: true);
    }

    private void Refuse()
    {
        _fullScreen.Refused();
        Menu.Initialize(WindowKind.Reader, IsAvailable, Invoke);
    }

    private void LeaveFullScreen()
    {
        _timer.Stop();
        AppWindow.SetPresenter(AppWindowPresenterKind.Default);
        WindowPlacement.SetMinimumSize(AppWindow);
        WindowPlacement.Restore(AppWindow, _lastWindowed.Frame, _lastWindowed.DisplayId, _lastWindowed.IsMaximized);
        ShowChromeFor(isFullScreen: false);
    }

    /// <summary>In a window the title bar and menu always show; in full screen the title bar is gone and the menu shows while the pointer moves.</summary>
    private void ShowChromeFor(bool isFullScreen)
    {
        AppTitleBar.Visibility = isFullScreen ? Visibility.Collapsed : Visibility.Visible;
        Menu.SetChromeVisible(!isFullScreen || _chrome.IsChromeVisible);
    }

    private void SettleChrome()
    {
        if (_chrome.Settle(_clock.Elapsed))
        {
            ShowChromeFor(isFullScreen: true);
        }
    }

    private void OnPointerMoved(object sender, PointerRoutedEventArgs args)
    {
        if (!_fullScreen.IsFullScreen)
        {
            return;
        }

        _chrome.PointerMoved(_clock.Elapsed);
        ShowChromeFor(isFullScreen: true);
    }

    private void OnKeyDown(object sender, KeyRoutedEventArgs args)
    {
        if (args.Key == VirtualKey.Escape && _fullScreen.Escape() == FullScreenChange.Left)
        {
            LeaveFullScreen();
            args.Handled = true;
        }
    }

    private void OnAppWindowChanged(AppWindow sender, AppWindowChangedEventArgs args)
    {
        if (_fullScreen.IsFullScreen || !(args.DidPositionChange || args.DidSizeChange))
        {
            return;
        }

        _lastWindowed = Snapshot();
        _host.ReaderMoved(_lastWindowed);
    }

    private ReaderWindowState Snapshot() => new(
        PublicationId,
        WindowPlacement.FrameOf(AppWindow),
        WindowPlacement.IsMaximized(AppWindow),
        WindowPlacement.DisplayIdOf(AppWindow),
        _page);
}
