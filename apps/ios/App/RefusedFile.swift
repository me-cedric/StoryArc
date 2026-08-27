import Foundation

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

    var id: String { name }

    /// Every format the app reads, in the order `publication-formats` lists them.
    ///
    /// Written here rather than derived from the format enum on purpose: the enum holds
    /// what the app can *detect*, and 7-Zip is detected and refused. A list built from it
    /// would promise CB7.
    private static let supported = "CBZ, CBR, CBT, EPUB, PDF"

    var message: String {
        if let detected {
            return "\(name) is a \(detected) file, which StoryArc does not read. "
                + "It reads \(Self.supported)."
        }
        return "\(name) is not a file StoryArc recognises. It reads \(Self.supported)."
    }
}
