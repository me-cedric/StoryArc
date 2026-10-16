using System.Runtime.InteropServices;

namespace StoryArc.Interop;

/// <summary>
/// The integer status a seam call returns. The values mirror the <c>STORYARC_*</c> codes in
/// <c>apps/desktop-core/storyarc-ffi/include/storyarc_ffi.h</c>; keep both in step.
/// </summary>
public enum StoryArcStatus
{
    /// <summary>The call did what it was asked.</summary>
    Ok = 0,

    /// <summary>An argument was null, empty or out of range.</summary>
    InvalidArgument = 1,

    /// <summary>The operation stopped because its cancel token was raised.</summary>
    Cancelled = 2,
}

/// <summary>
/// Hand-written wrappers over the Rust core (<c>storyarc_ffi</c>). The <c>DllImport</c> declarations
/// and the <c>StoryArcBuffer</c> struct are generated into <c>NativeMethods</c> by csbindgen
/// (design.md, Decision 5); the header is <c>apps/desktop-core/storyarc-ffi/include/storyarc_ffi.h</c>.
///
/// The seam rules this file leans on: a buffer the core returns is freed exactly once by
/// <c>storyarc_buffer_free</c>; a failed call leaves a message for the calling thread that
/// <c>storyarc_last_error</c> hands back and the caller never frees; a cancel token is an opaque
/// handle, wrapped in <see cref="CancelToken"/>.
/// </summary>
public static unsafe class NativeCore
{
    /// <summary>The storyarc-core version, for example <c>0.1.0</c>. The native side owns the string.</summary>
    public static string Version() =>
        ReadStatic(NativeMethods.storyarc_core_version())
        ?? throw new InvalidOperationException("storyarc_core_version returned a null pointer.");

    /// <summary>
    /// The message of the most recent call that failed on the calling thread, or <c>null</c> when
    /// none has. The core owns the text; it stays valid until the next failing call on this thread.
    /// </summary>
    public static string? LastError() => ReadStatic(NativeMethods.storyarc_last_error());

    /// <summary>
    /// Sends <paramref name="bytes"/> through the core and back: the core copies them into a buffer it
    /// owns, this copies them out and frees that buffer. The seam's byte-buffer rule, end to end.
    /// </summary>
    public static byte[] RoundTrip(ReadOnlySpan<byte> bytes)
    {
        StoryArcBuffer buffer = default;
        StoryArcStatus status;
        fixed (byte* data = bytes)
        {
            status = (StoryArcStatus)NativeMethods.storyarc_buffer_roundtrip(data, (nuint)bytes.Length, &buffer);
        }

        if (status != StoryArcStatus.Ok)
        {
            throw new InvalidOperationException($"storyarc_buffer_roundtrip failed with {status}: {LastError()}");
        }

        try
        {
            return new ReadOnlySpan<byte>(buffer.data, checked((int)buffer.len)).ToArray();
        }
        finally
        {
            NativeMethods.storyarc_buffer_free(buffer);
        }
    }

    private static string? ReadStatic(byte* text) =>
        text is null ? null : Marshal.PtrToStringUTF8((nint)text);
}

/// <summary>
/// A cancel token of the core: raise it to ask the operation running under it to stop. Owns the
/// native token and frees it on dispose; the core ignores a cancel or a free of a null token, and
/// raising a token twice is harmless.
/// </summary>
public sealed unsafe class CancelToken : SafeHandle
{
    public CancelToken()
        : base(IntPtr.Zero, ownsHandle: true)
    {
        SetHandle((nint)NativeMethods.storyarc_cancel_token_new());
        if (IsInvalid)
        {
            throw new InvalidOperationException("storyarc_cancel_token_new returned a null pointer.");
        }
    }

    public override bool IsInvalid => handle == IntPtr.Zero;

    /// <summary>Whether the token has been raised.</summary>
    public bool IsCancelled => NativeMethods.storyarc_cancel_token_is_cancelled((void*)handle) == 1;

    /// <summary>Raises the token. Calling it again changes nothing.</summary>
    public void Cancel() => NativeMethods.storyarc_cancel((void*)handle);

    protected override bool ReleaseHandle()
    {
        NativeMethods.storyarc_cancel_token_free((void*)handle);
        return true;
    }
}
