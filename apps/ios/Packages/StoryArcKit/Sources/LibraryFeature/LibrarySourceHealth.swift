internal import Foundation

internal import Catalogue
internal import Kavita
internal import Persistence
internal import Smb
public import StoryArcCore

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
        let fetched = await ServerShelf.fetch(in: registry, credentials: credentials)
        serverLists = fetched.shelves.filter(\.isList)
        // `collections-and-reading-lists` offers to copy a local list onto a server, and the
        // offer has to be honest before it is taken: only a server that just answered can
        // take one, so an unreachable one leaves the offer disabled rather than failing after
        // the reader has already confirmed it.
        listCapableServers = fetched.listCapable
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
    /// library goes away, which is exactly when nobody is looking at the answer.
    ///
    /// **It does not give the requirement's other half, and this comment claimed it did.**
    /// "Retries … when the app returns to the foreground" was said to follow because
    /// "returning is what starts it again" — but a `.task` fires on *appear*, and
    /// backgrounding does not disappear a view. `LibraryView` says so itself, a few lines
    /// from where it starts this loop. The foreground trigger is `RetryTrigger`, wired
    /// through ``SourceReachability``, and it is a separate mechanism because the two
    /// occasions arrive from different places: one from a view's lifetime, one from the
    /// system's.
    ///
    /// - Parameter isReading: whether a reader has a publication open. `sources`' automatic
    ///   recovery must not "interrupt reading", and this loop ran straight through a
    ///   chapter — every 5 s, then every 10, up to every 5 minutes, for as long as anything
    ///   was away. The guard is checked **each time round** rather than once at the top,
    ///   because a reader opens a publication *while* the loop is waiting.
    func retryUnreachableSources(
        credentials: CredentialStore?,
        pins: CertificatePins,
        isReading: @escaping @MainActor () -> Bool = { false }
    ) async {
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
            // Asked after the wait, not before it: the reader who matters is the one who is
            // reading *now*, and a five-minute-old answer is the wrong one.
            guard !isReading() else { continue }
            await probeNetworkSources(credentials: credentials, pins: pins)
        }
    }

    /// One immediate probe, when the system says something changed.
    ///
    /// `sources`' *Retry policy* names two occasions beside the backoff — connectivity
    /// regained, and the app returning to the foreground. ``SourceReachability`` decides
    /// whether a trigger earns a probe; this is what happens when it does.
    func probe(on trigger: RetryTrigger, credentials: CredentialStore?, pins: CertificatePins, isReading: Bool) async {
        guard SourceReachability.shouldProbe(on: trigger, sources: registry.sources, isReading: isReading)
        else { return }
        await probeNetworkSources(credentials: credentials, pins: pins)
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
                _ = try await KavitaClient(address: page.address).connect()
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

/// The five things a source's detail screen can do to a source.
///
/// `sources`: the screen "offers actions to test the connection, refresh, clear the cache,
/// remove downloads, and remove the source". Removal already existed; the other four did
/// not, on either platform. ``SourceDiagnosis`` decides which of them a given source is
/// offered; this is what happens when one is taken. Android's `LibraryViewModel` carries
/// the same four.
///
/// The stores are built here rather than passed in, the way ``mark(_:read:)`` builds its
/// own: both are thin wrappers over `UserDefaults` and the Keychain, and threading them
/// through Settings to reach one button would be two parameters carrying nothing.
extension LibraryModel {
    /// Asks one source, now, and says so while it is asking.
    ///
    /// Marked `connecting` first. A test whose only visible effect arrives a network
    /// timeout later is a button a reader presses twice.
    ///
    /// A folder is asked of the filesystem rather than of a network: it is either readable
    /// or it is not, which is the distinction ``SourceProbe/isRemote(_:)`` draws.
    public func test(_ source: Source) async {
        guard SourceProbe.isRemote(source.kind) else {
            registry = registry.marking(source.id, as: folderState(of: source))
            return
        }
        registry = registry.marking(source.id, as: .connecting)
        let state = await reach(
            source,
            credentials: CredentialStore(),
            pins: CertificatePins(CertificatePinStore().pins())
        )
        registry = registry.marking(source.id, as: state)
    }

    /// Re-fetches what one source holds.
    ///
    /// The test first, because a refresh of a source that is not answering is a walk that
    /// finds nothing — and a walk that finds nothing is deliberately not allowed to empty
    /// the shelf. For a folder the walk is the refresh; for a server the probe is, since a
    /// server's contents are browsed rather than folded into the shelf.
    public func refresh(_ source: Source) async {
        await test(source)
        guard source.kind == .localFolder, let folder = folder(of: source) else { return }
        scan(folder)
    }

    /// Drops what is cached for one source, and nothing else.
    ///
    /// The rows go, the on-disk snapshot is rewritten without them, and the next refresh
    /// puts back whatever is still there. Downloads are untouched: `sources` lists clearing
    /// the cache and removing downloads as two actions, and a reader on a train who meant
    /// the first must not get the second.
    ///
    /// Cover *files* are not swept one by one. They live in the caches directory keyed by
    /// publication, are evicted under storage pressure, and Privacy's "Clear cache" takes
    /// the lot — so those bytes are already reachable by something the reader can press.
    public func clearCache(of source: Source) {
        let gone = Set(publications.filter { $0.sourceID == source.id }.map(\.id))
        guard !gone.isEmpty else { return }
        publications.removeAll { gone.contains($0.id) }
        for id in gone {
            covers[id] = nil
            locations[id] = nil
        }
        // Written through rather than left for the next scan. ``cacheLibrary()`` refuses to
        // replace a good snapshot with an empty one — that guard is there for a walk that
        // failed, and this is not one, so an emptied library clears the file outright.
        if publications.isEmpty { libraryCache.clear() } else { cacheLibrary() }
        cachedAt = nil
        rebuild()
    }

    /// The folder behind a source, when the source is one.
    func folder(of source: Source) -> URL? {
        folders.first { $0.lastPathComponent == source.locator }
    }

    /// Whether a folder source can still be read.
    ///
    /// A folder whose bookmark did not restore has no URL here at all, which is the same
    /// answer as one that is no longer readable: unreachable, and grey — `local-library`
    /// names an unavailable folder separately, and a red badge on a share that is simply
    /// not mounted would contradict "offline is a normal state".
    private func folderState(of source: Source) -> SourceConnectionState {
        guard let folder = folder(of: source),
              FileManager.default.fileExists(atPath: folder.path())
        else { return .unreachable(since: Date()) }
        return .connected
    }
}
