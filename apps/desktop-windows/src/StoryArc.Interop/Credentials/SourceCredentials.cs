using System.Text;
using StoryArc.Interop.Sources;

namespace StoryArc.Interop.Credentials;

/// <summary>How a save of one source's credential ended.</summary>
public enum CredentialOutcome
{
    /// <summary>In Credential Manager, under the package's own name, not roaming.</summary>
    Stored,

    /// <summary>
    /// Held in memory for this session because the system's store is not available: the source works until the app quits and
    /// asks again at the next launch. <see cref="CredentialResult.Notice"/> is the grey line, given once.
    /// </summary>
    SessionOnly,

    /// <summary>
    /// Longer than Credential Manager keeps (2560 bytes). Named, not kept anywhere, and the source needs a sign-in.
    /// </summary>
    TooLong,

    /// <summary>The store rejected the write, or the reader denied its prompt. Named, no copy kept, the source needs a sign-in.</summary>
    Refused,
}

/// <summary>The result of saving a credential: what happened, the grey line for it when there is one, and whether the source needs a sign-in now.</summary>
public sealed record CredentialResult(CredentialOutcome Outcome, string? Notice, string? Failure)
{
    /// <summary>The source shows as needing a sign-in whenever its credential was not kept for the session at least.</summary>
    public bool NeedsSignIn => Outcome is CredentialOutcome.TooLong or CredentialOutcome.Refused;
}

/// <summary>
/// The credentials of the sources, through the core's vault (desktop-clients task 3.22; desktop-experience, "Secrets in the
/// system's own store"). The vault is Credential Manager on Windows and the session alone elsewhere. This class adds the one rule
/// the store has and the core's session-only path does not: a Credential Manager blob is at most 2560 bytes
/// (<c>CRED_MAX_CREDENTIAL_BLOB_SIZE</c>), so a longer credential is refused by name the same way on every host and never lands
/// half-kept. A source's record holds only its id.
/// </summary>
public sealed class SourceCredentials(CredentialVault vault)
{
    /// <summary>The longest credential Credential Manager keeps, in bytes of UTF-8.</summary>
    public const int BlobLimit = 2560;

    /// <summary>Whether <paramref name="credential"/> is within what the store keeps.</summary>
    public static bool Fits(string credential) => Encoding.UTF8.GetByteCount(credential) <= BlobLimit;

    /// <summary>
    /// Saves the credential, or says why it was not kept. An older credential under the same field is removed first when the new
    /// one cannot be kept, so no copy of any kind stays behind a source that now needs a sign-in.
    /// </summary>
    public CredentialResult Save(string sourceId, string field, string credential)
    {
        var key = new CredentialField(sourceId, field);
        if (!Fits(credential))
        {
            vault.Delete(key);
            return new CredentialResult(
                CredentialOutcome.TooLong,
                null,
                $"The {field} is longer than the {BlobLimit} bytes Credential Manager keeps.");
        }

        try
        {
            var saved = vault.Save(key, credential);
            return saved.IsStored
                ? new CredentialResult(CredentialOutcome.Stored, null, null)
                : new CredentialResult(CredentialOutcome.SessionOnly, saved.Notice, null);
        }
        catch (StoryArcException error) when (error.Status == StoryArcStatus.Storage)
        {
            return new CredentialResult(CredentialOutcome.Refused, null, error.CoreMessage);
        }
    }

    /// <summary>The credential, or <c>null</c> when none is held.</summary>
    public string? Load(string sourceId, string field) => vault.Load(new CredentialField(sourceId, field));

    /// <summary>Removes every credential of <paramref name="source"/> from the store and the session: what removing the source asks.</summary>
    public void Forget(NetworkSource source)
    {
        foreach (var field in source.CredentialFields)
        {
            vault.Delete(new CredentialField(source.Id, field));
        }
    }

    /// <summary>Whether <paramref name="source"/> has the credential it needs held now. A guest share or an open catalogue needs none.</summary>
    public bool Holds(NetworkSource source) => source.CredentialFields.Any(field => Load(source.Id, field) is not null);
}
