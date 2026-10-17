using Windows.Storage;

namespace StoryArc.Windows.Shell;

/// <summary>
/// The files the shell keeps: the session (which windows were open, where, on which page), the
/// settings, the chosen folders, the recent list and the core's progress store. All of them live in
/// <c>Windows.Storage.ApplicationData.Current.LocalFolder</c>, the package's <c>%LOCALAPPDATA%</c> that MSIX redirects (design.md, Decision 8), never the
/// roaming folder. A read that fails is nothing to restore; a write that fails is logged by the
/// caller and never stops a window from closing.
/// </summary>
internal static class StateFiles
{
    public static string SessionPath => Path.Combine(ApplicationData.Current.LocalFolder.Path, "session.json");

    public static string SettingsPath => Path.Combine(ApplicationData.Current.LocalFolder.Path, "settings.json");

    /// <summary>The folders the reader chose (task 2.43).</summary>
    public static string SourcesPath => Path.Combine(ApplicationData.Current.LocalFolder.Path, "sources.json");

    /// <summary>The recent publications behind the Jump List (task 2.42).</summary>
    public static string RecentPath => Path.Combine(ApplicationData.Current.LocalFolder.Path, "recent.json");

    /// <summary>The core's progress store: one position per publication, in the phones' shape (task 2.44).</summary>
    public static string ProgressPath => Path.Combine(ApplicationData.Current.LocalFolder.Path, "progress.sqlite");

    public static string? Read(string path)
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

    public static bool Write(string path, string text)
    {
        try
        {
            File.WriteAllText(path, text);
            return true;
        }
        catch (Exception error) when (error is IOException or UnauthorizedAccessException)
        {
            return false;
        }
    }
}
