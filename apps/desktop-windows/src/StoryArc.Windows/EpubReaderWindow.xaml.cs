using System.Globalization;
using System.Runtime.InteropServices.WindowsRuntime;
using Microsoft.UI.Windowing;
using Microsoft.UI.Xaml;
using Microsoft.UI.Xaml.Controls;
using Microsoft.UI.Xaml.Automation.Peers;
using Microsoft.Web.WebView2.Core;
using StoryArc.Interop.Epub;
using StoryArc.Interop.Opening;
using StoryArc.Interop.Playback;
using StoryArc.Interop.Shell;
using StoryArc.Windows.Shell;
using Windows.System;

namespace StoryArc.Windows;

/// <summary>
/// The reader window of one EPUB (desktop-clients task 4.16; design.md Decision 6). The renderer runs
/// in a <c>WebView2</c> on an environment of its own that registers the app's scheme
/// (<c>CoreWebView2CustomSchemeRegistration</c>, an authority, treated as secure), every request goes
/// through <c>WebResourceRequested</c> behind a <c>*</c> filter to <see cref="EpubHost.Answer"/>,
/// <c>NavigationStarting</c> and <c>FrameNavigationStarting</c> apply <see cref="EpubHost.AllowsNavigation"/>,
/// a new window is never opened, and the renderer's <c>locator</c> messages feed the progress cadence.
/// </summary>
public sealed partial class EpubReaderWindow : Window, IPublicationWindow
{
    private readonly AppHost _host;
    private readonly OpenedEpub _opened;
    private readonly HostCommands _commands = new();
    private readonly int _startPage;
    private readonly EpubJumps _jumps = new();
    private readonly EpubMarks _marks;
    private CoreWebView2Environment? _environment;
    private ReaderWindowState _lastWindowed;
    private EpubLook _look;
    private int _position;
    private long _lastLocatorSeq = -1;
    private string? _spoken;

    internal EpubReaderWindow(AppHost host, OpenedEpub opened, ReaderWindowState? restored, int startPage)
    {
        _host = host;
        _opened = opened;
        _startPage = startPage;
        _position = startPage + 1;
        _look = EpubLook.Restore(ReadText(StateFiles.EpubLookPath));
        var marksPath = Path.Combine(StateFiles.EpubMarksFolder, (opened.Identity.ContentDigest ?? EpubHost.IdFor(opened.Id)) + ".json");
        _marks = new EpubMarks(() => ReadText(marksPath), text => WriteText(marksPath, text), OrderOf);
        InitializeComponent();

        Title = opened.Title;
        AppTitleBar.Title = opened.Title;
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
        AppWindow.Changed += OnAppWindowChanged;
        Root.ActualThemeChanged += (sender, args) =>
        {
            // The reader linked the reading theme to the app's appearance: the page switches then and there.
            if (_look.FollowsAppearance)
            {
                ApplyTheme();
            }
        };
        LabelTools();
        Closed += (sender, args) =>
        {
            Web.Close();
            _opened.Dispose();
        };

        ShowPosition();
        _ = StartAsync();
    }

    public string PublicationId => _opened.Id;

    /// <summary>What the session file keeps for this window: its last windowed frame and its position, counted from one.</summary>
    public ReaderWindowState State() => _lastWindowed with { Page = _position };

    /// <summary>The reader's commands from the menu or a shortcut: a turn is a message to the renderer.</summary>
    public void Run(string commandId)
    {
        switch (commandId)
        {
            case "nextPage":
                _jumps.Turning();
                Post(_commands.Next());
                break;
            case "previousPage":
                _jumps.Turning();
                Post(_commands.Previous());
                break;
            case "firstPage":
                GoTo(0);
                break;
            case "lastPage":
                GoTo(_opened.PositionCount - 1);
                break;
            case "readAloud":
                StartReadAloud();
                break;
            case "showContents":
                ContentsFlyout.ShowAt(ContentsButton);
                break;
            case "find":
                SearchFlyout.ShowAt(SearchButton);
                break;
            case "bookmarkPage":
                ToggleBookmark();
                break;
            case "appearance":
                ThemeFlyout.ShowAt(ThemeButton);
                break;
            case "zoomIn":
                ChangeTypography(values => values with { FontSize = ReadingThemes.LargerSize(values.FontSize) });
                break;
            case "zoomOut":
                ChangeTypography(values => values with { FontSize = ReadingThemes.SmallerSize(values.FontSize) });
                break;
        }
    }

    /// <summary>
    /// Read aloud from the chapter being shown (task 4.20; ebook-reader "Reading aloud"): the voice takes the one player,
    /// the page follows it chapter by chapter through a <c>go</c>, and the control is absent without a voice.
    /// </summary>
    private void StartReadAloud()
    {
        if (_host.Playback is not { } playback || !PlaybackService.HasVoice)
        {
            return;
        }

        var queue = new ReadAloudModel(1, _opened.ReadingOrder.Count, _opened.SentencesOf);
        var chapter = ChapterOfPosition();
        playback.ReadAloud(PublicationId, _opened.Title, _opened.Author, queue, chapter, _opened.Chapters(), sentence =>
        {
            // The sentence being spoken is drawn as one more decoration, and the page follows it to the column that holds
            // it; no way back is kept, because the reader did not jump. The end of the voice withdraws the highlight.
            _spoken = sentence is not null && sentence.ChapterIndex < _opened.ReadingOrder.Count
                ? EpubMarks.SpokenLocator(sentence.Text, _opened.ReadingOrder[sentence.ChapterIndex].Href)
                : null;
            SyncHighlights();
            if (_spoken is not null)
            {
                _jumps.Turning();
                Post(_commands.Go(_spoken));
            }
        });
    }

    /// <summary>The reading-order index of the position being shown, from the positions list's href.</summary>
    private int ChapterOfPosition()
    {
        if (EpubProgress.LocatorAt(_opened.PositionsJson, _position - 1) is { } locator
            && System.Text.Json.Nodes.JsonNode.Parse(locator) is System.Text.Json.Nodes.JsonObject node
            && node["href"]?.GetValue<string>() is { } href)
        {
            var index = _opened.ReadingOrder.ToList().FindIndex(entry => entry.Href == href);
            return index < 0 ? 0 : index;
        }

        return 0;
    }

    private async Task StartAsync()
    {
        try
        {
            var options = new CoreWebView2EnvironmentOptions();
            options.CustomSchemeRegistrations.Add(new CoreWebView2CustomSchemeRegistration(EpubHost.Scheme)
            {
                // The WinRT projection types this flag as an integer; CI's compiler refused `true`.
                TreatAsSecure = 1,
                HasAuthorityComponent = true,
            });
            _environment = await CoreWebView2Environment.CreateWithOptionsAsync(string.Empty, StateFiles.WebViewDataFolder, options);
            await Web.EnsureCoreWebView2Async(_environment);
        }
        catch (Exception error) when (error is InvalidOperationException or System.Runtime.InteropServices.COMException or FileNotFoundException)
        {
            // No WebView2 runtime on this machine: the book cannot be shown, and the reason is said in grey, never as an alarm.
            ShowUnavailable(Strings.Get("desktop_w4_epub_noWebView", "This book needs the WebView2 runtime, which this PC does not have"));
            return;
        }

        var core = Web.CoreWebView2;
        core.Settings.IsWebMessageEnabled = true;
        core.Settings.AreHostObjectsAllowed = false;
        core.Settings.AreDevToolsEnabled = false;
        core.Settings.AreDefaultScriptDialogsEnabled = false;
        core.Settings.IsStatusBarEnabled = false;
        core.Settings.IsGeneralAutofillEnabled = false;
        core.Settings.IsPasswordAutosaveEnabled = false;
        core.Settings.AreBrowserAcceleratorKeysEnabled = false;
        core.Settings.IsBuiltInErrorPageEnabled = false;

        core.AddWebResourceRequestedFilter("*", CoreWebView2WebResourceContext.All, CoreWebView2WebResourceRequestSourceKinds.All);
        core.WebResourceRequested += OnWebResourceRequested;
        core.NavigationStarting += (sender, args) => args.Cancel = !_opened.Host.AllowsNavigation(args.Uri, isFrame: false);
        core.FrameNavigationStarting += (sender, args) => args.Cancel = !_opened.Host.AllowsNavigation(args.Uri, isFrame: true);
        core.NewWindowRequested += (sender, args) => args.Handled = true;
        core.WebMessageReceived += OnWebMessage;

        if (EpubProgress.LocatorAt(_opened.PositionsJson, _startPage) is { } locator)
        {
            _ = await core.AddScriptToExecuteOnDocumentCreatedAsync("window.__storyarcLocator = " + locator + ";");
        }

        _ = await core.AddScriptToExecuteOnDocumentCreatedAsync("window.__storyarcPreferences = " + CurrentAxes().ToJsonString() + ";");

        core.Navigate(_opened.Host.ReaderPageUrl);
    }

    /// <summary>
    /// Every request of the web view. The answer is built on a worker, because a chapter read through the
    /// core should not hold the interface thread, and handed back through the event's deferral.
    /// </summary>
    private async void OnWebResourceRequested(CoreWebView2 sender, CoreWebView2WebResourceRequestedEventArgs args)
    {
        var deferral = args.GetDeferral();
        try
        {
            var uri = args.Request.Uri;
            var context = ContextOf(args.ResourceContext);
            var range = args.Request.Headers.Contains("Range") ? args.Request.Headers.GetHeader("Range") : null;
            var answer = await Task.Run(() => _opened.Host.Answer(uri, context, range));
            args.Response = _environment!.CreateWebResourceResponse(
                new MemoryStream(answer.Body.ToArray()).AsRandomAccessStream(),
                answer.Status,
                answer.Reason,
                answer.HeaderBlock);
        }
        catch (ObjectDisposedException)
        {
            // The window closed while a chapter was being read.
        }
        finally
        {
            deferral.Complete();
        }
    }

    private static EpubRequestContext ContextOf(CoreWebView2WebResourceContext context) => context switch
    {
        CoreWebView2WebResourceContext.Document => EpubRequestContext.Document,
        CoreWebView2WebResourceContext.Image => EpubRequestContext.Image,
        CoreWebView2WebResourceContext.Stylesheet => EpubRequestContext.Stylesheet,
        CoreWebView2WebResourceContext.Script => EpubRequestContext.Script,
        CoreWebView2WebResourceContext.Font => EpubRequestContext.Font,
        CoreWebView2WebResourceContext.Media => EpubRequestContext.Media,
        CoreWebView2WebResourceContext.Fetch => EpubRequestContext.Fetch,
        CoreWebView2WebResourceContext.XmlHttpRequest => EpubRequestContext.XmlHttpRequest,
        CoreWebView2WebResourceContext.Ping => EpubRequestContext.Ping,
        CoreWebView2WebResourceContext.Websocket => EpubRequestContext.WebSocket,
        _ => EpubRequestContext.Other,
    };

    private void OnWebMessage(CoreWebView2 sender, CoreWebView2WebMessageReceivedEventArgs args)
    {
        if (RendererMessage.TryParse(args.WebMessageAsJson) is not { } message)
        {
            return;
        }

        switch (message.Type)
        {
            case "ready":
                SyncHighlights();
                break;
            case "locator" when message.Seq > _lastLocatorSeq && message.Position() is { } at:
                _lastLocatorSeq = message.Seq;
                _position = Math.Clamp(at.Position, 1, _opened.PositionCount);
                if (message.LocatorJson() is { } moved)
                {
                    _jumps.Moved(moved);
                }

                ShowPosition();
                _host.PageTurned(PublicationId, EpubProgress.PageIndex(_position, _opened.PositionCount));
                _host.ReaderMoved(State());
                break;
            case "link" when message.OutboundLink() is { } outbound:
                // A link out of the publication opens in the system browser, never inside the web view, and only once the reader confirmed its host (ebook-reader, "Following a link out of the publication").
                _ = ConfirmLeavingAsync(outbound);
                break;
            case "selection":
                ShowSelection(message.Selection());
                break;
            case "footnote" when message.Footnote() is { } note:
                ShowFootnote(note);
                break;
            case "highlight-activated" when message.ActivatedId() is { } id && _marks.Highlight(id) is { } highlight:
                _ = EditHighlightAsync(highlight);
                break;
            case "search-results":
                ReceiveSearch(message);
                break;
            case "host-error":
                ShowUnavailable(Strings.Get("reader_pageUnavailable", "This page could not be read"));
                break;
        }
    }

    private async Task ConfirmLeavingAsync(Uri outbound)
    {
        var dialog = new ContentDialog
        {
            XamlRoot = Content.XamlRoot,
            Title = string.Format(CultureInfo.CurrentCulture, Strings.Get("desktop_w4_epub_leave_title___", "Open a page on {0}?"), outbound.Host),
            Content = outbound.AbsoluteUri,
            PrimaryButtonText = Strings.Get("desktop_w4_epub_leave_open", "Open in Browser"),
            CloseButtonText = Strings.Get("desktop_w4_epub_leave_stay", "Stay in the Book"),
            DefaultButton = ContentDialogButton.Close,
        };
        if (await dialog.ShowAsync() == ContentDialogResult.Primary)
        {
            _ = Launcher.LaunchUriAsync(outbound);
        }
    }

    private void GoTo(int pageIndex)
    {
        if (EpubProgress.LocatorAt(_opened.PositionsJson, pageIndex) is { } locator)
        {
            Jump(locator);
        }
    }

    /// <summary>A move the reader asked for that leaves where they were: the place left becomes the way back.</summary>
    private void Jump(string locator)
    {
        _jumps.Jumping();
        Post(_commands.Go(locator));
        ShowBack();
    }

    private void OnBack(object sender, RoutedEventArgs args)
    {
        if (_jumps.Back() is { } back)
        {
            Post(_commands.Go(back));
        }

        ShowBack();
    }

    private void ShowBack() => BackButton.Visibility = _jumps.Return is null ? Visibility.Collapsed : Visibility.Visible;

    private void SyncHighlights() => Post(_commands.Highlights(_marks.HighlightItems(_spoken)));

    private void Post(string json) => Web.CoreWebView2?.PostWebMessageAsJson(json);

    /// <summary>
    /// The one progress line (ebook-reader, "Progress display"): how far through the book and how much of the chapter is left,
    /// in words, never a page number; the book alone when it declares no chapters. Also the bookmark of this page and the way back.
    /// </summary>
    private void ShowPosition()
    {
        var place = EpubPlace.Of(_jumps.Current);
        var total = _jumps.Current is null ? (_position - 1) / (double)Math.Max(1, _opened.PositionCount) : place.TotalProgression;
        PositionLabel.Text = EpubProgressLine.Text(
            Strings.Get("desktop_w4_epub_progress__lld__lld", "{0}% read · {1}% of this chapter left"),
            Strings.Get("epub_progress__lld", "{0}% read"),
            total,
            place.Progression,
            _opened.Contents.Count > 0 && _jumps.Current is not null);
        FrameworkElementAutomationPeer.FromElement(PositionLabel)?.RaiseAutomationEvent(AutomationEvents.LiveRegionChanged);
        ShowBookmark();
        ShowBack();
    }

    internal void ShowUnavailable(string sentence)
    {
        UnavailableText.Text = sentence;
        UnavailableText.Visibility = Visibility.Visible;
    }

    /// <summary>
    /// The page commands, the reading tools (contents, search, the bookmark, themes, larger and smaller text), and Read Aloud where
    /// the system has a voice and the app a player; never page zoom or spreads, which a reflowable book has not.
    /// </summary>
    private bool IsAvailable(string commandId) => commandId switch
    {
        "readAloud" => _host.Playback is not null && PlaybackService.HasVoice,
        "showContents" or "find" or "bookmarkPage" or "appearance" or "zoomIn" or "zoomOut" => true,
        "fullScreen" or "fitPage" or "singlePage" or "twoPages" => false,
        _ => CommandRouting.IsHandled(commandId, WindowKind.Reader),
    };

    /// <summary>The reading-order index of a resource, so the marks list in reading order.</summary>
    private int OrderOf(string href)
    {
        var index = _opened.ReadingOrder.ToList().FindIndex(entry => entry.Href.Split('#')[0] == href);
        return index < 0 ? int.MaxValue : index;
    }

    private static string? ReadText(string path)
    {
        try
        {
            return File.Exists(path) ? File.ReadAllText(path) : null;
        }
        catch (Exception error) when (error is IOException or UnauthorizedAccessException)
        {
            return null;
        }
    }

    /// <summary>Writes a state file; a failure is thrown as <see cref="IOException"/> for the store that asked to keep its change for the session.</summary>
    private static void WriteText(string path, string text)
    {
        Directory.CreateDirectory(Path.GetDirectoryName(path)!);
        File.WriteAllText(path, text);
    }

    private void Invoke(string commandId) => _host.Invoke(commandId, this);

    private void OnDragOver(object sender, DragEventArgs args) => Drops.Accept(args);

    private async void OnDrop(object sender, DragEventArgs args) =>
        _host.OpenPaths(await Drops.PathsAsync(args), OpenOrigin.Drop);

    private void OnAppWindowChanged(AppWindow sender, AppWindowChangedEventArgs args)
    {
        if (!(args.DidPositionChange || args.DidSizeChange))
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
        _position);
}
