using System.Globalization;
using StoryArc.Interop.Sources;

namespace StoryArc.Windows.Shell;

/// <summary>
/// The sentence for each problem a source can have, from the catalogue the iOS app's own strings fill (the same sentences, so a reader sees one
/// wording on every system). The core's message names the server setting for SMB 1 and for encryption; the catalogue's sentence says the
/// same in the reader's language. Every one is shown in grey, never red.
/// </summary>
internal static class SourceMessages
{
    public static string For(SourceFailure failure, NetworkSourceKind kind) => failure.Problem switch
    {
        SourceProblem.HostUnreachable when kind == NetworkSourceKind.NetworkShare => Strings.Get("smb_error_hostUnreachable"),
        SourceProblem.HostUnreachable => Strings.Get("catalogue_error_unreachable"),
        SourceProblem.NotFound when kind == NetworkSourceKind.NetworkShare => Strings.Get("smb_error_shareNotFound"),
        SourceProblem.NotFound => Strings.Get("catalogue_error_unreachable"),
        SourceProblem.SignInRejected when kind == NetworkSourceKind.NetworkShare => Strings.Get("smb_error_authentication"),
        SourceProblem.SignInRejected when kind == NetworkSourceKind.KavitaServer => Strings.Get("kavita_error_keyRejected"),
        SourceProblem.SignInRejected => Strings.Get("catalogue_error_unauthorized"),
        SourceProblem.CertificateNotTrusted => Strings.Get("catalogue_untrusted_title"),
        SourceProblem.Smb1Only => Strings.Get("smb_error_smb1"),
        SourceProblem.EncryptionRequired => Strings.Get("smb_error_encryption"),
        SourceProblem.CredentialNotKept => string.Format(CultureInfo.CurrentCulture, Strings.Get("desktop_w3_sources_credentialRefused___"), failure.Remedy ?? string.Empty),
        _ => Strings.Get("smb_error_unexpected"),
    };

    /// <summary>The short state a source's row shows under its name.</summary>
    public static string State(SourceCheck? check, NetworkSource source) => check switch
    {
        null => Strings.Get("source_state_connecting"),
        { IsConnected: true, Transport: { } transport } => transport,
        { IsConnected: true } => Strings.Get("source_state_connected"),
        { Failure.Problem: SourceProblem.SignInRejected or SourceProblem.CredentialNotKept } => Strings.Get("source_state_unauthorized"),
        { Failure: { } failure } => For(failure, source.Kind),
        _ => Strings.Get("source_state_unreachable"),
    };

    public static string KindTitle(NetworkSourceKind kind) => kind switch
    {
        NetworkSourceKind.NetworkShare => Strings.Get("source_kind_networkShare_title"),
        NetworkSourceKind.OpdsCatalogue => Strings.Get("source_kind_opdsCatalog_title"),
        _ => Strings.Get("source_kind_kavitaServer_title"),
    };
}
