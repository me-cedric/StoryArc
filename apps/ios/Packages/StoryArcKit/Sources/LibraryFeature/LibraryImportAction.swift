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

extension View {
    /// Presents the picker for an import and says what happened when it did not work.
    func importingPublications(
        into model: LibraryModel,
        isPresented: Binding<Bool>
    ) -> some View {
        fileImporter(
            isPresented: isPresented,
            allowedContentTypes: ImportableTypes.all,
            allowsMultipleSelection: false
        ) { result in
            guard case let .success(urls) = result, let file = urls.first else { return }
            Task { await model.importFile(file) }
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
