internal import SwiftUI

internal import Catalogue
internal import DesignSystem
internal import StoryArcCore

/// What the library draws once there is something to draw: the grid, its empty
/// states, and the offer to put the same query to a server.
///
/// Split from `LibraryView.swift` when that file passed the length the linter allows.
/// The scene, its state and the toolbar stayed there.
extension LibraryView {

    /// The publications this surface is about.
    ///
    /// A projection over the one library rather than a second store: `library-browsing`'s
    /// availability axis is *can I read this with no network*, and the answer is already
    /// on the device in the form of where each publication's bytes are. Everything the app
    /// can open from a file URL qualifies — a folder the reader picked as much as a
    /// download the app fetched — because that is the promise the destination makes, and
    /// a reader on a plane does not care which of the two put the file there.
    var shown: [Publication] {
        switch surface {
        case .onDevice: model.visible.filter { model.location(of: $0)?.isFileURL == true }
        // The shelf's primary axis, applied here rather than inside the query: it narrows
        // what this surface lists and nothing else, which is what keeps it from becoming the
        // mode `library-browsing` removed origin for being.
        case .shelf: model.visible.filter { availability.keeps(model.location(of: $0)) }
        case .search: model.visible
        }
    }

    /// Whether a publication can be opened right now. The rule itself lives beside the
    /// availability axis it belongs to; this is the shelf asking it.
    func isReadableNow(_ publication: Publication) -> Bool {
        LibraryAvailability.isReadableNow(
            publication,
            location: model.location(of: publication),
            registry: model.registry
        )
    }

    /// How this shelf divides, or nothing when it is short enough to take in at a glance.
    ///
    /// Never while a search is running: the results are already grouped by why they matched,
    /// and a second set of headings cutting across the first would be two answers to one
    /// question.
    var sections: [LibrarySection] {
        guard surface == .shelf, model.matchGroups.isEmpty, shown.count > LibrarySections.threshold
        else { return [] }
        return LibrarySections.divide(shown, by: model.query.sort)
    }

    /// Whether it is the device axis that is hiding the library, rather than a filter.
    ///
    /// Only when the library *has* something to show at the wider setting: a reader whose
    /// filters would empty the shelf either way is not helped by being told to look
    /// elsewhere first.
    var isNarrowedToDevice: Bool {
        surface == .shelf && availability == .onThisDevice && !model.visible.isEmpty
    }

    /// The one action that puts the shelf back, or `nil` when it is already as wide as it
    /// goes. The device axis is undone before the library filter, because it is the one the
    /// reader set most recently and the one that hides the most.
    var widening: (() -> Void)? {
        if isNarrowedToDevice { return { availability = .everywhere } }
        if model.query.scope == .allSources { return nil }
        return { model.widenToAllSources() }

    /// Asks every source again, and walks the folders again.
    ///
    /// `sources` already retries on a backoff while the library is on screen; this is the
    /// reader asking now, because a state with no way out of it is a dead end however
    /// patient the timer behind it is.
    func retrySources() {
        Task {
            await model.probeNetworkSources(credentials: credentials, pins: pins)
            await model.rescan()
        }
    }

    var content: some View {
        Group {
            KavitaServerSearchOffer(registry: model.registry, query: model.query) { source in
                serverSearch = model.query.search
                browsing = source.id
            }
            if !shown.isEmpty {
                if model.layout == .grid, !sections.isEmpty {
                    // `library-browsing`: a long shelf "is divided by series where a
                    // publication declares one, and otherwise by the active sort key, with
                    // headings that stay visible while their section is on screen".
                    SectionedShelf(
                        sections: sections,
                        model: model,
                        onOpen: open,
                        selection: selection.isActive ? selection.ids : nil,
                        onToggle: { selection.toggle($0.id) },
                        isReadableNow: isReadableNow
                    )
                } else if model.layout == .grid {
                    CoverGrid(
                        publications: shown,
                        // Empty, always. What the reader is in the middle of is the hero of
                        // the home destination now, and a second copy of it above the shelf
                        // was the app's only editorial moment being hidden the moment a
                        // search or a selection started — which is exactly when a reader is
                        // looking hardest.
                        continueReading: [],
                        // `library-browsing`: while a search is running, results are
                        // "grouped by match kind". Empty when nothing is typed, and then
                        // the shelf is one run of covers.
                        groups: model.matchGroups,
                        model: model,
                        onOpen: open,
                        selection: selection.isActive ? selection.ids : nil,
                        onToggle: { selection.toggle($0.id) }
                    )
                } else {
                    CoverList(
                        publications: shown,
                        groups: model.matchGroups,
                        model: model,
                        onOpen: open,
                        selection: selection.isActive ? selection.ids : nil,
                        onToggle: { selection.toggle($0.id) }
                    )
                }
            } else if surface == .onDevice {
                // Nothing to narrow and nothing to scan: this destination holds what the
                // device holds, so the only honest thing to say is that it holds nothing
                // yet. `navigation-shell` requires it to stay present and selectable
                // whatever the sources are doing, so there is no error branch here.
                OnDeviceEmpty()
            } else if !model.publications.isEmpty {
                // A library that is not empty but looks it. `library-browsing`
                // forbids showing that silently: say what is narrowing it and
                // offer one action to undo.
                NarrowedToNothing(
                    query: model.query,
                    clear: {
                        model.clearFilters()
                        model.query.search = ""
                    },
                    scopeName: model.registry.name(of: model.query.scope.sourceID),
                    // The device axis wins the sentence when it is the thing narrowing the
                    // shelf: a reader who asked for what works on a plane and got nothing
                    // needs to be told that, not that their filters match nothing.
                    isNarrowedToDevice: isNarrowedToDevice,
                    // Offered only when there is somewhere wider to go.
                    widen: widening
                )
            } else if case .scanning = model.scanState {
                ScanningView(state: model.scanState)
            } else if model.registry.sources.isEmpty {
                EmptyLibraryView(
                    openComic: { isImporting = true },
                    addFolder: { isPickingFolder = true },
                    addCatalogue: { isAddingCatalogue = true },
                    addKavita: { isAddingKavita = true },
                    addShare: { isAddingShare = true }
                )
            } else {
                // Sources are configured and the shelf is bare. This used to be
                // ``SourceList`` — connection states and a coloured dot each, which is
                // configuration on the browse path, and §6.2 of the design direction puts
                // configuration in Settings and nowhere else. Settings › Your libraries
                // still holds it, removal and all.
                LibraryAway(
                    isEverythingAway: LibraryAway.everythingAway(in: model.registry),
                    retry: retrySources,
                    openComic: { isImporting = true }
                )
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(theme.palette.surfaceCanvas)
        // `native-experience`: "floating chrome uses Liquid Glass, with scroll edge
        // effects at content boundaries". Soft rather than the default, because what
        // passes under this app's chrome is artwork — a hard cut across a cover looks
        // like a rendering fault, and a soft one reads as depth.
        .scrollEdgeEffectStyle(.soft, for: .all)
    }
}

/// Nothing is on this device yet.
///
/// Its own small view rather than a bare `Text` so the destination has a centred, quiet
/// state at the weight the rest of the empty states use, and so the slice that turns this
/// destination into the full offline shelf has one place to grow it from.
struct OnDeviceEmpty: View {
    @Environment(\.theme) private var theme

    var body: some View {
        Text("library.empty.title", bundle: .module)
            .textRole(.title3)
            .foregroundStyle(theme.palette.textSecondary)
            .frame(maxWidth: .infinity, maxHeight: .infinity)
    }
}
