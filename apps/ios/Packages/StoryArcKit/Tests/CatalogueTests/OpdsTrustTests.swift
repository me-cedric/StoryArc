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
/// travels neither to another host nor to another certificate, the fingerprint shown is the
/// leaf's and not its issuer's, and a certificate the system trusts is accepted whatever is
/// pinned. Android's `OpdsTrustTest` drives the same six over the same certificates.
///
/// **What this suite cannot reach, and why.** Two branches, and Android covers the second.
///
/// `OpdsTrustDelegate.urlSession(_:didReceive:)` takes a `URLAuthenticationChallenge`, and a
/// challenge carries the server's certificate in `URLProtectionSpace.serverTrust`, which is
/// read-only and populated by the system alone — no public initialiser sets it. So that one
/// method cannot be called at a desk, and it holds nothing but the guard and the two reads
/// that hand `decision(for:host:)` its arguments.
///
/// The guard for a server that presents no readable certificate cannot be reached either.
/// It needs a `SecTrust` with an empty chain, and `SecTrustCreateWithCertificates` answers
/// `errSecParam` and writes no trust for an empty array, so no such value exists to pass in.
/// Android drives that branch instead, in `aServerThatOffersNoCertificateIsRefused`, over a
/// null chain — which is a value Java's `X509TrustManager` really can be handed.
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

    /// A server certificate that an issuer signed, `CN=storyarc-test-chained.invalid`.
    ///
    /// A server refused for anything but self-signing — an expired chain, a corporate root
    /// the device does not carry — presents its own certificate and then the certificates
    /// that vouch for it. This is the first half of such a chain, so the suite can assert
    /// which half the reader is shown. Android's suite carries the same bytes.
    private static let chainedDer = Data(base64Encoded: [
        "MIICxDCCAawCAhABMA0GCSqGSIb3DQEBCwUAMCcxJTAjBgNVBAMMHHN0b3J5YXJj",
        "LXRlc3QtaXNzdWVyLmludmFsaWQwHhcNMjYwOTA2MTcyNDQ2WhcNNDYwOTAxMTcy",
        "NDQ2WjAoMSYwJAYDVQQDDB1zdG9yeWFyYy10ZXN0LWNoYWluZWQuaW52YWxpZDCC",
        "ASIwDQYJKoZIhvcNAQEBBQADggEPADCCAQoCggEBAM0eogPQxoqTvuSSopn2d4VC",
        "ijau/a+zAY7VhvX5OCJLmcpSwUW3LfIFT1xJhZxP8US8Ik/71oBvqaXShSFg/XM5",
        "ifj7eOd5G796BoyL+h16NOBpwqVlBABIcy6c4TkeiOJArPLt2MQqJtugv19pqOxj",
        "eKfpjo5Nsoz8eX8SX84yItSk7N91UqHyFvbeDOVtdZUaKaGk5odMYVB8bLnP4g/K",
        "o08Jm1QI2xsDEWjqFjLz12nFIEfPx5Kbdgpq6dVUuZHaMaUWnywrmDubojcZlSm/",
        "9Xm54H6evchziIK9HpP9Il/4tikUoYKmivpvnYZbRPFIyNfjn55TLc7YUVn1+jEC",
        "AwEAATANBgkqhkiG9w0BAQsFAAOCAQEAGrtbSuRGtO4jT+MO9KQmFRinICJ8aR0C",
        "KAnwhUtLT0KjCgn40e4clgVowXKcRq9smW2kP6CNspBaKwN3DFGxWu6Z6r6T6UF4",
        "LBBG7Iws8qgRK3wKPEENmeCxmb3iy9cbwNLWE+wyy9q7MvJF/43kEcoDDVGmoSdO",
        "R5Okd0L6zdidmSRyVpVAOtBpL0ad0Arp8WU7szhVAeyMtmjpMLUPL8Z1XR0NawBI",
        "CaBpK8sExoFgMgDOXM8dXZsk8tOyVdaYa2v1OqT1YuCCdlmkH1SS1smPg0QRh35y",
        "l4DbNjLzfcwMzyLF/w0vja9Rw39oljS9Z5J7Sy+E5ePID/Oi7nUN0Q==",
    ].joined())

    /// What `openssl x509 -fingerprint -sha256` prints for that server certificate.
    private static let chainedFingerprint =
        "48:09:02:E7:6F:46:DA:4F:6C:A0:DC:21:B0:63:13:62:4C:8A:74:6F:2A:26:61:31:01:F5:AD:BB:5E:4C:AE:5C"

    /// The issuer that signed it, `CN=storyarc-test-issuer.invalid`.
    ///
    /// The second half of the chain, and the certificate the reader must never be shown in
    /// place of the first. Its fingerprint is not named here, because no assertion wants it:
    /// what the tests state is that the value shown is the leaf's.
    private static let chainedIssuerDer = Data(base64Encoded: [
        "MIIC5DCCAcygAwIBAgIJALG8Zw5jz188MA0GCSqGSIb3DQEBCwUAMCcxJTAjBgNV",
        "BAMMHHN0b3J5YXJjLXRlc3QtaXNzdWVyLmludmFsaWQwHhcNMjYwOTA2MTcyNDQ2",
        "WhcNNDYwOTAxMTcyNDQ2WjAnMSUwIwYDVQQDDBxzdG9yeWFyYy10ZXN0LWlzc3Vl",
        "ci5pbnZhbGlkMIIBIjANBgkqhkiG9w0BAQEFAAOCAQ8AMIIBCgKCAQEAvhOz3Tzk",
        "3A3Tclccc7hcNLXcLEPW8NDhK2/GVFodp8lawerlutHCp6qmnrSfdL6EUhXB2ZId",
        "6fgGP0T9Qq4u9O2nZV43euk6QPfWS6y5VxR+QWkc4/gN7O4R6I5akFUQwz0IKsz+",
        "/vO5L9Vj9kWX3i2BwywZdLFL0+jPWd0Sl5zl1/qv1blCIrV0YKsBLg0w/jhKeclJ",
        "0LFi33I5cmD9fDG1v4V3mniPd6faHYDBgsrlG91InFwCfaMK1VAfT5sc+u3LJDGz",
        "EiZC3eX88g0A0v+mLnrlvICB1Tu3VY/wruZptQ5LwQelEwZxDdNoSQ/U/NcxqcUJ",
        "o2DMwLBl4vbCUQIDAQABoxMwETAPBgNVHRMBAf8EBTADAQH/MA0GCSqGSIb3DQEB",
        "CwUAA4IBAQC6uhYDlCJOFRPCLDxrNBauoodaq9lob57++Ncs6yl2kO9Ld/ct6L5n",
        "G6HnzcdT6dr3YbuwkKDWtc4rxkDTs1Z9alJX7qHdY7gdNJZAa/iZUTiJRYXT/cdG",
        "Vn5q6jnaKKgrSHDG85S/Y9n7h2NQwn/VzC5NKIymolby6GEDSIj3TjyvqP2eWAsg",
        "W+QP4q20BgiH5L18CXtU6aoNln0innnr/FyhfD3QT6VEmRD+mLWWHWX7Brynxz//",
        "o4aHxGB2IdSG33IiD22ya4im9qlCEHr+WEY3a8rTDllrXiQ/cdUKXmqtKX2NUKYN",
        "Mwqwf4DtxELBF4z5KXGH2ui0dY+sH4v3",
    ].joined())

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

    /// The server's own certificate, and behind it the issuer that signed it.
    ///
    /// Two certificates rather than one, so that "the leaf" and "the last certificate the
    /// server sent" are different values and a test can tell them apart. The issuer really
    /// did sign the leaf: `SecTrustEvaluateWithError` builds the chain before the decision
    /// reads it, and it drops any certificate that does not belong to the chain.
    private func chainedTrust() throws -> SecTrust {
        let der = try #require(Self.chainedDer)
        let issuerDer = try #require(Self.chainedIssuerDer)
        let leaf = try #require(SecCertificateCreateWithData(nil, der as CFData))
        let issuer = try #require(SecCertificateCreateWithData(nil, issuerDer as CFData))
        var made: SecTrust?
        let status = SecTrustCreateWithCertificates(
            [leaf, issuer] as CFArray,
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

    /// A pin holds one certificate open, not the host it sits on.
    ///
    /// The mirror of Android's `aPinBelongsToOneCertificate`, and the assertion that fails
    /// if the decision ever asks whether the host is pinned instead of whether this
    /// certificate is. A server that is re-keyed, or another certificate offered for the
    /// same host, must reach the reader as a new fingerprint to compare.
    @Test func aPinOnAnotherCertificateDoesNotOpenThisOne() throws {
        let delegate = OpdsTrustDelegate(pins: CertificatePins([Self.host: ["00:11:22"]]))
        let (disposition, credential) = delegate.decision(for: try trust(), host: Self.host)
        #expect(disposition == .cancelAuthenticationChallenge)
        #expect(credential == nil)
        #expect(delegate.takeRefusal()?.fingerprint == Self.fingerprint)
    }

    /// The fingerprint is the server's own certificate, not what stands behind it.
    ///
    /// A chain that is refused for anything but self-signing carries the leaf and then its
    /// issuers. Showing the reader an issuer's fingerprint would have them pin a whole
    /// signer, which is the widening `OpdsTrust` says must not happen.
    @Test func theFingerprintIsTheLeafAndNotItsIssuer() throws {
        let delegate = OpdsTrustDelegate(pins: CertificatePins())
        let (disposition, _) = delegate.decision(for: try chainedTrust(), host: Self.host)
        #expect(disposition == .cancelAuthenticationChallenge)
        let refusal = try #require(delegate.takeRefusal())
        #expect(refusal.fingerprint == Self.chainedFingerprint)
        #expect(refusal.subject.contains("storyarc-test-chained.invalid"))
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
