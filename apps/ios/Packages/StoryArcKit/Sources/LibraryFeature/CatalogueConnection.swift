public import Foundation
public import Catalogue
internal import Kavita
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

    /// The source this connection is putting back, when it is re-authorising one.
    ///
    /// `sources` requires "a single action to re-enter credentials, pre-filled with
    /// everything except the secret". Holding the source rather than only its address is
    /// what makes the result a *replacement*: the same identifier keeps the source's place
    /// in the order, its downloads and its reading positions, where removing and re-adding
    /// — which an iOS comment used to name as the workaround — loses all three.
    public private(set) var replacing: Source?

    private let client: OpdsClient
    private let pins: CertificatePins
    private let credentials: CredentialStore?

    /// The URL that answered, kept so saving uses the address that worked rather than the
    /// one that was typed — a host that redirects to a path is common, and saving the typed
    /// form means every later request pays for the redirect again.
    private var resolved: URL?

    /// The credential that worked, held only until the source is saved.
    private var accepted: OpdsCredential?

    /// The Kavita server recognised in what the reader pasted, and what it answered with.
    ///
    /// Set only by ``connect()``, and only for an address that carries a Kavita API key.
    /// Non-nil is what makes ``source()`` produce a Kavita source instead of a catalogue.
    private var kavita: (address: KavitaAddress, identity: KavitaIdentity)?

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

    /// Seeds the sheet from a catalogue whose sign-in was refused.
    ///
    /// The address comes back, the sign-in does not. A credential the server has just
    /// rejected is not a starting point, and showing dots where one used to be would invite
    /// the reader to press Connect on the credential that failed.
    public func prefill(from source: Source) {
        replacing = source
        address = source.locator ?? ""
        user = ""
        password = ""
        token = ""
        step = .entering
    }

    /// Fetches the root feed and reports what came back.
    ///
    /// A Kavita OPDS URL never gets that far. Its path *is* the reader's full-privilege API
    /// key, so a fetch would succeed with no 401, no prompt and no secret to file — and the
    /// key-bearing URL would be written into the registry, which is preferences and is
    /// backed up in the clear. `kavita-server` asks for such a paste to configure "a native
    /// Kavita source rather than a generic OPDS source", and nothing in that sentence says
    /// which sheet it was pasted into.
    public func connect() async {
        // Forgotten before anything is asked. A reader who pasted a Kavita URL, then edited
        // the field into an ordinary catalogue and connected again would otherwise save the
        // server they had moved away from.
        kavita = nil
        switch CatalogueTarget.of(address) {
        case let .kavita(address):
            await connectKavita(address)
        case let .feed(url):
            await attempt(url, credential: accepted)
        case .unusable:
            step = .failed(String(localized: "catalogue.error.notAURL", bundle: .module, locale: .storyArc))
        }
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
        guard case let .confirmed(title) = step else { return nil }

        // What was pasted was a Kavita server, so a Kavita source is what gets saved: the
        // key goes to the secure store and the registry gets the base URL without it.
        if let kavita {
            guard let source = KavitaSource.make(
                address: kavita.address,
                identity: kavita.identity,
                credentials: credentials,
                replacing: replacing
            ) else {
                step = .failed(
                    String(localized: "catalogue.error.secretNotStored", bundle: .module, locale: .storyArc)
                )
                return nil
            }
            return source
        }

        guard let url = resolved else { return nil }

        // A URL written as `https://user:password@host/feed` is a credential in the shape of
        // an address, and `URLSession` authenticates from it — so the fetch succeeded with
        // `accepted` still nil and the password went to the registry as part of the locator.
        // It is a working secret, so it moves to the secure store and the locator loses it.
        var credential = accepted
        if credential == nil, let user = url.user, !user.isEmpty {
            credential = .basic(user: user, password: url.password ?? "")
        }

        let id = replacing?.id ?? UUID()
        var reference: String?
        if let credential {
            // Nil when the secret cannot be stored, and the step says so. A catalogue
            // whose sign-in was accepted and then dropped is a row that fails on the next
            // launch with nothing to explain why.
            let stored = replacing?.credentialReference ?? CredentialStore.reference(for: id)
            guard let credentials, credentials.save(credential.stored, for: stored) else {
                step = .failed(
                    String(localized: "catalogue.error.secretNotStored", bundle: .module, locale: .storyArc)
                )
                return nil
            }
            reference = stored
        }

        return Source(
            id: id,
            displayName: title,
            kind: .opdsCatalog,
            state: .connected,
            lastSuccessfulSync: Date(),
            credentialReference: reference,
            locator: CatalogueTarget.storableLocator(for: url)
        )
    }

    /// Adds the Kavita server that was pasted into the catalogue sheet.
    ///
    /// The same request the Kavita sheet makes, reported the same way, because it is the
    /// same server answering. What the reader sees is the account name they would have seen
    /// there, and what gets saved is a Kavita source.
    private func connectKavita(_ address: KavitaAddress) async {
        step = .connecting
        do {
            let identity = try await KavitaClient(address: address).connect()
            kavita = (address, identity)
            step = .confirmed(title: "\(identity.username) · \(address.base.host() ?? "Kavita")")
        } catch let error as KavitaError {
            step = .failed(KavitaConnection.describe(error))
        } catch {
            step = .failed(CatalogueMessages.reachability(error))
        }
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
