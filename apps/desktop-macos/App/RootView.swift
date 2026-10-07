import SwiftUI

enum Destination: String, CaseIterable, Identifiable {
    case home
    case library
    case downloads

    var id: Self { self }

    var title: LocalizedStringKey {
        switch self {
        case .home: "desktop.nav.home"
        case .library: "desktop.nav.library"
        case .downloads: "desktop.nav.downloads"
        }
    }

    var symbol: String {
        switch self {
        case .home: "house"
        case .library: "books.vertical"
        case .downloads: "arrow.down.circle"
        }
    }
}

struct RootView: View {
    @State private var selection: Destination? = .home

    var body: some View {
        NavigationSplitView {
            List(Destination.allCases, selection: $selection) { destination in
                Label(destination.title, systemImage: destination.symbol)
            }
            .navigationSplitViewColumnWidth(min: 180, ideal: 220)
        } detail: {
            ContentUnavailableView(
                selection?.title ?? "desktop.nav.home",
                systemImage: selection?.symbol ?? "house",
                description: Text("desktop.placeholder.empty")
            )
        }
    }
}
