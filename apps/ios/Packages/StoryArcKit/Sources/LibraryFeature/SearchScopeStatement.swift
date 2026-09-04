internal import SwiftUI

internal import DesignSystem

/// What the search screen is about to search, stated as the control that changes it.
///
/// `library-browsing`: "**WHEN** the search screen is open **THEN** it states whether it is
/// searching everything or only what is on the device **AND** a user can narrow it to what is
/// on the device, and widen it again, without leaving the screen." Both halves in one control,
/// because a `Picker` naming both choices is what makes the current one *stated* rather than
/// merely set.
///
/// **Its own type because the requirement says "when the search screen is open", and the
/// results are the search screen.** It lived inside ``SearchAtRest`` as a private property, so
/// the scope was stated on the screen a reader sees before typing and nowhere on the one they
/// read afterwards — and the field's own `.searchScopes` bar is no substitute, because the
/// platform draws that only while the field is *active*. A reader looking at two results and
/// three sources that did not answer had nothing on screen saying which half of their library
/// had been asked. `ios-search-results.png`, 2026-09-02.
///
/// One type rather than two copies: the shape is `.segmented` on both, which is what the
/// field's own bar draws, and one idea must not look like two controls depending on which
/// state of the screen a reader is in.
struct SearchScopeStatement: View {
    @Binding var scope: LibraryAvailability

    var body: some View {
        Picker(selection: $scope) {
            ForEach(LibraryAvailability.allCases, id: \.self) { option in
                Text(option.titleKey, bundle: .module).tag(option)
            }
        } label: {
            Text("library.scope.all", bundle: .module)
        }
        .pickerStyle(.segmented)
        .labelsHidden()
    }
}
