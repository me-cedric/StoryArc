/// Removes from a diagnostic anything a reader would not knowingly publish.
///
/// `settings-and-about` requires the diagnostic export to be shown before sharing
/// "with every credential, token and server hostname redacted", and that the
/// redaction is "a tested function, not a regex written at the call site". This is
/// that function. Android's `DiagnosticRedaction` applies the same five rules in
/// the same order.
///
/// It over-redacts deliberately. A diagnostic missing a hostname is still useful;
/// a diagnostic carrying a token is a leak the reader cannot take back.
///
/// Redaction is the second line of defence, not the first. The first is that
/// `DiagnosticReport` puts no free text in the report at all — a source is
/// reported by kind and state rather than by the name the reader gave it, because
/// a name they chose is where a hostname would be. This function guards the one
/// place free text is unavoidable: file paths.
public enum DiagnosticRedaction {

    /// What replaces a removed value.
    ///
    /// Named rather than blanked, so a reader reading their own report can see that
    /// something was removed and what kind of thing it was. A blank looks like a
    /// bug in the export.
    public enum Marker {
        public static let credential = "[redacted]"
        public static let host = "[host]"
        public static let token = "[token]"
        public static let home = "~"
    }

    /// Applies every rule, in order. Order matters and is asserted by the tests.
    public static func redact(_ text: String) -> String {
        var result = text
        result = withoutURLAuthority(result)
        result = withoutBareAddresses(result)
        result = withoutKeyedCredentials(result)
        result = withoutOpaqueRuns(result)
        result = withoutHomeDirectory(result)
        return result
    }

    /// Rule 1 — the whole authority of a URL, in one step.
    ///
    /// `smb://reader:hunter2@nas.local:445/comics` becomes `smb://[host]/comics`.
    /// Taken as one span rather than as user, host and port separately: split
    /// rules leave the parts they do not claim behind, and the part left behind is
    /// the password. The path survives because a path is diagnostically useful.
    private static func withoutURLAuthority(_ text: String) -> String {
        text.replacing(#/([a-zA-Z][a-zA-Z0-9+.\-]*:\/\/)[^\/\s?#]*/#) { match in
            match.output.1 + Marker.host
        }
    }

    /// Rule 2 — a bare IPv4 address, which needs no scheme to identify a server.
    private static func withoutBareAddresses(_ text: String) -> String {
        text.replacing(#/\b\d{1,3}\.\d{1,3}\.\d{1,3}\.\d{1,3}\b/#) { _ in Marker.host }
    }

    /// Rule 3 — a value introduced by a word that means "secret".
    ///
    /// The key is kept and the value removed. Knowing that a token was present is
    /// diagnostically useful; knowing the token is not.
    private static func withoutKeyedCredentials(_ text: String) -> String {
        text.replacing(
            #/(?i)\b(token|password|passwd|secret|key|apikey|api_key|auth|authorization|bearer)\b[\s=:]+\S+/#
        ) { match in
            match.output.1 + "=" + Marker.credential
        }
    }

    /// Rule 4 — a long unbroken run of token-shaped characters.
    ///
    /// The backstop for a credential that arrives with no key naming it. Thirty-two
    /// characters is above anything a word or a version string reaches and below
    /// every API key format in use.
    private static func withoutOpaqueRuns(_ text: String) -> String {
        text.replacing(#/\b[A-Za-z0-9+\/_\-]{32,}\b/#) { _ in Marker.token }
    }

    /// Rule 5 — the home directory, which carries the reader's own name.
    private static func withoutHomeDirectory(_ text: String) -> String {
        text.replacing(#/\/(?:Users|home)\/[^\/\s]+/#) { _ in Marker.home }
    }
}
