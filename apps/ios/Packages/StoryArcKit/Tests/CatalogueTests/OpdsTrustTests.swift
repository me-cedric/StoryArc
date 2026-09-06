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
/// The decision itself is driven here, through `OpdsTrustDelegate.decision(for:host:)`: a
/// certificate the system refuses is refused and described, a pinned one is accepted, a pin
/// does not travel to another host, and a certificate the system trusts is accepted whatever
/// is pinned. Android's `OpdsTrustTest` drives the same four over the same certificate.
///
/// **What this suite cannot reach, and why.** `OpdsTrustDelegate.urlSession(_:didReceive:)`
/// takes a `URLAuthenticationChallenge`, and a challenge carries the server's certificate in
/// `URLProtectionSpace.serverTrust`, which is read-only and populated by the system alone —
/// no public initialiser sets it. So that one method cannot be called at a desk, and it holds
/// nothing but the guard and the two reads that hand `decision(for:host:)` its arguments.
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

    /// The same certificate, made its own anchor, so the system evaluates it.
    ///
    /// This is what a certificate a certificate authority issued looks like to the decision:
    /// `SecTrustEvaluateWithError` answers true. Anchoring one certificate is how a test gets
    /// that answer without a real chain, which would expire and would need the network.
    private func trustedTrust() throws -> SecTrust {
        let trust = try trust()
        #expect(SecTrustSetAnchorCertificates(trust, [try certificate()] as CFArray) == errSecSuccess)
        #expect(SecTrustSetAnchorCertificatesOnly(trust, true) == errSecSuccess)
        return trust
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

    // MARK: The decision

    @Test func anUntrustedCertificateIsRefusedAndDescribed() throws {
        let delegate = OpdsTrustDelegate(pins: CertificatePins())
        let (disposition, credential) = delegate.decision(for: try trust(), host: Self.host)
        #expect(disposition == .cancelAuthenticationChallenge)
        #expect(credential == nil)
        let refusal = try #require(delegate.takeRefusal())
        #expect(refusal.host == Self.host)
        #expect(refusal.fingerprint == Self.fingerprint)
        #expect(refusal.subject.contains("storyarc-test.invalid"))
    }

    @Test func aPinnedCertificateIsAccepted() throws {
        let delegate = OpdsTrustDelegate(pins: CertificatePins([Self.host: [Self.fingerprint]]))
        let (disposition, credential) = delegate.decision(for: try trust(), host: Self.host)
        #expect(disposition == .useCredential)
        #expect(credential != nil)
        // Nothing to ask the reader about: they already answered for this certificate.
        #expect(delegate.takeRefusal() == nil)
    }

    @Test func aPinOnAnotherHostDoesNotOpenThisOne() throws {
        let delegate = OpdsTrustDelegate(pins: CertificatePins(["other.example": [Self.fingerprint]]))
        let (disposition, _) = delegate.decision(for: try trust(), host: Self.host)
        #expect(disposition == .cancelAuthenticationChallenge)
        #expect(delegate.takeRefusal()?.fingerprint == Self.fingerprint)
    }

    /// A pin is an exception the reader adds, not a restriction they impose.
    ///
    /// `opds-catalog` offers the pin only "WHEN a catalogue presents a certificate the system
    /// does not trust", so a certificate the system does trust is accepted whether or not a
    /// pin exists. Asserted rather than assumed, because the other reading — a pinned host
    /// refusing every other certificate — is a different feature.
    @Test func aSystemTrustedCertificateIsAcceptedWhateverIsPinned() throws {
        let delegate = OpdsTrustDelegate(pins: CertificatePins([Self.host: ["00:11:22"]]))
        let (disposition, credential) = delegate.decision(for: try trustedTrust(), host: Self.host)
        #expect(disposition == .useCredential)
        #expect(credential != nil)
        #expect(delegate.takeRefusal() == nil)
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
