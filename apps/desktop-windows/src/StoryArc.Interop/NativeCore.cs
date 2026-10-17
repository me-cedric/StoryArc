using System.Runtime.InteropServices;
using System.Text;

namespace StoryArc.Interop;

/// <summary>
/// The integer status a seam call returns. The values mirror the <c>STORYARC_*</c> codes in
/// <c>apps/desktop-core/storyarc-ffi/include/storyarc_ffi.h</c>; the tests hold them to the generated constants.
/// </summary>
public enum StoryArcStatus
{
    /// <summary>The call did what it was asked.</summary>
    Ok = 0,

    /// <summary>A pointer, length, handle or index the call cannot work with. The message names which.</summary>
    InvalidArgument = 1,

    /// <summary>The operation stopped because its cancel token was raised.</summary>
    Cancelled = 2,

    /// <summary>Nothing at the path the call was given.</summary>
    NotFound = 3,

    /// <summary>A format or codec this build refuses, CB7 among them. The message names it, for the reader.</summary>
    Unsupported = 4,

    /// <summary>A publication or page in a supported format that is damaged, locked or too large.</summary>
    Unreadable = 5,

    /// <summary>The local store refused, or the disk is full.</summary>
    Storage = 6,

    /// <summary>The core failed in a way it has no case for: a defect, reported rather than a crash.</summary>
    Internal = 7,

    /// <summary>The source, server or sync place did not answer. Grey, never red: the app tries again later.</summary>
    Unreachable = 8,

    /// <summary>
    /// A credential, key or passphrase was refused, or a certificate is not trusted. The message names the
    /// challenge, or the certificate's fingerprint for <c>storyarc_http_pin</c>.
    /// </summary>
    Unauthorized = 9,
}

/// <summary>
/// A seam call that did not return <see cref="StoryArcStatus.Ok"/>: its status, and the message the
/// core left for this thread, which names the file, the format or the codec for the reader.
/// </summary>
public sealed class StoryArcException : Exception
{
    public StoryArcException(string call, StoryArcStatus status, string? coreMessage)
        : base($"{call} failed with {status}: {coreMessage ?? "no message"}")
    {
        Call = call;
        Status = status;
        CoreMessage = coreMessage;
    }

    /// <summary>The export that failed, for example <c>storyarc_publication_open</c>.</summary>
    public string Call { get; }

    public StoryArcStatus Status { get; }

    /// <summary>The core's own sentence, or <c>null</c> when it left none.</summary>
    public string? CoreMessage { get; }
}

/// <summary>
/// Hand-written wrappers over the Rust core (<c>storyarc_ffi</c>). The <c>DllImport</c> declarations
/// and the <c>StoryArcBuffer</c> struct are generated into <c>NativeMethods</c> by csbindgen
/// (design.md, Decision 5); the header is <c>apps/desktop-core/storyarc-ffi/include/storyarc_ffi.h</c>.
///
/// The seam rules this file leans on: a buffer the core returns is freed exactly once by
/// <c>storyarc_buffer_free</c>; a failed call leaves a message for the calling thread that
/// <c>storyarc_last_error</c> hands back and the caller never frees; every handle is opaque, owned
/// by a <see cref="SafeHandle"/> here, and freed once by its own <c>_free</c>; a path crosses as
/// UTF-8 bytes with their length, never NUL-terminated.
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
        int status;
        fixed (byte* data = bytes)
        {
            status = NativeMethods.storyarc_buffer_roundtrip(data, (nuint)bytes.Length, &buffer);
        }

        Check(status, "storyarc_buffer_roundtrip");
        return Take(buffer);
    }

    /// <summary>Throws <see cref="StoryArcException"/> with this thread's message unless <paramref name="status"/> is OK.</summary>
    internal static void Check(int status, string call)
    {
        if (status != NativeMethods.STORYARC_OK)
        {
            throw new StoryArcException(call, (StoryArcStatus)status, LastError());
        }
    }

    /// <summary>Copies a buffer the core returned into managed memory and frees it, on every path.</summary>
    internal static byte[] Take(StoryArcBuffer buffer)
    {
        try
        {
            return buffer.len == 0 ? [] : new ReadOnlySpan<byte>(buffer.data, checked((int)buffer.len)).ToArray();
        }
        finally
        {
            NativeMethods.storyarc_buffer_free(buffer);
        }
    }

    /// <summary>A buffer of UTF-8 text the core returned, as a string, the buffer freed.</summary>
    internal static string TakeString(StoryArcBuffer buffer) => Encoding.UTF8.GetString(Take(buffer));

    /// <summary>A string as the UTF-8 bytes the seam takes for a path or a JSON argument.</summary>
    internal static byte[] Utf8(string text) => Encoding.UTF8.GetBytes(text);

    /// <summary>The shape of every wave 3 export that takes one JSON request and writes one buffer.</summary>
    internal unsafe delegate int JsonExport(byte* request, nuint requestLength, StoryArcBuffer* output);

    /// <summary>The same for the exports that work on a handle first: the HTTP client, the share, the vault.</summary>
    internal unsafe delegate int HandleJsonExport(void* handle, byte* request, nuint requestLength, StoryArcBuffer* output);

    /// <summary>
    /// Calls an export of the <see cref="JsonExport"/> shape with <paramref name="request"/> as UTF-8 and
    /// answers the text it wrote. The request bytes are wiped afterwards, because a request can carry the
    /// one password or token its call needs. A failure throws <see cref="StoryArcException"/> and frees
    /// whatever buffer the core left.
    /// </summary>
    internal static string CallJson(JsonExport export, string call, string request) =>
        CallJson((_, data, length, output) => export(data, length, output), null, call, request);

    /// <summary>As <see cref="CallJson(JsonExport, string, string)"/> for an export that takes <paramref name="handle"/> first.</summary>
    internal static string CallJson(HandleJsonExport export, void* handle, string call, string request)
    {
        var bytes = Utf8(request);
        StoryArcBuffer buffer = default;
        int status;
        try
        {
            fixed (byte* data = bytes)
            {
                status = export(handle, data, (nuint)bytes.Length, &buffer);
            }
        }
        finally
        {
            System.Security.Cryptography.CryptographicOperations.ZeroMemory(bytes);
        }

        if (status != NativeMethods.STORYARC_OK)
        {
            var error = new StoryArcException(call, (StoryArcStatus)status, LastError());
            NativeMethods.storyarc_buffer_free(buffer);
            throw error;
        }

        return TakeString(buffer);
    }

    private static string? ReadStatic(byte* text) =>
        text is null ? null : Marshal.PtrToStringUTF8((nint)text);
}

/// <summary>
/// What every core handle shares: it owns one opaque pointer, frees it once, and holds a reference
/// while a call runs so a dispose on another thread waits for the call instead of freeing under it.
/// Calls on one handle are also serialised, because a reader window decodes pages on worker threads.
/// </summary>
public abstract unsafe class CoreHandle : SafeHandle
{
    private readonly Lock _gate = new();

    protected CoreHandle()
        : base(IntPtr.Zero, ownsHandle: true)
    {
    }

    private CoreHandle? _owner;

    public override bool IsInvalid => handle == IntPtr.Zero;

    /// <summary>
    /// Keeps <paramref name="owner"/> alive for as long as this handle is: the core frees its runtime only
    /// after every handle made from it, and this is how the wrapper keeps that order. Call
    /// <see cref="ReleaseOwner"/> from <c>ReleaseHandle</c>, after the handle's own free.
    /// </summary>
    protected void Retain(CoreHandle owner)
    {
        var added = false;
        owner.DangerousAddRef(ref added);
        if (!added)
        {
            throw new ObjectDisposedException(owner.GetType().Name);
        }

        _owner = owner;
    }

    protected void ReleaseOwner()
    {
        _owner?.DangerousRelease();
        _owner = null;
    }

    /// <summary>
    /// As <see cref="Use{T}"/> without the per-handle gate, for the two handles the core shares between
    /// threads by design: the runtime, and a call that only borrows it. A blocking call on the runtime
    /// (a share connecting) must not hold up a poll of the network state.
    /// </summary>
    protected T UseShared<T>(Func<nint, T> call)
    {
        var added = false;
        try
        {
            DangerousAddRef(ref added);
            return call(handle);
        }
        finally
        {
            if (added)
            {
                DangerousRelease();
            }
        }
    }

    /// <summary>Runs <paramref name="call"/> with the live pointer. Throws <see cref="ObjectDisposedException"/> after dispose.</summary>
    protected T Use<T>(Func<nint, T> call)
    {
        var added = false;
        lock (_gate)
        {
            try
            {
                DangerousAddRef(ref added);
                return call(handle);
            }
            finally
            {
                if (added)
                {
                    DangerousRelease();
                }
            }
        }
    }

    /// <summary>Takes ownership of a pointer an <c>_open</c> wrote.</summary>
    protected void Adopt(void* pointer) => SetHandle((nint)pointer);
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

/// <summary>
/// A scanned folder source (<c>storyarc_folder_open</c>): the publications the core found in it,
/// read as records. The scan happens in <see cref="Open"/>; a rescan is a second open, which the core
/// reconciles by modification time and size rather than reading every archive again.
/// </summary>
public sealed unsafe class ComicFolder : CoreHandle
{
    private ComicFolder()
    {
    }

    /// <summary>
    /// Scans the folder at <paramref name="path"/>. A missing folder throws with
    /// <see cref="StoryArcStatus.NotFound"/>; a raised <paramref name="cancel"/> with <see cref="StoryArcStatus.Cancelled"/>.
    /// </summary>
    public static ComicFolder Open(string path, CancelToken? cancel = null)
    {
        var bytes = NativeCore.Utf8(path);
        void* opened = null;
        var added = false;
        try
        {
            // The token is held for the length of the scan, so a dispose elsewhere cannot free it under the core.
            cancel?.DangerousAddRef(ref added);
            var token = added ? (void*)cancel!.DangerousGetHandle() : null;
            fixed (byte* data = bytes)
            {
                NativeCore.Check(NativeMethods.storyarc_folder_open(data, (nuint)bytes.Length, token, &opened), "storyarc_folder_open");
            }
        }
        finally
        {
            if (added)
            {
                cancel!.DangerousRelease();
            }
        }

        var folder = new ComicFolder();
        folder.Adopt(opened);
        return folder;
    }

    /// <summary>The folder's publications as the UTF-8 JSON array the core wrote.</summary>
    public string RecordsJson() => Use(pointer =>
    {
        StoryArcBuffer buffer = default;
        NativeCore.Check(NativeMethods.storyarc_folder_records((void*)pointer, &buffer), "storyarc_folder_records");
        return NativeCore.TakeString(buffer);
    });

    /// <summary>The folder's publications, parsed.</summary>
    public IReadOnlyList<CorePublication> Records() => CorePublication.ListFrom(RecordsJson());

    protected override bool ReleaseHandle()
    {
        NativeMethods.storyarc_folder_free((void*)handle);
        return true;
    }
}

/// <summary>One decoded page: 8-bit RGBA, not premultiplied, rows top to bottom with no padding.</summary>
public sealed record DecodedPage(int Width, int Height, byte[] Rgba);

/// <summary>
/// An open comic (<c>storyarc_publication_open</c>): a CBZ, CBR, CBT or a folder of images. It
/// answers its page count and its record, and decodes one page at a time at the size asked for.
/// A refused format, CB7 among them, throws with <see cref="StoryArcStatus.Unsupported"/> and its name.
/// </summary>
public sealed unsafe class ComicPublication : CoreHandle
{
    private ComicPublication()
    {
    }

    /// <summary>
    /// Opens the comic at <paramref name="path"/>. A missing file throws with <see cref="StoryArcStatus.NotFound"/>,
    /// a refused format with <see cref="StoryArcStatus.Unsupported"/> and a locked or damaged one with
    /// <see cref="StoryArcStatus.Unreadable"/>, each with the core's sentence in <see cref="StoryArcException.CoreMessage"/>.
    /// </summary>
    public static ComicPublication Open(string path)
    {
        var bytes = NativeCore.Utf8(path);
        void* opened = null;
        fixed (byte* data = bytes)
        {
            NativeCore.Check(NativeMethods.storyarc_publication_open(data, (nuint)bytes.Length, &opened), "storyarc_publication_open");
        }

        var publication = new ComicPublication();
        publication.Adopt(opened);
        return publication;
    }

    /// <summary>The number of pages, in reading order.</summary>
    public int PageCount => Use(pointer =>
    {
        uint count = 0;
        NativeCore.Check(NativeMethods.storyarc_publication_page_count((void*)pointer, &count), "storyarc_publication_page_count");
        return checked((int)count);
    });

    /// <summary>The publication's record as the UTF-8 JSON object the core wrote.</summary>
    public string MetadataJson() => Use(pointer =>
    {
        StoryArcBuffer buffer = default;
        NativeCore.Check(NativeMethods.storyarc_publication_metadata((void*)pointer, &buffer), "storyarc_publication_metadata");
        return NativeCore.TakeString(buffer);
    });

    /// <summary>The publication's record, parsed.</summary>
    public CorePublication Metadata() => CorePublication.From(MetadataJson());

    /// <summary>
    /// Decodes page <paramref name="index"/> (from zero), at most <paramref name="maxPixelSize"/> on its
    /// longest edge, or at its own size for zero. An index past the end throws with
    /// <see cref="StoryArcStatus.InvalidArgument"/>; a codec the build refuses with
    /// <see cref="StoryArcStatus.Unsupported"/>; a damaged page with <see cref="StoryArcStatus.Unreadable"/>.
    /// </summary>
    public DecodedPage DecodePage(int index, int maxPixelSize = 0)
    {
        ArgumentOutOfRangeException.ThrowIfNegative(index);
        ArgumentOutOfRangeException.ThrowIfNegative(maxPixelSize);
        return Use(pointer =>
        {
            StoryArcBuffer pixels = default;
            uint width = 0;
            uint height = 0;
            var status = NativeMethods.storyarc_publication_decode_page(
                (void*)pointer, (uint)index, (uint)maxPixelSize, &pixels, &width, &height);
            NativeCore.Check(status, "storyarc_publication_decode_page");
            return new DecodedPage(checked((int)width), checked((int)height), NativeCore.Take(pixels));
        });
    }

    protected override bool ReleaseHandle()
    {
        NativeMethods.storyarc_publication_free((void*)handle);
        return true;
    }
}

/// <summary>
/// The progress store (<c>storyarc_store_open</c>): one reading position per publication, kept in
/// the shape the phones' library documents use and merged by ADR-0006. Finished stays finished.
/// </summary>
public sealed unsafe class ProgressStore : CoreHandle
{
    private ProgressStore()
    {
    }

    /// <summary>Opens the store at <paramref name="path"/>, creating it when it is not there.</summary>
    public static ProgressStore Open(string path)
    {
        var bytes = NativeCore.Utf8(path);
        void* opened = null;
        fixed (byte* data = bytes)
        {
            NativeCore.Check(NativeMethods.storyarc_store_open(data, (nuint)bytes.Length, &opened), "storyarc_store_open");
        }

        var store = new ProgressStore();
        store.Adopt(opened);
        return store;
    }

    /// <summary>The record of the publication with <paramref name="identity"/>, or <c>null</c> when none is kept.</summary>
    public CoreProgress? Read(CoreIdentity identity)
    {
        var json = ReadJson(identity.ToJson());
        return json == "null" ? null : CoreProgress.FromJson(json);
    }

    /// <summary>The raw call: the identity as JSON in, the record or the JSON <c>null</c> out.</summary>
    public string ReadJson(string identityJson)
    {
        var bytes = NativeCore.Utf8(identityJson);
        return Use(pointer =>
        {
            StoryArcBuffer buffer = default;
            fixed (byte* data = bytes)
            {
                NativeCore.Check(
                    NativeMethods.storyarc_progress_read((void*)pointer, data, (nuint)bytes.Length, &buffer),
                    "storyarc_progress_read");
            }

            return NativeCore.TakeString(buffer);
        });
    }

    /// <summary>Records <paramref name="progress"/>. A full disk throws with <see cref="StoryArcStatus.Storage"/>.</summary>
    public void Write(CoreProgress progress) => WriteJson(progress.ToJson());

    /// <summary>The raw call. A record that is not one throws with <see cref="StoryArcStatus.InvalidArgument"/>.</summary>
    public void WriteJson(string recordJson)
    {
        var bytes = NativeCore.Utf8(recordJson);
        _ = Use(pointer =>
        {
            fixed (byte* data = bytes)
            {
                NativeCore.Check(
                    NativeMethods.storyarc_progress_write((void*)pointer, data, (nuint)bytes.Length),
                    "storyarc_progress_write");
            }

            return true;
        });
    }

    protected override bool ReleaseHandle()
    {
        NativeMethods.storyarc_store_free((void*)handle);
        return true;
    }
}
