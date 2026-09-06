import Foundation
import Security
import Testing

@testable import Catalogue

/// The certificate decision a reader meets when they add a catalogue.
///
/// `opds-catalog`, "Self-signed certificate": a catalogue presenting a certificate the system
/// does not trust is refused "by default", the app "explains why", and it "offers to pin that
/// specific certificate after showing its fingerprint".
///
/// **What this suite cannot reach, and why.** `OpdsTrustDelegate.urlSession(_:didReceive:)`
/// takes a `URLAuthenticationChallenge`, and a challenge carries the server's certificate in
/// `URLProtectionSpace.serverTrust`, which is read-only and populated by the system alone —
/// no public initialiser sets it. So the delegate method itself cannot be called at a desk.
/// The alternative, a TLS listener on loopback, needs a `SecIdentity`, which needs a private
/// key in the repository; `security.md` forbids that and it is not worth a test.
///
/// Every part the delegate builds its answer from is asserted here instead: that the system
/// refuses this certificate, that the fingerprint shown is the SHA-256 of the DER, that the
/// leaf is the certificate taken from the chain, and every rule `CertificatePins` applies.
/// Android's `OpdsTrustTest` asserts the same fingerprint over the same certificate, and
/// additionally drives the whole decision, because `X509TrustManager` is an interface a test
/// can call.
struct OpdsTrustTests {
    /// A self-signed certificate, `CN=storyarc-test.invalid`, generated once for this suite.
    ///
    /// The public half only. There is no private key here and no server to start: the suite
    /// needs a certificate to describe, not a handshake to complete. Android's suite carries
    /// the same bytes, so the two fingerprints are comparable by reading.
    private static let der = Data(base64Encoded: [
        "MIICvDCCAaQCCQCFu1YvS2eBAzANBgkqhkiG9w0BAQsFADAgMR4wHAYDVQQDDBVz",
        "dG9yeWFyYy10ZXN0LmludmFsaWQwHhcNMjYwOTA2MTUxNjQzWhcNNDYwOTAxMTUx",
        "NjQzWjAgMR4wHAYDVQQDDBVzdG9yeWFyYy10ZXN0LmludmFsaWQwggEiMA0GCSqG",
        "SIb3DQEBAQUAA4IBDwAwggEKAoIBAQCzbuveCoU6GRNNt5B6it0HDmfJcNjHvt3Z",
        "DyxvvadztCwEKPDb1eSflgr+lv0fPiPUXrq9XnmftjwOLjPsKxxYMgaeSBoSraB5",
        "7sz3xrYekXV6C5STeGHbFdgB47Bikds0sq34Ac+a9V8SW6D59DWx3CA+SLc5QFmM",
        "vU0gkswL0W8U1p/5sYirQNF3v2mFb/xjRKGGIkaB6dfH9XXewJdKIl8x4PkYlYES",
        "CXo/fkroHj2p0eTxrTf9CTCV0glqmdMJb98dFZ40jWQ2ALQGzBfLHl14lIMZDFHU",
        "ZDDinnEHeTrYwM7l0uo976AFWXkVsIUwXWfciYrnvKWnIfBexklLAgMBAAEwDQYJ",
        "KoZIhvcNAQELBQADggEBAJhDPhlht0JpnoprzeXIN8PqK2KlF6z6Ij8LQ+oAHBok",
        "3pjfzzhbk3IdQCU2YypXRuOSGtCoemCmf4ch83YUOyw5G4UxqV0ZDntNjEoq15uX",
        "Tw+mcpTuSVUfr+RutjLV71gLsHMX1SVffcMbF7YsUaUXS4oyGuXoRacibLGnMNm/",
        "PDiBzXAz1h69RmHytSB4Ws9Y93ofZpLeEP2KsFj8LRWLIiCXXWvloa2DnIUtWlB3",
        "47U3aVWUjIwaDa8Mup58ulyLR6lXipLlUSc9oepxWeoSDT46At3sWVzHjW1oxUd1",
        "ZDo1duNUATwIjAtwJuYlDK+BG/rO0X0JPc/0d5BAGLM=",
    ].joined())

    /// What `openssl x509 -fingerprint -sha256` prints for that certificate.
    private static let fingerprint =
        "6B:D2:93:82:01:BB:37:FD:A2:61:8F:77:EB:99:1F:3F:F1:DE:9B:31:A6:C2:48:A1:77:15:22:25:7B:48:2B:56"

    private static let host = "books.example"

    private func certificate() throws -> SecCertificate {
        let der = try #require(Self.der)
        return try #require(SecCertificateCreateWithData(nil, der as CFData))
    }

    private func trust() throws -> SecTrust {
        var made: SecTrust?
        let status = SecTrustCreateWithCertificates(
            try certificate(),
            SecPolicyCreateBasicX509(),
            &made
        )
        #expect(status == errSecSuccess)
        return try #require(made)
    }

    // MARK: What the reader is shown

    @Test func theSystemDoesNotVouchForASelfSignedCertificate() throws {
        // The scenario's WHEN. A certificate signed by nothing the system knows fails to
        // evaluate, which is what puts the decision in front of the reader at all.
        #expect(!SecTrustEvaluateWithError(try trust(), nil))
    }

    @Test func theLeafIsTheCertificateTheServerPresented() throws {
        let leaf = try #require(OpdsTrustDelegate.leaf(of: try trust()))
        #expect(SecCertificateCopyData(leaf) as Data == Self.der)
    }

    @Test func theFingerprintIsTheSha256OfTheCertificate() throws {
        #expect(OpdsTrustDelegate.fingerprint(of: try certificate()) == Self.fingerprint)
    }

    @Test func theSubjectNamesTheServerTheReaderIsLookingAt() throws {
        let subject = try #require(OpdsTrustDelegate.subject(of: try certificate()))
        #expect(subject.contains("storyarc-test.invalid"))
    }

    @Test func aRefusalCarriesEverythingTheOfferNeeds() throws {
        let refusal = UntrustedCertificate(
            host: Self.host,
            fingerprint: OpdsTrustDelegate.fingerprint(of: try certificate()),
            subject: OpdsTrustDelegate.subject(of: try certificate()) ?? Self.host,
            notValidAfter: nil
        )
        #expect(refusal.host == Self.host)
        #expect(refusal.fingerprint == Self.fingerprint)
    }

    // MARK: What the reader accepted

    @Test func nothingIsPinnedUntilAReaderPinsIt() {
        #expect(!CertificatePins().accepts(Self.fingerprint, from: Self.host))
    }

    @Test func aPinnedFingerprintIsAcceptedOnItsOwnHost() {
        let pins = CertificatePins()
        pins.pin(Self.fingerprint, for: Self.host)
        #expect(pins.accepts(Self.fingerprint, from: Self.host))
    }

    @Test func aPinBelongsToOneHost() {
        let pins = CertificatePins([Self.host: [Self.fingerprint]])
        #expect(!pins.accepts(Self.fingerprint, from: "other.example"))
    }

    @Test func aPinBelongsToOneCertificate() {
        let pins = CertificatePins([Self.host: ["00:11:22"]])
        #expect(!pins.accepts(Self.fingerprint, from: Self.host))
    }

    @Test func forgettingAHostDropsItsPinsAndNoOthers() {
        let pins = CertificatePins([
            Self.host: [Self.fingerprint],
            "other.example": [Self.fingerprint],
        ])
        pins.forget(Self.host)
        #expect(!pins.accepts(Self.fingerprint, from: Self.host))
        #expect(pins.accepts(Self.fingerprint, from: "other.example"))
    }

    @Test func everyPinIsHandedToTheStoreToWrite() {
        let pins = CertificatePins()
        pins.pin(Self.fingerprint, for: Self.host)
        pins.pin("00:11:22", for: "other.example")
        #expect(pins.all == [Self.host: [Self.fingerprint], "other.example": ["00:11:22"]])
    }
}
