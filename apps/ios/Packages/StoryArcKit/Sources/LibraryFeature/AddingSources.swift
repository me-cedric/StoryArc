internal import SwiftUI

internal import Catalogue
internal import Persistence
internal import StoryArcCore

/// Which of the three source sheets a reader asked for, if any.
///
/// One optional rather than the three booleans this replaced, for ``LocalPick``'s reason:
/// three booleans can express "two sheets at once", which is not a state either screen has.
enum AddedSource: String, Identifiable, CaseIterable {
    /// An OPDS catalogue.
    case catalogue
    /// A Kavita server.
    case kavita
    /// An SMB share.
    case share

    var id: String { rawValue }
}

/// The sheets that add a configured source, and the connections behind them.
///
/// `sources` asks the empty state to name the four kinds of place, so both destinations that
/// draw ``EmptyLibraryView`` need all four actions. This is the machinery behind three of
/// them, declared once: Home and the shelf would otherwise each carry the same state, the
/// same connections and the same sheets, and `LibraryView.swift` sits at its line cap and
/// could not hold a second copy in any case.
///
/// Built like ``SwiftUI/View/pickingLocalLibrary(into:pick:)``: the caller owns one optional
/// saying which question it asked, and this owns the presentation that answers it.
private struct AddingSources: ViewModifier {
    let model: LibraryModel

    @Binding var sheet: AddedSource?

    /// Held by the view rather than made per presentation, so a reader who dismisses a sheet
    /// mid-sign-in and reopens it finds what they typed still there.
    @State private var smb = SmbConnection(credentials: CredentialStore())
    @State private var kavita = KavitaConnection(credentials: CredentialStore())
    @State private var catalogue: CatalogueConnection

    init(model: LibraryModel, pins: CertificatePins, sheet: Binding<AddedSource?>) {
        self.model = model
        _sheet = sheet
        _catalogue = State(
            initialValue: CatalogueConnection(
                pins: pins,
                credentials: CredentialStore(),
                pinStore: CertificatePinStore()
            )
        )
    }

    func body(content: Content) -> some View {
        content.sheet(item: $sheet) { asked in
            switch asked {
            case .catalogue: CatalogueSheet(connection: catalogue) { model.add($0) }
            case .kavita: KavitaSheet(connection: kavita) { model.add($0) }
            case .share: SmbSheet(connection: smb) { model.add($0) }
            }
        }
    }
}

extension View {
    /// Presents whichever source sheet the reader asked for.
    ///
    /// The pin set is passed in rather than loaded here because one object has to serve both
    /// halves: a certificate accepted while adding a catalogue must still be accepted when
    /// that catalogue's covers load.
    func addingSources(
        to model: LibraryModel,
        pins: CertificatePins,
        sheet: Binding<AddedSource?>
    ) -> some View {
        modifier(AddingSources(model: model, pins: pins, sheet: sheet))
    }
}
