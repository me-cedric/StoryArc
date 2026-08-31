import SwiftUI

/// A file the system handed over that StoryArc will not open, and what to say about it.
///
/// `local-library` is specific about the wording: the app "names the format it detected
/// and states which formats it supports, rather than reporting a generic failure". A
/// reader who picked the wrong file in another app has no way to tell that from a broken
/// StoryArc unless StoryArc says which it is.
struct RefusedFile: Identifiable, Sendable {
    let name: String
    /// The format the sniffer recognised, or `nil` when it recognised nothing.
    let detected: String?
    /// Whether the file is behind a store's content protection.
    ///
    /// Its own flag rather than a `detected` string, because `publication-formats` requires
    /// this refusal to be "distinct from an unsupported container, because the format itself
    /// is supported and this particular file is locked" — and the two sentences below say
    /// genuinely different things. Listing the supported formats under this one would be
    /// wrong twice over: the format *is* supported, and there is nothing to convert to.
    var isProtected = false

    var id: String { name }

    /// Every format the app reads, in the order `publication-formats` lists them.
    ///
    /// Written here rather than derived from the format enum on purpose: the enum holds
    /// what the app can *detect*, and 7-Zip is detected and refused. A list built from it
    /// would promise CB7.
    private static let supported = "CBZ, CBR, CBT, EPUB, PDF, M4B and other audiobooks"

    var message: String {
        // No key, no account, no activation code, and no suggestion of a way around it.
        // StoryArc does not implement, circumvent or advise on removing a content
        // protection, and a message that hinted at one would be the first step to a field
        // that asks for it.
        if isProtected {
            return "\(name) is protected by its store's content protection, "
                + "so StoryArc cannot open it."
        }
        if let detected {
            return "\(name) is a \(detected) file, which StoryArc does not read. "
                + "It reads \(Self.supported)."
        }
        return "\(name) is not a file StoryArc recognises. It reads \(Self.supported)."
    }
}

extension View {
    /// Says why a handed-over file was refused.
    ///
    /// Here rather than in `StoryArcApp` so the wording and the alert that carries it sit
    /// together — and because the app file is at the length the linter allows.
    func refusing(_ file: Binding<RefusedFile?>) -> some View {
        alert(
            Text(verbatim: "Cannot open this file"),
            isPresented: Binding(get: { file.wrappedValue != nil }, set: { if !$0 { file.wrappedValue = nil } })
        ) {
            Button(role: .cancel) { file.wrappedValue = nil } label: { Text(verbatim: "OK") }
        } message: {
            Text(file.wrappedValue?.message ?? "")
        }
    }
}
