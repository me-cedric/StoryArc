import Catalogue
import Formats
import LibraryFeature
import Persistence
import StoryArcCore
import SwiftUI

extension StoryArcApp {
    /// Export and import of the whole library, over the stores this app already holds.
    ///
    /// Nil when the progress store could not be opened, which hides the two Settings rows: an
    /// archive with no progress ledger would export a library with no reading in it.
    var libraryTransfer: LibraryTransfer? {
        progress.map {
            LibraryTransfer(
                archive: LibraryArchive(progress: $0, covers: CoverOverrideStore()),
                secrets: credentials
            )
        }
    }

    /// Brings what the app holds in memory up to what an import wrote to disk.
    ///
    /// The settings, the pinned certificates the running session trusts, the sources, the shelves
    /// and the reading positions. A pin that reached the store but not `CertificatePins.app`
    /// would be ignored until the next launch, and the next pin the reader accepted would write
    /// the old set over it.
    func libraryImported(_ outcome: LibraryImportOutcome) {
        settings = settingsStore.settings()
        for (host, fingerprints) in outcome.snapshot.certificatePins {
            for fingerprint in fingerprints { CertificatePins.app.pin(fingerprint, for: host) }
        }
        Task { await library.reloadAfterImport() }
    }
}
