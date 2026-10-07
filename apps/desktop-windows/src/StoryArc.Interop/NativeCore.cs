using System.Runtime.InteropServices;

namespace StoryArc.Interop;

/// <summary>Calls into the Rust core (<c>storyarc_ffi</c>). The header is <c>apps/desktop-core/storyarc-ffi/include/storyarc_ffi.h</c>.</summary>
public static partial class NativeCore
{
    private const string Library = "storyarc_ffi";

    [LibraryImport(Library, EntryPoint = "storyarc_core_version")]
    private static partial nint CoreVersion();

    /// <summary>The storyarc-core version, for example <c>0.1.0</c>. The native side owns the string.</summary>
    public static string Version() =>
        Marshal.PtrToStringUTF8(CoreVersion())
        ?? throw new InvalidOperationException("storyarc_core_version returned a null pointer.");
}
