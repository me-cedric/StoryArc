internal import Foundation

internal import Catalogue
internal import Persistence
internal import StoryArcCore

/// One search, across everything the reader has, answered at whatever speed each part of it
/// can manage.
///
/// **What this is for, in one sentence: the reader asks once.** Before it, the library's
/// field filtered the local index and never asked a server; a catalogue's search lived
/// inside the catalogue; and a Kavita server's search was reached from a field on the Kavita
/// screens. Three fields, three answers, and a reader who had to know which of their books
/// lived where before they could look for one.
///
/// The shape of the answer follows from one line of `library-browsing`: "locally held
/// results render immediately and remote results fill in as they arrive". So:
///
/// - **The local answer is not awaited.** It is computed from the index the model already
///   holds and is on screen in the same frame the reader typed in.
/// - **Nothing is awaited *together*.** Each library is asked in its own task and each
///   answer is folded in as it lands, so one slow server delays itself and nothing else.
/// - **A failure is not an error state.** It is a line under the results naming that
///   library once, with a way to ask again. The rows already on screen are untouched, per
///   the requirement's own words: "never replaced by an error".
///
/// The merge itself is ``SearchListing`` — pure, mirrored, and where the ranking, the
/// labelling and the no-reordering promise are actually kept. This type is the part that has
/// a clock and a network in it, and deliberately has nothing else.
@MainActor
@Observable
final class LibrarySearch {

    /// Everything known about the question currently being asked.
    private(set) var listing = SearchListing(term: "")

    /// The fan-out for the term now in the field. Cancelled when the term changes.
    private var remote: Task<Void, Never>?

    /// How long a reader has to stop typing before a server is troubled.
    ///
    /// `library-browsing` asks for results that "update as they type, debounced". The local
    /// half needs no debounce — it is a filter over an array in memory. This is for the
    /// other half: a term typed at speed would otherwise put eight questions to a server and
    /// throw seven of the answers away.
    private static let settleBeforeAsking = Duration.milliseconds(350)

    init() {}

    /// Whether there is a question on the table at all.
    var isSearching: Bool { !listing.term.isEmpty }

    /// The reader typed.
    ///
    /// Local rows are in `listing` by the time this returns. The rest arrives later, or does
    /// not arrive, and either way the screen already has something on it.
    func ask(
        _ raw: String,
        in model: LibraryModel,
        credentials: CredentialStore,
        pins: CertificatePins
    ) {
        remote?.cancel()
        remote = nil

        let term = raw.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !term.isEmpty else {
            listing = SearchListing(term: "")
            return
        }

        let asked = model.registry.sources.filter(RemoteSearch.answers)
        // Whether a row names its library is ``SearchListing``'s own rule, decided from
        // what the device matched and who is being asked — not from the registry's count,
        // which answers a different question for the shelf.
        listing = SearchListing(
            term: term,
            local: FoundRow.held(in: model.matchGroups, registry: model.registry),
            asking: asked.map { $0.id.uuidString }
        )

        guard !asked.isEmpty else { return }
        remote = Task { [weak self] in
            try? await Task.sleep(for: Self.settleBeforeAsking)
            guard !Task.isCancelled else { return }
            await self?.askEveryone(asked, term: term, credentials: credentials, pins: pins)
        }
    }

    /// The reader gave up on the search.
    func clear() {
        remote?.cancel()
        remote = nil
        listing = SearchListing(term: "")
    }

    /// The reader asked a library that went quiet to try once more.
    ///
    /// `library-browsing`: the library that could not answer is named "with a way to try it
    /// again". One library, not all of them — a reader whose home server is off does not
    /// want their other three asked a second time to find that out.
    func retry(
        _ sourceID: String,
        in model: LibraryModel,
        credentials: CredentialStore,
        pins: CertificatePins
    ) {
        guard let source = model.registry.sources.first(where: { $0.id.uuidString == sourceID })
        else { return }
        let term = listing.term
        listing = listing.askingAgain(sourceID)
        Task { [weak self] in
            await self?.ask(source, term: term, credentials: credentials, pins: pins)
        }
    }

    /// Every library asked at once, each answer folded in the moment it lands.
    ///
    /// A task group rather than a loop of `await`s: a loop would make the second server wait
    /// for the first, and a reader with one slow server would experience all of them as slow.
    private func askEveryone(
        _ sources: [Source],
        term: String,
        credentials: CredentialStore,
        pins: CertificatePins
    ) async {
        await withTaskGroup(of: Void.self) { group in
            for source in sources {
                group.addTask { [weak self] in
                    await self?.ask(source, term: term, credentials: credentials, pins: pins)
                }
            }
        }
    }

    /// One library asked, and its answer folded in — unless the reader has moved on.
    private func ask(
        _ source: Source,
        term: String,
        credentials: CredentialStore,
        pins: CertificatePins
    ) async {
        let id = source.id.uuidString
        do {
            let rows = try await RemoteSearch.rows(
                from: source,
                term: term,
                credentials: credentials,
                pins: pins
            )
            // The reader has typed on, so this answer is to a question nobody is asking any
            // more. Dropped rather than merged: rows for "bon" appearing under a field that
            // says "bone" is the one way a late answer *can* still surprise someone.
            guard listing.term == term else { return }
            listing = listing.answered(id, with: FoundRow.away(rows, from: source))
        } catch {
            guard listing.term == term else { return }
            listing = listing.couldNotAnswer(id, named: source.displayName)
        }
    }
}
