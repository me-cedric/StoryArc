using Windows.Storage;

namespace StoryArc.Windows.Shell;

/// <summary>
/// The two small files the shell keeps: the session (which windows were open, where, on which
/// page) and the settings. Both live in <c>Windows.Storage.ApplicationData.Current.LocalFolder</c>,
/// the package's <c>%LOCALAPPDATA%</c> that MSIX redirects (design.md, Decision 8), never the
/// roaming folder. A read that fails is nothing to restore; a write that fails is logged by the
/// caller and never stops a window from closing.
/// </summary>
internal static class StateFiles
{
    public static string SessionPath => Path.Combine(ApplicationData.Current.LocalFolder.Path, "session.json");

    public static string SettingsPath => Path.Combine(ApplicationData.Current.LocalFolder.Path, "settings.json");

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
