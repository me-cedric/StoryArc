using Microsoft.UI.Dispatching;
using Microsoft.UI.Xaml;
using StoryArc.Windows.Shell;

namespace StoryArc.Windows;

public partial class App : Application
{
    // Held for the life of the app: the windows, the session and the settings are its.
    private AppHost? _host;

    public App()
    {
        InitializeComponent();
        // A crash leaves its exception in crash.log in the data folder: never sent anywhere, read by the
        // reader or by the release lane's start-up check. XAML otherwise reports only 0xC000027B.
        UnhandledException += (_, e) => CrashLog.Write(e.Exception);
        AppDomain.CurrentDomain.UnhandledException += (_, e) => CrashLog.Write(e.ExceptionObject as Exception);
    }

    /// <summary>
    /// Starts the host with what this process was launched for (<see cref="Program.FirstActivation"/>):
    /// a file from Explorer or the command line opens its reader without bringing the library in
    /// front of it. A launch that a later process redirects here arrives through <see cref="Program.Redirected"/>.
    /// </summary>
    protected override void OnLaunched(LaunchActivatedEventArgs args)
    {
        var host = new AppHost(DispatcherQueue.GetForCurrentThread());
        _host = host;
        host.Start(Activations.Read(Program.FirstActivation, Environment.GetCommandLineArgs()));
        Program.Redirected += redirected => host.Activate(Activations.Read(redirected, commandLine: null));
    }
}
