internal import Foundation

internal import Catalogue
internal import Kavita
internal import Persistence
internal import Smb
internal import StoryArcCore

/// Whether a source is actually there, and when to ask again.
///
/// Its own file rather than a tail on `LibrarySources.swift`, which had grown past the
/// length the linter allows — and because health is one subject: the asking, and the
/// schedule for asking again. Android keeps the same pair in `SourceHealth.kt`.
///
/// The *decisions* are not here. ``SourceProbe`` in `StoryArcCore` holds the backoff and
/// the meaning of a status code, where a test can reach them without a network.
extension LibraryModel {
    /// Answers the question every network source asks on launch.
    ///
    /// `sources` requires a source's health to be shown. State is never persisted, so a
    /// catalogue or a server loads as `connecting` and stays there unless something asks --
    /// which nothing did, so every network source a reader added read "Connecting…" for
    /// ever, whether it was reachable or not.
    ///
    /// One request each, on appearance. Cheap enough to repeat and honest enough to trust:
    /// a state older than the last time the library was on screen is a claim about the past.
    func probeNetworkSources(credentials: CredentialStore?, pins: CertificatePins) async {
        for source in registry.sources
        where source.kind == .opdsCatalog
            || source.kind == .kavitaServer
            || source.kind == .networkShare {
            let state = await reach(source, credentials: credentials, pins: pins)
            registry = registry.marking(source.id, as: state)
        }
        // Asked at the same moment, because it is the same question — what does this server
        // have — and the add-to menu cannot fetch it for itself without opening a connection
        // every time a reader long-presses a cover.
        serverLists = await ServerShelf.all(in: registry, credentials: credentials)
            .filter(\.isList)
    }

    /// Keeps asking, while any source is still away.
    ///
    /// `sources` asks for more than one probe: an unreachable source is retried "with
    /// exponential backoff starting at 5 seconds and capping at 5 minutes", and an
    /// unreachable source that comes back is reconnected "without user action". A single
    /// probe on appearance satisfies neither — a reader whose Wi-Fi returns while they are
    /// looking at the library would watch it say `Connecting` until they left the screen
    /// and came back.
    ///
    /// The schedule is ``SourceProbe/delay(afterFailures:)``, which is tested without a
    /// network. This is only the loop.
    ///
    /// Cancellation is the caller's: run from a `task` modifier, this stops when the
    /// library goes away, which is exactly when nobody is looking at the answer. That also
    /// gives the requirement's other half — the retry "when the app returns to the
    /// foreground" — because returning is what starts it again.
    func retryUnreachableSources(credentials: CredentialStore?, pins: CertificatePins) async {
        var failures = 0
        while !Task.isCancelled {
            guard registry.sources.contains(where: { if case .unreachable = $0.state { true } else { false } })
            else { return }

            failures += 1
            do {
                try await Task.sleep(for: .seconds(SourceProbe.delay(afterFailures: failures)))
            } catch {
                return // Cancelled mid-wait: the library is gone.
            }
            await probeNetworkSources(credentials: credentials, pins: pins)
        }
    }

    /// Adds a publication to one of a server's reading lists.
    ///
    /// Returns false when the publication did not come from that server. `kavita-server`
    /// requires the app to explain that "a server list can only contain that server's
    /// publications" rather than silently doing nothing or silently doing the wrong thing.
    @discardableResult
    func add(_ publication: Publication, toServerList list: ServerShelf) async -> Bool {
        let kavita = KavitaProgressStore()
        guard let origin = kavita.origin(of: publication.id),
              origin.sourceId == list.server.id
        else { return false }

        let credentials = CredentialStore()
        let address = registry.sources
            .first { $0.id.uuidString == origin.sourceId }
            .flatMap { KavitaPage(source: $0, credentials: credentials)?.address }
        await KavitaSync.append(list.id, for: origin, to: address, in: kavita)
        return true
    }

    private func reach(
        _ source: Source,
        credentials: CredentialStore?,
        pins: CertificatePins
    ) async -> SourceConnectionState {
        if let page = SmbPage(source: source, credentials: credentials) {
            do {
                _ = try await SmbClient(address: page.address).connect()
                return .connected
            } catch SmbError.authenticationRejected {
                return .unauthorized(reason: String(localized: "source.state.unauthorized",
                                                    bundle: .module, locale: .storyArc))
            } catch {
                return .unreachable(since: Date())
            }
        }

        if let page = KavitaPage(source: source, credentials: credentials) {
            do {
                _ = try await KavitaClient(address: page.address, pins: pins).connect()
                return .connected
            } catch KavitaError.keyRejected {
                return .unauthorized(reason: String(localized: "source.state.unauthorized",
                                                    bundle: .module, locale: .storyArc))
            } catch {
                return .unreachable(since: Date())
            }
        }

        if let page = CataloguePage(source: source, credentials: credentials) {
            do {
                _ = try await OpdsClient(pins: pins).feed(at: page.url, credential: page.credential)
                return .connected
            } catch let error as OpdsError {
                if case .unauthorized = error {
                    return .unauthorized(reason: String(localized: "source.state.unauthorized",
                                                        bundle: .module, locale: .storyArc))
                }
                return .unreachable(since: Date())
            } catch {
                return .unreachable(since: Date())
            }
        }

        // Neither page could be built, so the secret this source needs has gone.
        return .unauthorized(reason: String(localized: "source.state.unauthorized",
                                            bundle: .module, locale: .storyArc))
    }
}
