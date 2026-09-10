public import SwiftUI

public import StoryArcCore

/// A series, as a value a navigation stack can carry.
///
/// By name rather than by id, because a series has no id of its own: it is what a set of
/// publications agree they belong to, whichever source each of them came through. Android's
/// `Screen.SeriesShelf` carries the same thing for the same reason.
public struct SeriesRoute: Hashable, Sendable {
    public let name: String

    public init(name: String) {
        self.name = name
    }
}

extension View {
    /// Registers the screen a series opens into.
    ///
    /// Beside ``publicationDetail(model:onOpen:onListen:onGone:)`` and for the same reason:
    /// one registration per stack, so a cell can be a link without knowing what the
    /// destination is made of.
    public func seriesShelf(model: LibraryModel) -> some View {
        navigationDestination(for: SeriesRoute.self) { route in
            SeriesShelfView(name: route.name, model: model)
        }
    }
}

/// How a cell in the Library split opens a series, where a value link cannot.
///
/// The shelf column declares no destination of its own, so a ``NavigationLink`` there goes
/// nowhere — the same reason ``OpenPublicationRoute`` exists, and the reason a series cell
/// silently opened the wrong screen until a simulator was pointed at it: the cell fell
/// through to the publication branch and showed the issue leading the series.
public struct OpenSeriesRoute {
    private let open: (SeriesRoute) -> Void

    public init(_ open: @escaping (SeriesRoute) -> Void) {
        self.open = open
    }

    public func callAsFunction(_ route: SeriesRoute) {
        open(route)
    }
}

extension EnvironmentValues {
    /// The way a series cell in the Library split opens, or nil where a value link works.
    @Entry public var openSeriesRoute: OpenSeriesRoute?
}
