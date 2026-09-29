import Foundation

import Kavita
import Persistence
import StoryArcCore

/// Writes down what the server already reports, for a chapter this device has never opened.
///
/// The rule is ``KavitaExchange/openSeed(pagesRead:of:existing:reflowable:)``, outside the
/// views, so a test can call it without a store. The record is stamped as synchronised: the
/// position came from the server, so the server already holds it, and the next pull must
/// not read it as a change made on this device.
func seedKavitaOpen(
    _ publication: Publication,
    pagesRead: Int,
    of pages: Int,
    into progress: ProgressStore?
) async {
    guard let progress else { return }
    let existing = try? await progress.progress(for: publication.identity)
    guard let position = KavitaExchange.openSeed(
        pagesRead: pagesRead,
        of: pages,
        existing: existing,
        reflowable: publication.isReflowable
    ) else { return }
    let seeded = ReadingProgress(identity: publication.identity, position: position, updatedAt: Date())
    try? await progress.save(KavitaExchange.settled(seeded))
}
