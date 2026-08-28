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

    private let pins: CertificatePins
    private let credentials: CredentialStore?
    private var resolved: KavitaAddress?

    public init(pins: CertificatePins = CertificatePins(), credentials: CredentialStore? = nil) {
        self.pins = pins
        self.credentials = credentials
    }

    public func connect() async {
        // A pasted OPDS URL wins, because it is unambiguous: it names the server and the
        // key together, and a key typed beside it could only disagree.
        guard let address = KavitaAddress.fromOpds(self.address)
            ?? KavitaAddress.from(base: self.address, apiKey: apiKey)
        else {
            step = .failed(String(localized: "kavita.error.notAnAddress", bundle: .module))
            return
        }

        step = .connecting
        do {
            let identity = try await KavitaClient(address: address, pins: pins).connect()
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

        let id = UUID()
        let stored = CredentialStore.reference(for: id)
        guard let credentials, credentials.save(address.apiKey, for: stored) else {
            step = .failed(String(localized: "kavita.error.keyNotStored", bundle: .module))
            return nil
        }
        let reference = stored

        return Source(
            // The account name, not the host. A reader with two accounts on one server
            // needs to tell them apart, and the host is the same for both.
            displayName: "\(identity.username) · \(address.base.host() ?? "Kavita")",
            kind: .kavitaServer,
            state: .connected,
            lastSuccessfulSync: Date(),
            credentialReference: reference,
            locator: address.base.absoluteString
        )
    }

    public func reset() {
        step = .entering
    }

    private static func describe(_ error: KavitaError) -> String {
        switch error {
        case let .serverTooOld(found, required):
            String(
                format: String(localized: "kavita.error.tooOld", bundle: .module),
                found.description,
                required.description
            )
        case .keyRejected:
            String(localized: "kavita.error.keyRejected", bundle: .module)
        case .badAddress:
            String(localized: "kavita.error.notAnAddress", bundle: .module)
        case .unexpectedResponse:
            String(localized: "kavita.error.notKavita", bundle: .module)
        case let .http(status):
            String(
                format: String(localized: "catalogue.error.http", bundle: .module),
                status,
                HTTPURLResponse.localizedString(forStatusCode: status)
            )
        }
    }
}

/// What is needed to open a saved Kavita source.
public struct KavitaPage: Sendable {
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

        title = source.displayName
        address = KavitaAddress(base: base, apiKey: key)
    }
}
