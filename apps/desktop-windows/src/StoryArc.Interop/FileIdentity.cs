using System.Text.Json;

namespace StoryArc.Interop;

/// <summary>
/// The identity a file's progress is filed under (ADR-0006): the content digest the library's records carry and the
/// normalised path, from <c>storyarc_file_identity</c>. An EPUB, a PDF or an audiobook file uses it, as a comic does,
/// so a moved or renamed file keeps its place.
/// </summary>
public static unsafe class FileIdentity
{
    /// <summary>The identity of the file at <paramref name="path"/>; a missing file throws with <see cref="StoryArcStatus.NotFound"/>.</summary>
    public static CoreIdentity Of(string path)
    {
        ArgumentException.ThrowIfNullOrEmpty(path);
        var bytes = NativeCore.Utf8(path);
        StoryArcBuffer buffer = default;
        fixed (byte* data = bytes)
        {
            NativeCore.Check(NativeMethods.storyarc_file_identity(data, (nuint)bytes.Length, &buffer), "storyarc_file_identity");
        }

        return JsonSerializer.Deserialize(NativeCore.TakeString(buffer), CoreJsonContext.Default.CoreIdentity)
            ?? throw new StoryArcException("storyarc_file_identity", StoryArcStatus.Internal, "the core wrote no identity");
    }
}
