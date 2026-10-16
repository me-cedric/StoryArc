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
    }

    protected override void OnLaunched(LaunchActivatedEventArgs args)
    {
        _host = new AppHost(DispatcherQueue.GetForCurrentThread());
        _host.Start();
    }
}
