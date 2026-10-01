internal import SwiftUI

internal import StoryArcCore

/// What a bulk offer to a server's own list could not hold.
///
/// Carries the publications alongside the server's name because the alert's local-list
/// button needs the whole refused subset, not just the count `BulkActionBar` drew before
/// task 12.4 — the single-cover alert (``View/refusedByServer(_:model:publication:)``) has
/// offered a local list since task 12.1; a bulk refusal offered Cancel alone until this.
struct BulkRefused {
    var server: String?
    var publications: [Publication] = []

    var isPresented: Bool { server != nil }

    mutating func clear() {
        server = nil
        publications = []
    }
}

extension View {
    /// The alert a bulk refusal raises, with the button that puts the whole refused
    /// selection in a new local list instead.
    ///
    /// Its own file rather than inline in `BulkActionBar`, which the alert's own length
    /// had pushed past the 400-line cap this project enforces.
    func refusedBulkByServer(_ refused: Binding<BulkRefused>, model: LibraryModel) -> some View {
        alert(
            Text("shelves.serverOnly.title", bundle: .module),
            isPresented: Binding(
                get: { refused.wrappedValue.isPresented },
                set: { if !$0 { refused.wrappedValue.clear() } }
            )
        ) {
            if !refused.wrappedValue.publications.isEmpty {
                Button {
                    // The offer the spec asks for: a local list can hold anything.
                    model.create(
                        list: String(localized: "shelves.new.list", bundle: .module, locale: .storyArc)
                    )
                    if let made = model.shelves.lists.last {
                        model.append(refused.wrappedValue.publications.map(\.id), toList: made.id)
                    }
                    refused.wrappedValue.clear()
                } label: {
                    Text("shelves.serverOnly.local", bundle: .module)
                }
            }
            Button(role: .cancel) { refused.wrappedValue.clear() } label: {
                Text("shelves.cancel", bundle: .module)
            }
        } message: {
            Text("shelves.serverOnly.body \(refused.wrappedValue.server ?? "")", bundle: .module)
        }
    }
}
