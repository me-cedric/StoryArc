using System.Runtime.InteropServices;
using System.Text;

namespace StoryArc.Interop;

/// <summary>
/// The integer status a seam call returns. The values mirror <c>StoryArcStatus</c> in
/// <c>storyarc-ffi</c>; keep both in step.
/// </summary>
public enum StoryArcStatus
{
    /// <summary>The call did what it was asked.</summary>
    Ok = 0,

    /// <summary>An argument was null, empty or out of range.</summary>
    InvalidArgument = 1,

    /// <summary>The cancel token names no operation the core is running.</summary>
    UnknownToken = 2,
}

/// <summary>
/// Hand-written wrappers over the Rust core (<c>storyarc_ffi</c>). The <c>DllImport</c> declarations
/// are generated into <c>NativeMethods</c> by csbindgen (design.md, Decision 5); the header is
/// <c>apps/desktop-core/storyarc-ffi/include/storyarc_ffi.h</c>.
///
/// The seam rules this file leans on: a buffer the core returns is freed by one
/// <c>storyarc_buffer_free</c> call; a failed call leaves a message for the calling thread that
/// <c>storyarc_last_error</c> hands back; cancellation is a token the C# side maps a
/// <see cref="CancellationToken"/> onto.
/// </summary>
public static unsafe class NativeCore
{
    /// <summary>The storyarc-core version, for example <c>0.1.0</c>. The native side owns the string.</summary>
    public static string Version()
    {
        byte* text = NativeMethods.storyarc_core_version();
        if (text is null)
        {
            throw new InvalidOperationException("storyarc_core_version returned a null pointer.");
        }

        return Marshal.PtrToStringUTF8((nint)text)
            ?? throw new InvalidOperationException("storyarc_core_version returned no text.");
    }

    /// <summary>
    /// The message of the last call that failed on the calling thread, or <c>null</c> when none has.
    /// The core hands the message over in a buffer it owns; this reads it and frees it in one go.
    /// </summary>
    public static string? LastError()
    {
        nuint length;
        byte* data = NativeMethods.storyarc_last_error(&length);
        if (data is null)
        {
            return null;
        }

        try
        {
            return Encoding.UTF8.GetString(data, checked((int)length));
        }
        finally
        {
            NativeMethods.storyarc_buffer_free(data, length);
        }
    }

    /// <summary>
    /// Asks the core to stop the operation that runs under <paramref name="token"/>.
    /// <see cref="StoryArcStatus.UnknownToken"/> when nothing runs under it; the operation itself
    /// reports the cancellation through its own return.
    /// </summary>
    public static StoryArcStatus Cancel(ulong token) =>
        (StoryArcStatus)NativeMethods.storyarc_cancel(token);
}
