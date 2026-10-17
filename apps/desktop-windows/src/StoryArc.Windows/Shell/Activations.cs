using Microsoft.Windows.AppLifecycle;
using StoryArc.Interop.Opening;
using Windows.ApplicationModel.Activation;

namespace StoryArc.Windows.Shell;

/// <summary>What an activation asks the app to open, and where the request came from.</summary>
internal sealed record LaunchRequest(IReadOnlyList<string> Paths, OpenOrigin Origin)
{
    public static LaunchRequest Nothing { get; } = new([], OpenOrigin.CommandLine);

    /// <summary>The <c>storyarc://</c> links the launch carries (task 5.8): names to open, never paths.</summary>
    public IReadOnlyList<string> Links { get; init; } = [];

    /// <summary>A file from Explorer or a path on the command line: the reader opens without the library in front of it.</summary>
    public bool OpensFiles => Paths.Count > 0;
}

/// <summary>
/// Reads an activation of <c>Microsoft.Windows.AppLifecycle.AppActivationArguments</c> (desktop-clients
/// task 2.42): <c>ExtendedActivationKind.File</c> carries <c>IFileActivatedEventArgs.Files</c>, the
/// files of a double click or Open With; <c>ExtendedActivationKind.Launch</c> carries
/// <c>ILaunchActivatedEventArgs.Arguments</c>, the paths of the execution alias, a redirected
/// command line or a Jump List item; <c>ExtendedActivationKind.Protocol</c> carries
/// <c>IProtocolActivatedEventArgs.Uri</c>, a <c>storyarc://</c> link (task 5.8). The first process
/// also has its own command line.
/// </summary>
internal static class Activations
{
    public static LaunchRequest Read(AppActivationArguments? activation, string[]? commandLine)
    {
        if (activation?.Kind == ExtendedActivationKind.File && activation.Data is IFileActivatedEventArgs files)
        {
            var paths = files.Files.Select(item => item.Path).Where(path => !string.IsNullOrEmpty(path)).ToList();
            return new LaunchRequest(paths, OpenOrigin.FileActivation);
        }

        if (activation?.Kind == ExtendedActivationKind.Protocol && activation.Data is IProtocolActivatedEventArgs protocol)
        {
            return new LaunchRequest([], OpenOrigin.CommandLine) { Links = [protocol.Uri.AbsoluteUri] };
        }

        if (activation?.Kind == ExtendedActivationKind.Launch && activation.Data is ILaunchActivatedEventArgs launch)
        {
            var launchedPaths = LaunchArguments.PathsIn(launch.Arguments);
            var launchedLinks = LaunchArguments.LinksIn(launch.Arguments);
            if (launchedPaths.Count > 0 || launchedLinks.Count > 0)
            {
                return new LaunchRequest(launchedPaths, OpenOrigin.CommandLine) { Links = launchedLinks };
            }
        }

        return commandLine is null
            ? LaunchRequest.Nothing
            : new LaunchRequest(LaunchArguments.Paths(commandLine, skipExecutable: true), OpenOrigin.CommandLine)
            {
                Links = LaunchArguments.Links(commandLine, skipExecutable: true),
            };
    }
}
