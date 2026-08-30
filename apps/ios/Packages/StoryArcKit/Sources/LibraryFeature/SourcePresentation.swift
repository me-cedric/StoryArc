internal import SwiftUI

internal import DesignSystem
internal import StoryArcCore

/// Presentation for the domain's source types. Kept out of `StoryArcCore` so the
/// domain stays free of SwiftUI — the same split Android keeps between its
/// `core:model` and `core:designsystem` modules.
extension SourceKind {
    /// SF Symbols only. DESIGN.md §8: no custom icon set, except where the
    /// platform genuinely offers nothing — `opdsCatalog` is the closest fit
    /// available and is revisited if a better symbol ships.
    var symbolName: String {
        switch self {
        case .localFolder: "folder"
        case .networkShare: "externaldrive.connected.to.line.below"
        case .opdsCatalog: "dot.radiowaves.up.forward"
        case .kavitaServer: "server.rack"
        }
    }

    var titleKey: LocalizedStringKey {
        switch self {
        case .localFolder: "source.kind.localFolder.title"
        case .networkShare: "source.kind.networkShare.title"
        case .opdsCatalog: "source.kind.opdsCatalog.title"
        case .kavitaServer: "source.kind.kavitaServer.title"
        }
    }

    var explanationKey: LocalizedStringKey {
        switch self {
        case .localFolder: "source.kind.localFolder.explanation"
        case .networkShare: "source.kind.networkShare.explanation"
        case .opdsCatalog: "source.kind.opdsCatalog.explanation"
        case .kavitaServer: "source.kind.kavitaServer.explanation"
        }
    }
}

extension SourceConnectionState {
    var statusKey: LocalizedStringKey {
        switch self {
        case .connected: "source.state.connected"
        case .connecting: "source.state.connecting"
        case .unreachable: "source.state.unreachable"
        case .unauthorized: "source.state.unauthorized"
        }
    }

    /// Only `unauthorized` is red. An unreachable source is grey, because
    /// `sources` treats offline as a normal state rather than a failure.
    func indicatorColor(_ palette: Palette) -> Color {
        switch self {
        case .connected: StoryArcColor.Status.success
        case .connecting: palette.textTertiary
        case .unreachable: StoryArcColor.Status.offline
        case .unauthorized: StoryArcColor.Status.danger
        }
    }
}

/// How the browsing enums are named on screen.
///
/// The enums themselves live in the domain and carry no strings: `StoryArcCore`
/// has no bundle and no business holding UI copy. Naming them is presentation,
/// so it lives beside the other presentation.
extension LibrarySort {
    var titleKey: LocalizedStringKey {
        switch self {
        case .title: "library.sort.title"
        case .series: "library.sort.series"
        case .lastRead: "library.sort.lastRead"
        case .progress: "library.sort.progress"
        case .year: "library.sort.year"
        }
    }
}

extension ReadState {
    var titleKey: LocalizedStringKey {
        switch self {
        case .unread: "library.readState.unread"
        case .inProgress: "library.readState.inProgress"
        case .finished: "library.readState.finished"
        }
    }
}

extension MatchKind {
    /// The heading over a group of search results.
    ///
    /// Plural, because a heading names a set: "Series" over one result still reads
    /// correctly, where "Serie" over four would not.
    var titleKey: LocalizedStringKey {
        switch self {
        case .series: "library.match.series"
        case .publication: "library.match.publication"
        case .person: "library.match.person"
        case .tag: "library.match.tag"
        }
    }
}
