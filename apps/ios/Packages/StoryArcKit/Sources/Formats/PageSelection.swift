public import Foundation

// What `ComicInfo.xml` says about individual pages, and how much of it to believe.
//
// Free functions rather than methods because every container needs the same rules and
// only some of them carry the metadata that can change the answer. Keeping them in one
// place is what stops a CBZ and a CBT disagreeing about which page a reader sees first.
//
// Their own file only because `ComicArchive.swift` reached the 400-line cap; Android
// keeps the same two objects at the foot of `ComicArchive.kt`.

/// Resolves which page is the cover.
public enum CoverSelection {
    /// The designated cover, when one is designated and exists; otherwise the
    /// first page in reading order.
    ///
    /// A designated index that falls outside the page list is ignored rather than
    /// clamped. `ComicInfo`'s indices count *archive* entries, and an archive whose
    /// non-page entries were filtered out can leave a stale index behind — showing
    /// an arbitrary middle page would look like a bug in the reader rather than in
    /// the file.
    public static func cover(of pages: [PageEntry], designated index: Int?) -> PageEntry? {
        guard let index, index >= 0, index < pages.count else { return pages.first }
        return pages[index]
    }
}
