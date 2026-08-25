import Testing

@testable import StoryArcCore

/// The redaction rules, one test per thing that must not survive.
///
/// `settings-and-about` asks for the redaction to be "a tested function, not a regex
/// written at the call site". A regex nobody tests is a regex that silently stops
/// matching, and the failure mode here is a reader publishing their own password.
/// Android's `DiagnosticRedactionTest` asserts the same table.
@Suite("Diagnostic redaction")
struct DiagnosticRedactionTests {

    // MARK: - Hosts and credentials in URLs

    @Test("A password in a share URL does not survive, and neither does the host")
    func shareCredentials() {
        let redacted = DiagnosticRedaction.redact("smb://reader:hunter2@nas.local:445/comics")

        #expect(redacted == "smb://[host]/comics")
        #expect(!redacted.contains("hunter2"))
        #expect(!redacted.contains("nas.local"))
    }

    @Test("The path survives, because a path is what the diagnostic is for")
    func pathSurvives() {
        let redacted = DiagnosticRedaction.redact("https://kavita.example.com/api/series/12")

        #expect(redacted == "https://[host]/api/series/12")
    }

    @Test("A port is part of the authority and goes with it")
    func portGoes() {
        #expect(DiagnosticRedaction.redact("http://192.168.1.4:8080/opds") == "http://[host]/opds")
    }

    @Test("A bare address needs no scheme to identify a server")
    func bareAddress() {
        let redacted = DiagnosticRedaction.redact("could not reach 192.168.1.40")

        #expect(redacted == "could not reach [host]")
    }

    @Test("A file URL has no host to remove and keeps its path")
    func fileURL() {
        // The empty authority is the point: `file:///` would lose its path to a
        // greedy authority rule, and the path is the whole content of a file URL.
        #expect(DiagnosticRedaction.redact("file:///var/mobile/Comics") == "file://[host]/var/mobile/Comics")
    }

    // MARK: - Named secrets

    @Test("A value introduced by a word meaning secret is removed, and the word is kept")
    func keyedCredentials() {
        for keyed in [
            "token=abc123", "password: hunter2", "apiKey=xyz", "Authorization: Basic dXNlcg",
            "secret = s3cr3t", "bearer eyJhbGci",
        ] {
            let redacted = DiagnosticRedaction.redact(keyed)
            #expect(redacted.contains(DiagnosticRedaction.Marker.credential), "\(keyed)")
        }
    }

    @Test("Knowing a token was present is useful, so the key survives the value")
    func keySurvives() {
        #expect(DiagnosticRedaction.redact("token=abc123") == "token=[redacted]")
    }

    @Test("A word that merely contains a secret word is not a secret")
    func noFalsePositiveOnSubstrings() {
        // "keyboard" contains "key". Redacting the sentence after it would remove
        // the diagnostic while claiming to protect it.
        #expect(DiagnosticRedaction.redact("keyboard shortcuts enabled") == "keyboard shortcuts enabled")
    }

    // MARK: - Unnamed secrets

    @Test("A long opaque run is treated as a token even with nothing naming it")
    func opaqueRun() {
        let key = String(repeating: "a1B2", count: 10)
        #expect(DiagnosticRedaction.redact("stored \(key)") == "stored [token]")
    }

    @Test("A version string is not long enough to look like a token")
    func versionSurvives() {
        // The whole point of the 32-character floor: it sits above every word and
        // version number and below every key format.
        #expect(DiagnosticRedaction.redact("StoryArc 1.4.2 (build 318)") == "StoryArc 1.4.2 (build 318)")
    }

    // MARK: - The reader's own name

    @Test("The home directory carries the reader's name and is replaced by a tilde")
    func homeDirectory() {
        let redacted = DiagnosticRedaction.redact("/Users/someone/Comics/Nausicaa.cbz")

        #expect(redacted == "~/Comics/Nausicaa.cbz")
        #expect(!redacted.contains("someone"))
    }

    @Test("A Linux home is the same rule")
    func linuxHome() {
        #expect(DiagnosticRedaction.redact("/home/someone/books") == "~/books")
    }

    // MARK: - Order

    @Test("Rules compose rather than undoing each other")
    func rulesCompose() {
        let report = """
            source: smb://reader:hunter2@nas.local/comics
            folder: /Users/someone/Comics
            token=aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa
            """
        let redacted = DiagnosticRedaction.redact(report)

        for leaked in ["hunter2", "nas.local", "someone", "aaaaaaaaaaaa"] {
            #expect(!redacted.contains(leaked), "leaked \(leaked)")
        }
        #expect(redacted.contains("smb://[host]/comics"))
        #expect(redacted.contains("~/Comics"))
    }

    @Test("Redaction is idempotent, so a marker is never redacted again")
    func idempotent() {
        // The export can be regenerated, and a marker that itself matched a rule
        // would degrade into `[[[token]]]` on each pass.
        let once = DiagnosticRedaction.redact("smb://reader:hunter2@nas.local/x /Users/a/b token=abc")
        #expect(DiagnosticRedaction.redact(once) == once)
    }

    @Test("Text with nothing to hide is returned unchanged")
    func nothingToRedact() {
        let plain = "iOS 26.0, iPhone17,1, 42 publications, 3.2 MB cache"
        #expect(DiagnosticRedaction.redact(plain) == plain)
    }
}
