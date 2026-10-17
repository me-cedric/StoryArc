using System.Runtime.InteropServices.WindowsRuntime;
using Microsoft.UI.Windowing;
using Microsoft.UI.Xaml;
using Microsoft.UI.Xaml.Automation.Peers;
using Microsoft.Web.WebView2.Core;
using StoryArc.Interop.Epub;
using StoryArc.Interop.Opening;
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
    private CoreWebView2Environment? _environment;
    private ReaderWindowState _lastWindowed;
    private int _position;
    private long _lastLocatorSeq = -1;

    internal EpubReaderWindow(AppHost host, OpenedEpub opened, ReaderWindowState? restored, int startPage)
    {
        _host = host;
        _opened = opened;
        _startPage = startPage;
        _position = startPage + 1;
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
                Post(_commands.Next());
                break;
            case "previousPage":
                Post(_commands.Previous());
                break;
            case "firstPage":
                GoTo(0);
                break;
            case "lastPage":
                GoTo(_opened.PositionCount - 1);
                break;
        }
    }

    private async Task StartAsync()
    {
        try
        {
            var options = new CoreWebView2EnvironmentOptions();
            options.CustomSchemeRegistrations.Add(new CoreWebView2CustomSchemeRegistration(EpubHost.Scheme)
            {
                TreatAsSecure = true,
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

        core.AddWebResourceRequestedFilter("*", CoreWebView2WebResourceContext.All);
        core.WebResourceRequested += OnWebResourceRequested;
        core.NavigationStarting += (sender, args) => args.Cancel = !_opened.Host.AllowsNavigation(args.Uri, isFrame: false);
        core.FrameNavigationStarting += (sender, args) => args.Cancel = !_opened.Host.AllowsNavigation(args.Uri, isFrame: true);
        core.NewWindowRequested += (sender, args) => args.Handled = true;
        core.WebMessageReceived += OnWebMessage;

        if (EpubProgress.LocatorAt(_opened.PositionsJson, _startPage) is { } locator)
        {
            _ = await core.AddScriptToExecuteOnDocumentCreatedAsync("window.__storyarcLocator = " + locator + ";");
        }

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
            case "locator" when message.Seq > _lastLocatorSeq && message.Position() is { } at:
                _lastLocatorSeq = message.Seq;
                _position = Math.Clamp(at.Position, 1, _opened.PositionCount);
                ShowPosition();
                _host.PageTurned(PublicationId, EpubProgress.PageIndex(_position, _opened.PositionCount));
                _host.ReaderMoved(State());
                break;
            case "link" when message.OutboundLink() is { } outbound:
                // A link out of the publication opens in the system browser, never inside the web view (ebook-reader, "Following a link out of the publication").
                _ = Launcher.LaunchUriAsync(outbound);
                break;
            case "host-error":
                ShowUnavailable(Strings.Get("reader_pageUnavailable", "This page could not be read"));
                break;
        }
    }

    private void GoTo(int pageIndex)
    {
        if (EpubProgress.LocatorAt(_opened.PositionsJson, pageIndex) is { } locator)
        {
            Post(_commands.Go(locator));
        }
    }

    private void Post(string json) => Web.CoreWebView2?.PostWebMessageAsJson(json);

    private void ShowPosition()
    {
        PositionLabel.Text = EpubProgress.Label(Strings.Get("reader_pageLabel__lld__lld", "Page {0} of {1}"), _position, _opened.PositionCount);
        FrameworkElementAutomationPeer.FromElement(PositionLabel)?.RaiseAutomationEvent(AutomationEvents.LiveRegionChanged);
    }

    internal void ShowUnavailable(string sentence)
    {
        UnavailableText.Text = sentence;
        UnavailableText.Visibility = Visibility.Visible;
    }

    private bool IsAvailable(string commandId) =>
        commandId != "fullScreen" && commandId is not ("zoomIn" or "zoomOut" or "fitPage" or "singlePage" or "twoPages")
        && CommandRouting.IsHandled(commandId, WindowKind.Reader);

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
