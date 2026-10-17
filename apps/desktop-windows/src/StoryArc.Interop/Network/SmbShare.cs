using System.Text.Json;

namespace StoryArc.Interop.Network;

/// <summary>What a connected share negotiated: the SMB dialect, and whether the session is encrypted.</summary>
public sealed record SmbIdentity(string Dialect = "", bool IsEncrypted = false);

/// <summary>One entry of a folder on a share. <see cref="Path"/> is relative to the address's own folder.</summary>
public sealed record SmbEntry(string Name = "", string Path = "", bool IsDirectory = false, long Length = 0);

/// <summary>Where a share is, and who is asking. No user name is a guest.</summary>
public sealed record SmbConnection(string Address, int? Port = null, string? Username = null, string? Password = null)
{
    /// <summary>Never prints the password: a record's own <c>ToString</c> would, into a log or a failed assertion.</summary>
    public override string ToString() => "SmbConnection { Address = " + Address + " }";

    internal string ToJson() => JsonText.Object(
        ("address", Address),
        ("port", Port),
        ("username", string.IsNullOrEmpty(Username) ? null : Username),
        ("password", Password));
}

/// <summary>
/// A connected SMB share (<c>storyarc_smb_connect</c>), the core's own client and not the system redirector. The
/// four named failures and the SMB 1 refusal come back as <see cref="StoryArcException"/> with their remedy in
/// <see cref="StoryArcException.CoreMessage"/>; a host that does not answer is <see cref="StoryArcStatus.Unreachable"/>.
/// </summary>
public sealed unsafe class SmbShare : CoreHandle
{
    private SmbShare()
    {
    }

    /// <summary>Connects, which blocks until the server answers or the core gives up: call it off the interface thread.</summary>
    public static SmbShare Connect(CoreRuntime runtime, SmbConnection connection)
    {
        var request = connection.ToJson();
        var pointer = runtime.Borrow(runtimePointer =>
        {
            var bytes = NativeCore.Utf8(request);
            void* opened = null;
            try
            {
                fixed (byte* data = bytes)
                {
                    NativeCore.Check(
                        NativeMethods.storyarc_smb_connect((void*)runtimePointer, data, (nuint)bytes.Length, &opened),
                        "storyarc_smb_connect");
                }
            }
            finally
            {
                System.Security.Cryptography.CryptographicOperations.ZeroMemory(bytes);
            }

            return (nint)opened;
        });
        var share = new SmbShare();
        share.Adopt((void*)pointer);
        share.Retain(runtime);
        return share;
    }

    /// <summary>The dialect negotiated and whether the session is encrypted, which the source states to the reader.</summary>
    public SmbIdentity Identity() => Use(pointer =>
    {
        StoryArcBuffer buffer = default;
        NativeCore.Check(NativeMethods.storyarc_smb_identity((void*)pointer, &buffer), "storyarc_smb_identity");
        return JsonSerializer.Deserialize(NativeCore.TakeString(buffer), NetworkJsonContext.Default.SmbIdentity)
            ?? throw new JsonException("the core wrote a null share identity");
    });

    /// <summary>One folder of the share, folders first, in natural order. <paramref name="path"/> is empty for the address's own folder.</summary>
    public IReadOnlyList<SmbEntry> List(string path = "")
    {
        var bytes = NativeCore.Utf8(path);
        return Use(pointer =>
        {
            StoryArcBuffer buffer = default;
            fixed (byte* data = bytes)
            {
                NativeCore.Check(NativeMethods.storyarc_smb_list((void*)pointer, data, (nuint)bytes.Length, &buffer), "storyarc_smb_list");
            }

            return JsonSerializer.Deserialize(NativeCore.TakeString(buffer), NetworkJsonContext.Default.SmbEntryArray) ?? [];
        });
    }

    protected override bool ReleaseHandle()
    {
        NativeMethods.storyarc_smb_free((void*)handle);
        ReleaseOwner();
        return true;
    }
}
