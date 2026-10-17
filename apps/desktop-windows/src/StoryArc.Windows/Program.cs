using Microsoft.UI.Dispatching;
using Microsoft.UI.Xaml;
using Microsoft.Windows.AppLifecycle;
using StoryArc.Windows.Shell;

namespace StoryArc.Windows;

/// <summary>
/// The app's own entry point, so a second launch never starts a second copy (desktop-clients task
/// 2.42; desktop-experience "Double click while the app is running"). The XAML generated <c>Main</c>
/// is off (<c>DISABLE_XAML_GENERATED_MAIN</c> in the project). The first instance registers the key
/// <see cref="InstanceKey"/> with <c>Microsoft.Windows.AppLifecycle.AppInstance.FindOrRegisterForKey</c>;
/// a later launch, from Explorer, the command line or the Jump List, finds it, hands its activation
/// over with <c>RedirectActivationToAsync</c> and exits. The redirect is awaited on a worker thread
/// while this thread waits with <c>CoWaitForMultipleObjects</c>, as the Windows App SDK's single
/// instancing guide does, because blocking an STA thread outright can deadlock the COM call.
/// </summary>
public static class Program
{
    /// <summary>The single-instance key: one running StoryArc per user session.</summary>
    public const string InstanceKey = "StoryArc.Main";

    /// <summary>How this process was activated: a plain launch, a file from Explorer, or a Jump List item.</summary>
    internal static AppActivationArguments? FirstActivation { get; private set; }

    /// <summary>Raised on the app's thread when a later launch redirected its activation here.</summary>
    internal static event Action<AppActivationArguments>? Redirected;

    [STAThread]
    public static int Main(string[] args)
    {
        WinRT.ComWrappersSupport.InitializeComWrappers();
        var activation = AppInstance.GetCurrent().GetActivatedEventArgs();
        var main = AppInstance.FindOrRegisterForKey(InstanceKey);
        if (!main.IsCurrent)
        {
            Redirect(main, activation);
            return 0;
        }

        FirstActivation = activation;
        Application.Start(_ =>
        {
            var dispatcher = DispatcherQueue.GetForCurrentThread();
            SynchronizationContext.SetSynchronizationContext(new DispatcherQueueSynchronizationContext(dispatcher));
            main.Activated += (_, redirected) => dispatcher.TryEnqueue(() => Redirected?.Invoke(redirected));
            _ = new App();
        });
        return 0;
    }

    private static void Redirect(AppInstance target, AppActivationArguments activation)
    {
        using var done = new ManualResetEvent(initialState: false);
        _ = Task.Run(async () =>
        {
            try
            {
                await target.RedirectActivationToAsync(activation);
            }
            finally
            {
                done.Set();
            }
        });

        Win32.WaitPumping(done);
    }
}
