internal import Foundation

/// What a launch puts back: the folders the reader picked, and the publications another
/// app handed them.
///
/// Both come out of the same bookmark store, because on iOS both are the same thing — a
/// security-scoped grant that outlives the process. What they are *not* is the same kind of
/// place, and treating them as one is what broke this twice over. A handed-over file was
/// appended to `folders`, so the library registered a local-folder source named after the
/// comic and walked a regular file, which lists nothing: an empty shelf named after the
/// reader's own book. And because each folder started its own scan, and starting a scan
/// cancelled the running one, that file — restored last — cancelled the walk of the library
/// the reader had actually picked.
///
/// Split out of ``LibraryModel`` for the same reason ``LibrarySources`` and
/// ``LibraryScanning`` were: the file is at the length the linter allows, and a restore is
/// a seam that was already there.
extension LibraryModel {
    /// Re-opens what a previous launch remembered, and scans it.
    ///
    /// `local-library`: a picked folder is reachable again "after a device restart without
    /// asking again", and a publication handed over by another app is remembered "once and
    /// unobtrusively". Called once, when the library first appears.
    public func restoreFolders() {
        guard folders.isEmpty else { return }
        restoreCachedLibrary()
        guard let bookmarks else {
            scan(documentsFolder)
            return
        }

        let restored = bookmarks.restore()
        unavailableFolders = restored.stale.map(\.name)
        for folder in restored.folders {
            folders.append(folder)
            register(folder)
        }
        startWatching()

        // The remembered files first. They are one archive each, so they cost nothing next
        // to a folder walk, and putting them at the head means the book the reader most
        // recently opened is on the shelf before the walking starts.
        //
        // The Documents folder only when there is no picked folder at all — it is not a
        // library the reader chose, it is where a file copied in through Files lands, and a
        // remembered file does not stand in for it.
        let places = folders.isEmpty ? [documentsFolder] : folders
        scan(restored.files + places)
    }
}
