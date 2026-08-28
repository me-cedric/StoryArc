public import Foundation
internal import CryptoKit
internal import Synchronization

/// Which server certificates the reader has explicitly accepted.
///
/// `opds-catalog`: a catalogue presenting a certificate the system does not trust is
/// refused "by default", and the app "offers to pin that specific certificate after
/// showing its fingerprint and an explicit warning". So there are two states, not one —
/// untrusted and refused, or untrusted and named by the reader — and this holds the
/// second.
///
/// One certificate, one host. A pin is not "trust this server for anything"; it is "this
/// exact certificate, on this exact host". A pin that widened to a whole CA would let a
/// self-hosted server vouch for the rest of the internet.
public final class CertificatePins: Sendable {
    /// SHA-256 of the leaf certificate's DER, per host.
    private let pinned: Mutex<[String: Set<String>]>

    public init(_ initial: [String: Set<String>] = [:]) {
        pinned = Mutex(initial)
    }

    /// Everything pinned, for a store to write.
    public var all: [String: Set<String>] {
        pinned.withLock { $0 }
    }

    /// Whether this host has accepted this fingerprint.
    public func accepts(_ fingerprint: String, from host: String) -> Bool {
        pinned.withLock { $0[host]?.contains(fingerprint) == true }
    }

    /// Records an acceptance. Only ever called after a reader has seen the fingerprint.
    public func pin(_ fingerprint: String, for host: String) {
        pinned.withLock { _ = $0[host, default: []].insert(fingerprint) }
    }

    /// Forgets every pin for a host. Called when its source is removed.
    public func forget(_ host: String) {
        pinned.withLock { $0[host] = nil }
    }
}

/// A certificate the system would not vouch for, described so a reader can decide.
public struct UntrustedCertificate: Sendable, Equatable {
    public let host: String

    /// SHA-256 of the DER, in the colon-separated hex every other tool prints. Shown to
    /// the reader, because "do you trust this server" is not a question anyone can answer
    /// and "does this fingerprint match the one your server printed" is.
    public let fingerprint: String

    public let subject: String
    public let notValidAfter: Date?

    public init(host: String, fingerprint: String, subject: String, notValidAfter: Date?) {
        self.host = host
        self.fingerprint = fingerprint
        self.subject = subject
        self.notValidAfter = notValidAfter
    }
}

/// Decides what to do with a server's certificate.
///
/// Split from the client so the rule can be read on its own. The rule is: the system
/// decides, and the reader can overrule it only for one certificate they have seen.
public final class OpdsTrustDelegate: NSObject, URLSessionDelegate, Sendable {
    private let pins: CertificatePins

    /// The last certificate refused, so the caller can offer to pin it.
    ///
    /// A refusal reaches the caller as a `URLError`, which carries no room for this. Held
    /// here rather than thrown because `URLSession` decides the challenge on its own queue
    /// and the throw happens somewhere else entirely.
    private let refused: Mutex<UntrustedCertificate?> = Mutex(nil)

    public init(pins: CertificatePins) {
        self.pins = pins
    }

    /// The certificate refused since this was last asked, and clears it.
    func takeRefusal() -> UntrustedCertificate? {
        refused.withLock { value in
            defer { value = nil }
            return value
        }
    }

    public func urlSession(
        _ session: URLSession,
        didReceive challenge: URLAuthenticationChallenge
    ) async -> (URLSession.AuthChallengeDisposition, URLCredential?) {
        guard challenge.protectionSpace.authenticationMethod == NSURLAuthenticationMethodServerTrust,
              let trust = challenge.protectionSpace.serverTrust
        else { return (.performDefaultHandling, nil) }

        // The system first, always. A certificate that evaluates is not the reader's
        // problem, and asking them about one would teach them to tap through the question
        // that matters.
        if SecTrustEvaluateWithError(trust, nil) {
            return (.useCredential, URLCredential(trust: trust))
        }

        let host = challenge.protectionSpace.host
        guard let leaf = Self.leaf(of: trust) else {
            return (.cancelAuthenticationChallenge, nil)
        }
        let fingerprint = Self.fingerprint(of: leaf)

        if pins.accepts(fingerprint, from: host) {
            return (.useCredential, URLCredential(trust: trust))
        }

        // Refused, and described. `opds-catalog` requires the explanation before the offer.
        refused.withLock {
            $0 = UntrustedCertificate(
                host: host,
                fingerprint: fingerprint,
                subject: Self.subject(of: leaf) ?? host,
                notValidAfter: Self.expiry(of: leaf)
            )
        }
        return (.cancelAuthenticationChallenge, nil)
    }

    private static func leaf(of trust: SecTrust) -> SecCertificate? {
        (SecTrustCopyCertificateChain(trust) as? [SecCertificate])?.first
    }

    /// SHA-256 of the DER, colon-separated uppercase hex.
    ///
    /// The same form `openssl x509 -fingerprint -sha256` prints, so a reader can compare
    /// what the app shows against what their server told them without transcribing either.
    private static func fingerprint(of certificate: SecCertificate) -> String {
        let digest = SHA256.hash(data: SecCertificateCopyData(certificate) as Data)
        return digest.map { String(format: "%02X", $0) }.joined(separator: ":")
    }

    private static func subject(of certificate: SecCertificate) -> String? {
        SecCertificateCopySubjectSummary(certificate) as String?
    }

    /// When the certificate stops being valid — on macOS only.
    ///
    /// iOS exposes no public API for a certificate's validity dates.
    /// `SecCertificateCopyValues` is macOS-only, and the alternative is hand-parsing the
    /// DER validity field. The fingerprint is what the spec requires a reader to compare
    /// and the subject is what tells them which server they are looking at; an expiry date
    /// is a nicety, and hand-rolled X.509 parsing to get one is not a trade worth making.
    private static func expiry(of certificate: SecCertificate) -> Date? {
        #if os(macOS)
        guard let values = SecCertificateCopyValues(
            certificate,
            [kSecOIDX509V1ValidityNotAfter] as CFArray,
            nil
        ) as? [String: Any],
            let entry = values[kSecOIDX509V1ValidityNotAfter as String] as? [String: Any],
            let seconds = entry[kSecPropertyKeyValue as String] as? Double
        else { return nil }
        // Counted from 2001, which is what the Security framework returns here.
        return Date(timeIntervalSinceReferenceDate: seconds)
        #else
        nil
        #endif
    }
}
