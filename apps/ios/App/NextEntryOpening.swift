import LibraryFeature
import StoryArcCore
import SwiftUI

/// Opens the entry a reader took from an end-of-publication offer, when it has no file yet.
///
/// `collections-and-reading-lists` tasks 7.3 and 7.14: the next entry of a server reading
/// list has no file until the list fetches it, so taking that offer fetches it the way
/// `KavitaListView` fetches a row. A failed fetch is said, because an offer that does nothing
/// when taken tells the reader nothing. Android's `AppHost.openEntry` is the same rule.
extension StoryArcApp {
    func openFetched(_ publication: Publication) async {
        switch await ServerListContext.open(publication, seeding: progress) {
        case let .opened(next, url): open(next, at: url)
        case let .failed(reason): nextEntryFailure = reason
        case nil: break
        }
    }
}

extension View {
    /// The alert a failed fetch shows, over the reader whose offer was taken.
    func nextEntryFailure(_ failure: Binding<String?>) -> some View {
        alert(
            Text(verbatim: failure.wrappedValue ?? ""),
            isPresented: Binding(get: { failure.wrappedValue != nil }, set: { if !$0 { failure.wrappedValue = nil } })
        ) {
            Button(role: .cancel) { failure.wrappedValue = nil } label: { Text("open.in.dismiss") }
        }
    }
}
