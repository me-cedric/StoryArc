using System.Diagnostics;
using System.Runtime.InteropServices;
using Microsoft.UI.Input;
using Microsoft.UI.Windowing;
using Microsoft.UI.Xaml;
using Microsoft.UI.Xaml.Automation.Peers;
using Microsoft.UI.Xaml.Controls;
using Microsoft.UI.Xaml.Input;
using StoryArc.Interop.Opening;
using StoryArc.Interop.Reader;
using StoryArc.Interop.Shell;
using StoryArc.Windows.Shell;
using Windows.System;
using Windows.UI.Core;

namespace StoryArc.Windows;

/// <summary>
/// The reader window of one publication (desktop-clients tasks 2.37 to 2.41). It opens at its
/// saved frame or at the default reader size, shows one page or two facing pages through
/// <see cref="ReaderPageView"/>, turns by key, click zone, wheel and drag through the pure rules of
/// StoryArc.Interop, reports every turn to the host's progress writer, and enters and leaves full
/// screen with <c>AppWindow.SetPresenter(AppWindowPresenterKind.FullScreen)</c> and back to
/// <c>AppWindowPresenterKind.Default</c> (Microsoft.UI.Windowing).
/// </summary>
public sealed partial class ReaderWindow : Window
{
    private static readonly TimeSpan ChromeTick = TimeSpan.FromMilliseconds(500);

    /// <summary>How long a click waits to learn whether it is the first half of a double click, which zooms instead of turning.</summary>
    private static readonly TimeSpan ClickSettle = TimeSpan.FromMilliseconds(250);

    /// <summary>One wheel notch. A precision touchpad sends many small deltas; a page turns once per notch's worth.</summary>
    private const int WheelNotch = 120;

    private readonly AppHost _host;
    private readonly OpenedPublication _opened;
    private readonly PageNavigator _navigator;
    private readonly ReaderPageView _pages;
    private readonly FullScreenState _fullScreen = new(isSupported: true);
    private readonly Stopwatch _clock = Stopwatch.StartNew();
    private readonly DispatcherTimer _timer = new() { Interval = ChromeTick };
    private readonly CursorHider _cursor = new();
    private HoverChrome _chrome = new();
    private ReaderWindowState _lastWindowed;
    private readonly DispatcherTimer _clickTimer = new() { Interval = ClickSettle };
    private double? _dragStartX;
    private PageAction _pendingClick = PageAction.None;
    private int _wheel;

    internal ReaderWindow(AppHost host, OpenedPublication opened, ReaderWindowState? restored, int startPage)
    {
        _host = host;
        _opened = opened;
        InitializeComponent();

        var declaredWide = Enumerable.Empty<int>();
        _navigator = new PageNavigator(opened.PageCount, opened.Record.IsRightToLeft, startPage, declaredWide);
        _pages = new ReaderPageView(opened, _navigator, this);

        Title = opened.Record.DisplayTitle;
        AppTitleBar.Title = opened.Record.DisplayTitle;
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
        _lastWindowed = Snapshot();

        Menu.Initialize(WindowKind.Reader, IsAvailable, Invoke);
        MenuBuilder.AttachAccelerators(Root, WindowKind.Reader, IsAvailable, Invoke);

        // The ScrollViewer takes the pointer for itself; the reader still wants to see a press and a
        // release to read a click zone or a drag, so it listens to the handled events too.
        PageScroller.AddHandler(UIElement.PointerPressedEvent, new PointerEventHandler(OnPagePointerPressed), handledEventsToo: true);
        PageScroller.AddHandler(UIElement.PointerReleasedEvent, new PointerEventHandler(OnPagePointerReleased), handledEventsToo: true);
        PageScroller.AddHandler(UIElement.PointerWheelChangedEvent, new PointerEventHandler(OnPageWheel), handledEventsToo: true);

        AppWindow.Changed += OnAppWindowChanged;
        _timer.Tick += (sender, args) => SettleChrome();
        _timer.Start();
        _clickTimer.Tick += (sender, args) =>
        {
            _clickTimer.Stop();
            var action = _pendingClick;
            _pendingClick = PageAction.None;
            Turn(action);
        };
        Activated += (sender, args) =>
        {
            if (args.WindowActivationState != WindowActivationState.Deactivated)
            {
                PageScroller.Focus(FocusState.Programmatic);
            }
        };
        Closed += (sender, args) =>
        {
            _timer.Stop();
            _clickTimer.Stop();
            _cursor.SetHidden(false);
            _opened.Dispose();
        };

        PageMoved();
    }

    internal string PublicationId => _opened.Id;

    internal ScrollViewer Scroller => PageScroller;

    internal (Grid Slot, Image Image, Border Placeholder, TextBlock Reason) FirstSlotParts => (FirstSlot, FirstPage, FirstPlaceholder, FirstReason);

    internal (Grid Slot, Image Image, Border Placeholder, TextBlock Reason) SecondSlotParts => (SecondSlot, SecondPage, SecondPlaceholder, SecondReason);

    /// <summary>What the session file keeps for this window: its last windowed frame and its page, counted from one.</summary>
    internal ReaderWindowState State() => _lastWindowed with { Page = _navigator.CurrentPage + 1 };

    /// <summary>Says in grey, under the page, that the rest of the publication cannot be read; the pages held stay.</summary>
    internal void ShowUnavailable(string sentence)
    {
        UnavailableText.Text = sentence;
        UnavailableText.Visibility = Visibility.Visible;
    }

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

    /// <summary>The reader's commands from the menu or a shortcut. The page keys arrive through <see cref="OnKeyDown"/> instead.</summary>
    internal void Run(string commandId)
    {
        switch (commandId)
        {
            case "nextPage":
                Turn(PageAction.Next);
                break;
            case "previousPage":
                Turn(PageAction.Previous);
                break;
            case "firstPage":
                Turn(PageAction.First);
                break;
            case "lastPage":
                Turn(PageAction.Last);
                break;
            case "singlePage":
                _navigator.ForceSinglePage(true);
                PageMoved();
                break;
            case "twoPages":
                _navigator.ForceSinglePage(false);
                PageMoved();
                break;
            case "zoomIn":
                _pages.ZoomTo(PageZoom.StepIn(PageScroller.ZoomFactor), anchor: null);
                break;
            case "zoomOut":
                _pages.ZoomTo(PageZoom.StepOut(PageScroller.ZoomFactor), anchor: null);
                break;
            case "fitPage":
                _pages.ZoomTo(PageZoom.Floor, anchor: null);
                break;
        }
    }

    /// <summary>Full screen shows grey once the system has refused it and was never in it.</summary>
    private bool IsAvailable(string commandId) =>
        CommandRouting.IsHandled(commandId, WindowKind.Reader)
        && (commandId != "fullScreen" || _fullScreen.IsAvailable || _fullScreen.IsFullScreen);

    private void Invoke(string commandId) => _host.Invoke(commandId, this);

    private void Turn(PageAction action)
    {
        if (action == PageAction.ToggleChrome)
        {
            _chrome.Toggle(_clock.Elapsed);
            ShowChrome();
            return;
        }

        if (_navigator.Apply(action))
        {
            _pages.ZoomTo(PageZoom.Floor, anchor: null);
            PageMoved();
        }
    }

    /// <summary>After any move: draw the slot, name the page for Narrator, and tell the host for the progress cadence and the session.</summary>
    private void PageMoved()
    {
        _pages.Show();
        var current = _navigator.CurrentPage + 1;
        PageLabel.Text = string.Format(
            System.Globalization.CultureInfo.CurrentCulture,
            Strings.Get("reader_pageLabel__lld__lld", "Page {0} of {1}"),
            current,
            _navigator.PageCount);
        FrameworkElementAutomationPeer.FromElement(PageLabel)?.RaiseAutomationEvent(AutomationEvents.LiveRegionChanged);
        _host.PageTurned(PublicationId, _navigator.CurrentPage);
        _host.ReaderMoved(State());
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
        ShowChrome();
    }

    private void Refuse()
    {
        _fullScreen.Refused();
        Menu.Initialize(WindowKind.Reader, IsAvailable, Invoke);
    }

    private void LeaveFullScreen()
    {
        AppWindow.SetPresenter(AppWindowPresenterKind.Default);
        WindowPlacement.SetMinimumSize(AppWindow);
        WindowPlacement.Restore(AppWindow, _lastWindowed.Frame, _lastWindowed.DisplayId, _lastWindowed.IsMaximized);
        ShowChrome();
    }

    /// <summary>
    /// In a window the title bar and the menu always show and the page line follows the pointer; in
    /// full screen the title bar is gone and the menu shows only while the pointer moves. A resting
    /// pointer hides with the chrome (desktop-experience, "Revealing chrome").
    /// </summary>
    private void ShowChrome()
    {
        var isFullScreen = _fullScreen.IsFullScreen;
        AppTitleBar.Visibility = isFullScreen ? Visibility.Collapsed : Visibility.Visible;
        Menu.SetChromeVisible(!isFullScreen || _chrome.IsChromeVisible);
        PageChrome.Opacity = _chrome.IsChromeVisible ? 1 : 0;
        _cursor.SetHidden(_chrome.IsPointerHidden);
    }

    private void SettleChrome()
    {
        if (_chrome.Settle(_clock.Elapsed))
        {
            ShowChrome();
        }
    }

    private void OnPointerMoved(object sender, PointerRoutedEventArgs args)
    {
        _chrome.PointerMoved(_clock.Elapsed);
        ShowChrome();
        if (_dragStartX is { } start && !_pages.IsZoomed)
        {
            var x = args.GetCurrentPoint(PageScroller).Position.X;
            _pages.Follow(DragTurn.Travel(x - start, PageScroller.ActualWidth));
        }
    }

    /// <summary>The pointer left the window: it shows again, and the chrome stays until the reader asks.</summary>
    private void OnPointerExited(object sender, PointerRoutedEventArgs args)
    {
        _chrome.PointerLeft();
        ShowChrome();
    }

    private void OnPagePointerPressed(object sender, PointerRoutedEventArgs args)
    {
        var point = args.GetCurrentPoint(PageScroller);
        if (point.Properties.IsLeftButtonPressed && !_pages.IsZoomed)
        {
            _dragStartX = point.Position.X;
        }
    }

    /// <summary>A release ends a drag: past the threshold it turns, short of it the page settles back; with no travel it is a click on a zone.</summary>
    private void OnPagePointerReleased(object sender, PointerRoutedEventArgs args)
    {
        if (_dragStartX is not { } start)
        {
            return;
        }

        _dragStartX = null;
        var x = args.GetCurrentPoint(PageScroller).Position.X;
        var travel = x - start;
        _pages.Follow(0);
        var step = DragTurn.ReadingStep(travel, _navigator.IsRightToLeft);
        if (step != 0)
        {
            Turn(step > 0 ? PageAction.Next : PageAction.Previous);
            return;
        }

        if (Math.Abs(travel) < 4)
        {
            // Held back for the double-click interval: a second click makes it a zoom instead.
            var action = EdgeClickZones.Resolve(x, PageScroller.ActualWidth, _navigator.IsRightToLeft, _host.Settings.Current.ClickZonesOn);
            _pendingClick = action == PageAction.None ? PageAction.ToggleChrome : action;
            _clickTimer.Stop();
            _clickTimer.Start();
        }
    }

    /// <summary>A plain wheel on a fitted page turns it, one notch one page; with Control held the ScrollViewer zooms instead.</summary>
    private void OnPageWheel(object sender, PointerRoutedEventArgs args)
    {
        var isControlHeld = args.KeyModifiers.HasFlag(VirtualKeyModifiers.Control);
        if (isControlHeld || _pages.IsZoomed)
        {
            return;
        }

        _wheel += args.GetCurrentPoint(PageScroller).Properties.MouseWheelDelta;
        args.Handled = true;
        if (Math.Abs(_wheel) >= WheelNotch)
        {
            Turn(_wheel < 0 ? PageAction.Next : PageAction.Previous);
            _wheel = 0;
        }
    }

    private void OnDoubleTapped(object sender, DoubleTappedRoutedEventArgs args)
    {
        _clickTimer.Stop();
        _pendingClick = PageAction.None;
        var target = PageZoom.DoubleClickTarget(PageScroller.ZoomFactor, PageZoom.Floor);
        _pages.ZoomTo(target, args.GetPosition(PageScroller));
        args.Handled = true;
    }

    private void OnPageAreaSizeChanged(object sender, SizeChangedEventArgs args)
    {
        _navigator.Resize(new Extent(args.NewSize.Width, args.NewSize.Height));
        _pages.Show();
    }

    private void OnViewChanged(object? sender, ScrollViewerViewChangedEventArgs args)
    {
        if (!args.IsIntermediate)
        {
            _pages.ZoomSettled();
        }
    }

    /// <summary>
    /// The page keys, before the ScrollViewer takes the arrows for scrolling: this handler is on the
    /// root's <c>PreviewKeyDown</c>. A zoomed page keeps its arrows for panning.
    /// </summary>
    private void OnKeyDown(object sender, KeyRoutedEventArgs args)
    {
        if (args.Key == VirtualKey.Escape && _fullScreen.Escape() == FullScreenChange.Left)
        {
            LeaveFullScreen();
            args.Handled = true;
            return;
        }

        // A key pressed in the menu or the title bar is theirs: arrows move through the menus there.
        if (args.OriginalSource is DependencyObject source && IsInChrome(source))
        {
            return;
        }

        var key = ReaderKeys.From(args.Key);
        if (key == ReaderKey.Other || (_pages.IsZoomed && key is ReaderKey.Left or ReaderKey.Right))
        {
            return;
        }

        var isShiftHeld = InputKeyboardSource.GetKeyStateForCurrentThread(VirtualKey.Shift).HasFlag(CoreVirtualKeyStates.Down);
        var action = PageKeyMapper.Map(key, new KeyContext(
            _navigator.IsRightToLeft,
            IsTextFieldFocused: false,
            _navigator.IsAtFirst,
            _navigator.IsAtLast,
            isShiftHeld));
        if (action is PageAction.None or PageAction.LeaveText)
        {
            return;
        }

        Turn(action);
        args.Handled = true;
    }

    private bool IsInChrome(DependencyObject element)
    {
        for (var current = element; current is not null; current = Microsoft.UI.Xaml.Media.VisualTreeHelper.GetParent(current))
        {
            if (current == Menu || current == AppTitleBar)
            {
                return true;
            }
        }

        // A menu's flyout lives in a popup outside the window's tree; its items are chrome too.
        return element is MenuFlyoutItemBase or MenuBarItem;
    }

    private void OnDragOver(object sender, DragEventArgs args) => Drops.Accept(args);

    private async void OnDrop(object sender, DragEventArgs args) =>
        _host.OpenPaths(await Drops.PathsAsync(args), OpenOrigin.Drop);

    private void OnAppWindowChanged(AppWindow sender, AppWindowChangedEventArgs args)
    {
        if (_fullScreen.IsFullScreen || !(args.DidPositionChange || args.DidSizeChange))
        {
            return;
        }

        _lastWindowed = Snapshot();
        _host.ReaderMoved(State());
    }

    private ReaderWindowState Snapshot() => new(
        PublicationId,
        WindowPlacement.FrameOf(AppWindow),
        WindowPlacement.IsMaximized(AppWindow),
        WindowPlacement.DisplayIdOf(AppWindow),
        _navigator.CurrentPage + 1);
}

/// <summary><c>Windows.System.VirtualKey</c> to the reader's platform-free key.</summary>
internal static class ReaderKeys
{
    public static ReaderKey From(VirtualKey key) => key switch
    {
        VirtualKey.Left => ReaderKey.Left,
        VirtualKey.Right => ReaderKey.Right,
        VirtualKey.PageUp => ReaderKey.PageUp,
        VirtualKey.PageDown => ReaderKey.PageDown,
        VirtualKey.Space => ReaderKey.Space,
        VirtualKey.Home => ReaderKey.Home,
        VirtualKey.End => ReaderKey.End,
        VirtualKey.Enter => ReaderKey.Enter,
        VirtualKey.Escape => ReaderKey.Escape,
        VirtualKey.Tab => ReaderKey.Tab,
        _ => ReaderKey.Other,
    };
}
