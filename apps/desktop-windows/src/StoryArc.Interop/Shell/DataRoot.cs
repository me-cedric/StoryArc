namespace StoryArc.Interop.Shell;

/// <summary>
/// The folder that holds the shell's files, for each way the app is installed (shared-release-train, design D5). The
/// MSIX keeps the package's own folder. The installer's copy has no package and uses <c>%LOCALAPPDATA%\StoryArc</c>.
/// The portable copy has a file named <see cref="PortableMarker"/> beside the executable and keeps everything in a
/// <c>data</c> folder there, so nothing lands in the user profile. Pure, so the interop tests reach it.
/// </summary>
public static class DataRoot
{
    /// <summary>The file beside the executable that makes a copy portable.</summary>
    public const string PortableMarker = "portable";

    /// <param name="packageFolder">The package's local folder, or <c>null</c> when the app has no package.</param>
    /// <param name="exeFolder">The folder of the executable.</param>
    /// <param name="localAppData">The user's <c>%LOCALAPPDATA%</c>.</param>
    /// <param name="fileExists">Whether a file exists.</param>
    public static string Resolve(string? packageFolder, string exeFolder, string localAppData, Func<string, bool> fileExists) =>
        packageFolder
        ?? (fileExists(Path.Combine(exeFolder, PortableMarker))
            ? Path.Combine(exeFolder, "data")
            : Path.Combine(localAppData, "StoryArc"));
}
