public import Foundation
public import Catalogue
public import Kavita
public import Persistence
public import StoryArcCore

/// Adding a Kavita server, from a URL and a key to a saved source.
///
/// `kavita-server`: the app "authenticates, confirms the server version and the account
/// name, and saves the source". Confirmation before saving, for the reason the catalogue
/// gives — a reader who mistyped finds out here rather than by browsing an empty library.
@Observable
@MainActor
public final class KavitaConnection {
    public enum Step: Equatable, Sendable {
        case entering
        case connecting
        case confirmed(KavitaIdentity)
        case failed(String)
    }

    public private(set) var step: Step = .entering

    /// The address, as typed. A pasted OPDS URL is accepted here too.
    public var address = ""
    public var apiKey = ""

    /// Whether the reader has typed enough for a request to be worth making.
    ///
    /// The key is not required when the address is a Kavita OPDS URL, because that URL
    /// already contains one.
    public var canConnect: Bool {
        guard step != .connecting else { return false }
        if KavitaAddress.fromOpds(address) != nil { return true }
        return !address.trimmingCharacters(in: .whitespaces).isEmpty
            && !apiKey.trimmingCharacters(in: .whitespaces).isEmpty
    }

    /// Whether the address the reader pasted already carries a key.
    ///
    /// Read by the sheet, which hides the key field when it does: asking for something the
    /// reader has already given is how a form makes someone feel they typed it wrong.
    public var addressCarriesKey: Bool { KavitaAddress.fromOpds(address) != nil }

    /// The source this connection is putting back, when it is re-authorising one.
    ///
    /// `sources` requires "a single action to re-enter credentials, pre-filled with
    /// everything except the secret". Holding the source rather than only its address is
    /// what makes the result a *replacement*: the same identifier keeps the source's place
    /// in the order, its downloads and its reading positions, where removing and re-adding
    /// — which an iOS comment used to name as the workaround — loses all three.
    public private(set) var replacing: Source?

    private let credentials: CredentialStore?
    private var resolved: KavitaAddress?

    /// No `pins`. It used to take a set and forward it to ``KavitaClient``, which stored it
    /// and never read it — so the call chain read as though the reader's own certificate
    /// decisions were in force here when nothing consulted them. Rank 15 of the 30 August
    /// security review: a parameter that claims a defence it does not provide is worse than
    /// an absent one, because the next change "fixes" the delegate rather than wiring it.
    /// A Kavita server needs a certificate the system already trusts, and the sources
    /// screen says so.
    public init(credentials: CredentialStore? = nil) {
        self.credentials = credentials
    }

    /// Seeds the sheet from a source whose key was refused.
    ///
    /// The address comes back, the key does not. A key the server has just rejected is not
    /// a starting point, and showing dots where one used to be would invite the reader to
    /// press Connect on the credential that failed.
    public func prefill(from source: Source) {
        replacing = source
        address = source.locator ?? ""
        apiKey = ""
        step = .entering
    }

    public func connect() async {
        // A pasted OPDS URL wins, because it is unambiguous: it names the server and the
        // key together, and a key typed beside it could only disagree.
        guard let address = KavitaAddress.fromOpds(self.address)
            ?? KavitaAddress.from(base: self.address, apiKey: apiKey)
        else {
            step = .failed(String(localized: "kavita.error.notAnAddress", bundle: .module, locale: .storyArc))
            return
        }

        step = .connecting
        do {
            let identity = try await KavitaClient(address: address).connect()
            resolved = address
            step = .confirmed(identity)
        } catch let error as KavitaError {
            step = .failed(Self.describe(error))
        } catch {
            step = .failed(CatalogueMessages.reachability(error))
        }
    }

    /// The source to save, once the server has confirmed who it is.
    ///
    /// Nil when the key cannot be stored, and the step says so. A Kavita source without its
    /// key is a row that will fail on the next launch with nothing to explain why — saving
    /// one would be the app quietly forgetting a password the reader watched it accept.
    public func source() -> Source? {
        guard case let .confirmed(identity) = step, let address = resolved else { return nil }

        guard let source = KavitaSource.make(
            address: address,
            identity: identity,
            credentials: credentials,
            replacing: replacing
        ) else {
            step = .failed(String(localized: "kavita.error.keyNotStored", bundle: .module, locale: .storyArc))
            return nil
        }
        return source
    }

    public func reset() {
        step = .entering
    }

    /// Internal rather than private: the catalogue sheet reports the same errors, because a
    /// Kavita OPDS URL pasted there is answered by Kavita.
    static func describe(_ error: KavitaError) -> String {
        switch error {
        case let .serverTooOld(found, required):
            String(
                format: String(localized: "kavita.error.tooOld", bundle: .module, locale: .storyArc),
                found.description,
                required.description
            )
        case .keyRejected:
            String(localized: "kavita.error.keyRejected", bundle: .module, locale: .storyArc)
        case .badAddress:
            String(localized: "kavita.error.notAnAddress", bundle: .module, locale: .storyArc)
        case .unexpectedResponse:
            String(localized: "kavita.error.notKavita", bundle: .module, locale: .storyArc)
        case let .http(status):
            String(
                format: String(localized: "catalogue.error.http", bundle: .module, locale: .storyArc),
                status,
                HTTPURLResponse.localizedString(forStatusCode: status)
            )
        }
    }
}

/// A confirmed Kavita server, written down as a source.
///
/// Shared by the Kavita sheet and by the catalogue sheet — which diverts a pasted Kavita
/// OPDS URL here rather than letting the key that URL carries become an OPDS locator. One
/// function rather than two, because the two would drift and only one of them would be the
/// one that keeps the key out of preferences.
///
/// The key is filed under the source's *own* identifier. It was not: the reference was
/// minted from one UUID and the source returned with another, so every iOS Kavita secret
/// was stored under a name nothing would ever look up again — including its own removal.
enum KavitaSource {
    /// Nil when the key cannot be stored. A Kavita source without its key is a row that
    /// fails on the next launch with nothing to explain why, so the caller says so instead
    /// of saving one.
    /// `replacing` is the source being re-authorised, when there is one. Its identifier and
    /// its credential reference are reused, so the new key lands under the name the registry
    /// already holds and the source keeps everything filed under that identifier.
    static func make(
        address: KavitaAddress,
        identity: KavitaIdentity,
        credentials: CredentialStore?,
        replacing: Source? = nil
    ) -> Source? {
        let id = replacing?.id ?? UUID()
        let reference = replacing?.credentialReference ?? CredentialStore.reference(for: id)
        guard let credentials, credentials.save(address.apiKey, for: reference) else { return nil }

        return Source(
            id: id,
            // The account name, not the host. A reader with two accounts on one server
            // needs to tell them apart, and the host is the same for both.
            displayName: "\(identity.username) · \(address.base.host() ?? "Kavita")",
            kind: .kavitaServer,
            state: .connected,
            lastSuccessfulSync: Date(),
            credentialReference: reference,
            // The base, which is the address with the key taken out of it. `sources`
            // forbids a secret reaching preferences, and the registry is preferences.
            locator: address.base.absoluteString
        )
    }
}

/// What is needed to open a saved Kavita source.
///
/// `Identifiable` on the source's own id, so a screen that offers a choice of servers — the
/// one `collections-and-reading-lists` needs before it can copy a list onto one — can list
/// them without inventing a second identity for each.
public struct KavitaPage: Sendable, Identifiable {
    public let id: String
    public let title: String
    public let address: KavitaAddress

    /// Nil when the source is not a Kavita server, has no address, or has lost its key —
    /// the last of which is what `unauthorized` means and needs the reader to fix.
    public init?(source: Source, credentials: CredentialStore?) {
        guard source.kind == .kavitaServer,
              let locator = source.locator,
              let base = URL(string: locator),
              let reference = source.credentialReference,
              let key = credentials?.secret(for: reference)
        else { return nil }

        id = source.id.uuidString
        title = source.displayName
        address = KavitaAddress(base: base, apiKey: key)
    }
}
