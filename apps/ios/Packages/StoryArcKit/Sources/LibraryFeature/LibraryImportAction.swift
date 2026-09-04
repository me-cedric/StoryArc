internal import SwiftUI

internal import StoryArcCore
internal import UniformTypeIdentifiers

/// The way a reader asks for a publication to be copied into the app.
///
/// `local-library` gives imported copies a requirement of their own, separate from opening
/// a file the system hands over: an import is for keeping, and the copy has to outlive the
/// original being moved or deleted. So this is a deliberate action in the same menu as
/// adding a folder, not something that happens to a file on its way past.
///
/// A file of its own because ``LibraryView`` sits at its line cap, and a picker with its
/// own file types and its own refusal is a whole small subject.
struct ImportPublicationButton: View {
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            Label {
                Text("library.import", bundle: .module)
            } icon: {
                Image(systemName: "square.and.arrow.down")
            }
        }
    }
}

/// Which of the two local pickers a reader asked for.
///
/// **One value where there were two booleans, and that is the whole fix.** `isPickingFolder`
/// and `isImporting` each drove a `fileImporter` of its own, both applied to
/// ``LibraryView``'s body — and SwiftUI presents only the **last** such modifier applied,
/// silently. The folder picker was declared first, so *Add a folder* opened nothing on a
/// device while *Open a file* directly below it worked; see ``LocalPickerTests`` for how that
/// was isolated. Two booleans can express "both at once", which is not a state the screen has
/// or wants; one optional cannot.
enum LocalPick: String, Identifiable, CaseIterable {
    /// A folder the reader keeps, watched where it lies.
    case folder
    /// A file handed over to be copied into storage the app owns.
    case file

    var id: String { rawValue }

    /// What the system browser is allowed to offer.
    ///
    /// The two sets are disjoint on purpose: a picker that offered both would let a reader
    /// answer "add a folder" with a comic, and the two land in different places —
    /// ``LibraryModel/addFolder(_:)`` remembers where a folder *is*, while
    /// ``LibraryModel/importFile(_:)`` copies bytes the app then owns.
    var contentTypes: [UTType] {
        switch self {
        case .folder: [.folder]
        case .file: ImportableTypes.all
        }
    }
}

extension View {
    /// Presents the one document picker this screen has, and says what happened when an
    /// import did not work.
    ///
    /// One `fileImporter`, told what to offer by ``LocalPick``, rather than one per kind.
    /// Ordering is not the fix: an order is a thing the next edit re-shuffles without knowing
    /// it was load-bearing, and no gate in this repository can see a presentation that was
    /// dropped. A single presentation cannot be shadowed by a sibling that does not exist.
    func pickingLocalLibrary(
        into model: LibraryModel,
        pick: Binding<LocalPick?>
    ) -> some View {
        fileImporter(
            isPresented: Binding(
                get: { pick.wrappedValue != nil },
                set: { if !$0 { pick.wrappedValue = nil } }
            ),
            // Read in the same body pass that turns the presentation on, because the caller
            // sets the pick and the flag with one assignment. The fallback is never the value
            // the picker opens with — it is what the modifier reads while nothing is up.
            allowedContentTypes: pick.wrappedValue?.contentTypes ?? ImportableTypes.all,
            allowsMultipleSelection: false
        ) { result in
            // Read before the sheet's dismissal clears it: `onCompletion` runs while the
            // pick is still set, and routing on it is what keeps one presentation honest
            // about which of the two questions it asked.
            let asked = pick.wrappedValue
            guard case let .success(urls) = result, let url = urls.first else { return }
            switch asked {
            case .folder: model.addFolder(url)
            // `.file`, and also a completion that somehow outlived the pick: copying is the
            // safe answer of the two, since it never adopts a directory as a library.
            case .file, nil: Task { await model.importFile(url) }
            }
        }
        .alert(
            Text("library.import.failed.title", bundle: .module),
            isPresented: Binding(
                get: { model.importFailure != nil },
                set: { if !$0 { model.importFailure = nil } }
            ),
            presenting: model.importFailure
        ) { _ in
            Button(role: .cancel) { model.importFailure = nil } label: {
                Text("library.import.dismiss", bundle: .module)
            }
        } message: { name in
            Text("library.import.failed \(name)", bundle: .module)
        }
    }
}

/// Which files the picker offers.
///
/// The four comic containers are declared in the app's `Info.plist`, which is also what
/// makes StoryArc appear in the system's own "Open with" list — one declaration serving
/// both halves of `local-library`. Looked up by identifier rather than hard-coded as a
/// filename filter, so the picker greys out what it cannot open instead of letting a
/// reader choose a spreadsheet and be refused afterwards.
enum ImportableTypes {
    static let all: [UTType] = {
        let declared = ["app.storyarc.cbz", "app.storyarc.cbr", "app.storyarc.cbt"]
            .compactMap(UTType.init(_:))
        // CB7 is absent on purpose: `publication-formats` leaves 7-Zip undecoded, and
        // offering to import a file the reader could not then open would be a promise the
        // app cannot keep.
        return declared + [.epub, .pdf]
    }()
}
