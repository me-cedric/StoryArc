public import Foundation
public import Catalogue
public import Persistence
public import StoryArcCore

/// Adding a catalogue, from a URL to a saved source.
///
/// `opds-catalog`'s first scenario: the app "fetches the root feed, detects the OPDS
/// version, and shows the catalogue title as confirmation before saving". Confirmation
/// before saving is the point — a reader who mistyped a host should find out here, not by
/// browsing an empty library later.
///
/// Every branch the spec names is a step, so none of them can be reached by accident: a
/// 401 asks for credentials, an untrusted certificate shows its fingerprint, and anything
/// that is not a feed says what it was.
@Observable
@MainActor
public final class CatalogueConnection {
    /// Where the reader is in the flow.
    public enum Step: Equatable, Sendable {
        /// Waiting for a URL.
        case entering

        /// A request is out.
        case connecting

        /// The server asked who is calling.
        case askingCredentials(scheme: OpdsError.AuthenticationScheme?)

        /// The server's certificate is not one the system vouches for.
        case untrusted(UntrustedCertificate)

        /// The root feed came back, and this is what it calls itself.
        case confirmed(title: String)

        /// Something else happened, said plainly.
        case failed(String)
    }

    public private(set) var step: Step = .entering

    /// The address, as typed. Trimmed and completed only when a request is made, so what
    /// the reader sees is what they wrote.
    public var address = ""

    public var user = ""
    public var password = ""
    public var token = ""

    /// Whether the reader has typed enough for a request to be worth making.
    public var canConnect: Bool {
        !address.trimmingCharacters(in: .whitespaces).isEmpty && step != .connecting
    }

    private let client: OpdsClient
    private let pins: CertificatePins
    private let credentials: CredentialStore?

    /// The URL that answered, kept so saving uses the address that worked rather than the
    /// one that was typed — a host that redirects to a path is common, and saving the typed
    /// form means every later request pays for the redirect again.
    private var resolved: URL?

    /// The credential that worked, held only until the source is saved.
    private var accepted: OpdsCredential?

    private let pinStore: CertificatePinStore?

    public init(
        pins: CertificatePins = CertificatePins(),
        credentials: CredentialStore? = nil,
        pinStore: CertificatePinStore? = nil
    ) {
        self.pins = pins
        self.credentials = credentials
        self.pinStore = pinStore
        client = OpdsClient(pins: pins)
    }

    /// Fetches the root feed and reports what came back.
    public func connect() async {
        guard let url = OpdsDocument.address(from: address) else {
            step = .failed(String(localized: "catalogue.error.notAURL", bundle: .module))
            return
        }
        await attempt(url, credential: accepted)
    }

    /// Tries again with what the reader just typed into the credential prompt.
    public func submitCredentials() async {
        guard case let .askingCredentials(scheme) = step, let url = resolved
            ?? OpdsDocument.address(from: address)
        else { return }

        let credential: OpdsCredential = switch scheme {
        case .bearer: .bearer(token: token)
        // Basic when the server said Basic, and Basic when it said nothing: a server with
        // no challenge that still refuses is almost always Basic, and the reader can see
        // which fields they were given.
        case .basic, nil: .basic(user: user, password: password)
        }
        await attempt(url, credential: credential)
    }

    /// Accepts one certificate, then tries again.
    ///
    /// Only reachable from ``Step/untrusted(_:)``, which is the step that shows the
    /// fingerprint. `opds-catalog` requires the warning before the offer, and the step is
    /// what makes that ordering structural rather than remembered.
    public func trustCertificate() async {
        guard case let .untrusted(certificate) = step, let url = resolved
            ?? OpdsDocument.address(from: address)
        else { return }
        pins.pin(certificate.fingerprint, for: certificate.host)
        // Written now rather than when the source is saved. A reader who accepts a
        // certificate and then abandons the flow has still made that decision, and asking
        // again next time teaches them to tap through the warning.
        pinStore?.save(pins.all)
        await attempt(url, credential: accepted)
    }

    /// The source to save, once the catalogue has confirmed its own name.
    ///
    /// Nil before then, which is what stops an unconfirmed catalogue from being saved.
    /// The secret goes to the platform secure store and its reference to the registry —
    /// `sources` forbids the secret itself reaching the registry.
    public func source() -> Source? {
        guard case let .confirmed(title) = step, let url = resolved else { return nil }

        let id = UUID()
        var reference: String?
        if let accepted, let credentials {
            let stored = CredentialStore.reference(for: id)
            reference = credentials.save(accepted.stored, for: stored) ? stored : nil
        }

        return Source(
            id: id,
            displayName: title,
            kind: .opdsCatalog,
            state: .connected,
            lastSuccessfulSync: Date(),
            credentialReference: reference,
            locator: url.absoluteString
        )
    }

    private func attempt(_ url: URL, credential: OpdsCredential?) async {
        step = .connecting
        do {
            let feed = try await client.feed(at: url, credential: credential)
            resolved = url
            accepted = credential
            // A feed with no title still connected. Named by its host rather than left
            // blank: `sources` requires the name to appear "everywhere the source is
            // referenced", and a blank one reads as a missing word.
            step = .confirmed(title: feed.title.isEmpty ? (url.host() ?? url.absoluteString) : feed.title)
        } catch let refusal as OpdsRefusal {
            switch refusal {
            case let .untrusted(certificate):
                resolved = url
                step = .untrusted(certificate)
            }
        } catch let error as OpdsError {
            resolved = url
            step = Self.step(for: error)
        } catch {
            step = .failed(CatalogueMessages.reachability(error))
        }
    }

    private static func step(for error: OpdsError) -> Step {
        if case let .unauthorized(scheme) = error { return .askingCredentials(scheme: scheme) }
        return .failed(CatalogueMessages.describe(error))
    }
}
