using System.Security.Cryptography;
using System.Text.Json;
using System.Text.Json.Nodes;
using StoryArc.Interop.Network;

namespace StoryArc.Interop.Credentials;

/// <summary>
/// One credential of one source: the source's id and the field ("password", "token" or "apiKey"). A source's own
/// record holds only its id, never the credential (desktop-experience, "Saving a password").
/// </summary>
public sealed record CredentialField(string SourceId, string Field)
{
    public const string Password = "password";
    public const string Token = "token";
    public const string ApiKey = "apiKey";

    internal string ToJson() => JsonText.Object(("sourceId", SourceId), ("field", Field));
}

/// <summary>
/// What a save did: kept in the system's store (Credential Manager on Windows), or held for the session only
/// because no store runs. <see cref="Notice"/> is the grey line that says what supplies one, and the core gives it
/// the first time only.
/// </summary>
public sealed record CredentialSaveOutcome(bool IsStored, string? Notice);

/// <summary>
/// The vault (<c>storyarc_vault_open</c>): the system's store behind the core's one rule set. On Windows the store
/// is Credential Manager with <c>CRED_PERSIST_LOCAL_MACHINE</c>, so nothing roams. Without a store the credential
/// lives in memory for the session. This code never writes a credential to a file, and neither does the core.
/// </summary>
public sealed unsafe class CredentialVault : CoreHandle
{
    private CredentialVault()
    {
    }

    public static CredentialVault Open(CoreRuntime runtime)
    {
        var pointer = runtime.Borrow(runtimePointer =>
        {
            void* opened = null;
            NativeCore.Check(NativeMethods.storyarc_vault_open((void*)runtimePointer, &opened), "storyarc_vault_open");
            return (nint)opened;
        });
        var vault = new CredentialVault();
        vault.Adopt((void*)pointer);
        vault.Retain(runtime);
        return vault;
    }

    /// <summary>
    /// Saves <paramref name="credential"/>. A refusal of the store is <see cref="StoryArcStatus.Storage"/> with the
    /// core's sentence, and no copy is kept anywhere.
    /// </summary>
    public CredentialSaveOutcome Save(CredentialField field, string credential)
    {
        var key = NativeCore.Utf8(field.ToJson());
        var bytes = NativeCore.Utf8(credential);
        try
        {
            var json = Use(pointer =>
            {
                StoryArcBuffer buffer = default;
                int status;
                fixed (byte* keyData = key)
                fixed (byte* credentialData = bytes)
                {
                    status = NativeMethods.storyarc_vault_save(
                        (void*)pointer, keyData, (nuint)key.Length, credentialData, (nuint)bytes.Length, &buffer);
                }

                if (status != NativeMethods.STORYARC_OK)
                {
                    var error = new StoryArcException("storyarc_vault_save", (StoryArcStatus)status, NativeCore.LastError());
                    NativeMethods.storyarc_buffer_free(buffer);
                    throw error;
                }

                return NativeCore.TakeString(buffer);
            });
            var node = JsonNode.Parse(json) ?? throw new JsonException("the core wrote a null save outcome");
            return new CredentialSaveOutcome(node["stored"]?.GetValue<bool>() ?? false, node["notice"]?.GetValue<string>());
        }
        finally
        {
            CryptographicOperations.ZeroMemory(bytes);
        }
    }

    /// <summary>The credential, or <c>null</c> when none is held for that field.</summary>
    public string? Load(CredentialField field)
    {
        var key = NativeCore.Utf8(field.ToJson());
        return Use<string?>(pointer =>
        {
            StoryArcBuffer buffer = default;
            int status;
            fixed (byte* keyData = key)
            {
                status = NativeMethods.storyarc_vault_load((void*)pointer, keyData, (nuint)key.Length, &buffer);
            }

            if (status == NativeMethods.STORYARC_ERROR_NOT_FOUND)
            {
                NativeMethods.storyarc_buffer_free(buffer);
                return null;
            }

            if (status != NativeMethods.STORYARC_OK)
            {
                var error = new StoryArcException("storyarc_vault_load", (StoryArcStatus)status, NativeCore.LastError());
                NativeMethods.storyarc_buffer_free(buffer);
                throw error;
            }

            return NativeCore.TakeString(buffer);
        });
    }

    /// <summary>Removes the credential from the store and the session, which is what removing a source asks.</summary>
    public void Delete(CredentialField field)
    {
        var key = NativeCore.Utf8(field.ToJson());
        _ = Use(pointer =>
        {
            fixed (byte* keyData = key)
            {
                NativeCore.Check(NativeMethods.storyarc_vault_delete((void*)pointer, keyData, (nuint)key.Length), "storyarc_vault_delete");
            }

            return true;
        });
    }

    protected override bool ReleaseHandle()
    {
        NativeMethods.storyarc_vault_free((void*)handle);
        ReleaseOwner();
        return true;
    }
}
