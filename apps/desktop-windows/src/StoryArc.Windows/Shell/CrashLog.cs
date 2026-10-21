namespace StoryArc.Windows.Shell;

/// <summary>
/// Appends an unhandled exception to <c>crash.log</c> in <see cref="StateFiles.Root"/>. Local only: StoryArc sends nothing.
/// A log that cannot be written is skipped, because the app is already going down.
/// </summary>
internal static class CrashLog
{
    public static void Write(Exception? error)
    {
        try
        {
            File.AppendAllText(Path.Combine(StateFiles.Root, "crash.log"), $"{DateTimeOffset.Now:O}\n{error}\n\n");
        }
        catch (Exception logError) when (logError is IOException or UnauthorizedAccessException)
        {
            // Nothing left to do.
        }
    }
}
