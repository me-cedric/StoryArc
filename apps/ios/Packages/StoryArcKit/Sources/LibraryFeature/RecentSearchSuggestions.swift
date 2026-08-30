internal import SwiftUI

/// What the reader searched for lately, under an open search field.
///
/// `library-browsing`: "when a reader opens search, recent queries are offered, and can be
/// cleared". Offered only while nothing has been typed — once there is a term, the results
/// below the field are the better answer, and a list of old searches sitting on top of them
/// would hide what was just found.
///
/// Its own file because it was one of four views this module declared and mounted nowhere:
/// nine string keys shipped in four languages behind controls no reader could reach.
/// ``LibraryView`` hands it to `.searchSuggestions` on the search surface.
struct RecentSearchSuggestions: View {
    let model: LibraryModel

    var body: some View {
        if model.query.search.trimmingCharacters(in: .whitespaces).isEmpty,
           !model.recentSearches.isEmpty {
            Section {
                ForEach(model.recentSearches.terms, id: \.self) { term in
                    // `searchCompletion` puts the term in the field, which runs the search:
                    // a recent query is a shortcut to the search, not to whatever it found
                    // last time.
                    Label {
                        Text(term)
                    } icon: {
                        Image(systemName: "clock.arrow.circlepath")
                    }
                    .searchCompletion(term)
                }

                Button(role: .destructive) {
                    model.clearRecentSearches()
                } label: {
                    Text("library.search.recent.clear", bundle: .module)
                }
            } header: {
                Text("library.search.recent", bundle: .module)
            }
        }
    }
}
