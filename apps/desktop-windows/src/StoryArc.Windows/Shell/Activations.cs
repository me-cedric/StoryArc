using Microsoft.Windows.AppLifecycle;
using StoryArc.Interop.Opening;
using Windows.ApplicationModel.Activation;

namespace StoryArc.Windows.Shell;

/// <summary>What an activation asks the app to open, and where the request came from.</summary>
internal sealed record LaunchRequest(IReadOnlyList<string> Paths, OpenOrigin Origin)
{
    public static LaunchRequest Nothing { get; } = new([], OpenOrigin.CommandLine);

    /// <summary>A file from Explorer or a path on the command line: the reader opens without the library in front of it.</summary>
    public bool OpensFiles => Paths.Count > 0;
}

/// <summary>
/// Reads an activation of <c>Microsoft.Windows.AppLifecycle.AppActivationArguments</c> (desktop-clients
/// task 2.42): <c>ExtendedActivationKind.File</c> carries <c>IFileActivatedEventArgs.Files</c>, the
/// files of a double click or Open With; <c>ExtendedActivationKind.Launch</c> carries
/// <c>ILaunchActivatedEventArgs.Arguments</c>, the paths of the execution alias, a redirected
/// command line or a Jump List item. The first process also has its own command line.
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

        if (activation?.Kind == ExtendedActivationKind.Launch && activation.Data is ILaunchActivatedEventArgs launch
            && LaunchArguments.PathsIn(launch.Arguments) is { Count: > 0 } launched)
        {
            return new LaunchRequest(launched, OpenOrigin.CommandLine);
        }

        return commandLine is null
            ? LaunchRequest.Nothing
            : new LaunchRequest(LaunchArguments.Paths(commandLine, skipExecutable: true), OpenOrigin.CommandLine);
    }
}
