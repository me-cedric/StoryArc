package app.storyarc.core.model

/** A device after a sync merge, and what the merge has to tell the reader. */
data class LibrarySyncMerged(
    val snapshot: LibrarySnapshot,
    /** Positions where both devices had moved. Each is shown once, naming both positions. */
    val conflicts: List<ProgressPull.Conflict> = emptyList(),
    /** Hosts that gained an accepted certificate, and the source that names each. */
    val certificatePinsAdded: List<CertificatePinNotice> = emptyList(),
    /** Sources, by name, that the reader has to sign in to on this device. */
    val sourcesNeedingSignIn: List<String> = emptyList(),
)

/**
 * A sync document merged into this device.
 *
 * `library-sync` *Two devices that both moved*. Unlike an import, nothing here simply takes the
 * document's side: a position goes by ADR-0006 ([ProgressPull]), a shelf's members are a union,
 * a deletion travels, and a setting or a theme field goes to the device that changed it last.
 * Pure, over a [LibrarySnapshot], so two devices can be reconciled in a test with no store.
 * iOS's `LibrarySyncMerge` applies the same rules in the same order.
 */
object LibrarySyncMerge {

    fun merging(document: LibraryDocument, local: LibrarySnapshot, device: String): LibrarySyncMerged {
        val shelves = ShelfStamps.merging(local.shelves, local.removedShelves, document.library)
        val settings = SettingsStamps.merging(
            local.settings, local.settingsChangedAt, document.library.settings, device,
        )
        val themes = ThemeStamps.merging(
            local.themes, local.themesChangedAt, document.library.readingThemes, device,
        )
        val (progress, conflicts) = mergingProgress(document, local)
        return LibrarySyncMerged(
            snapshot = local.copy(
                sources = LibraryImport.mergingSources(document, local.sources),
                certificatePins = LibraryImport.mergingPins(document, local.certificatePins),
                shelves = shelves.shelves,
                removedShelves = shelves.removed,
                pinnedShelves = PinnedShelves(
                    (local.pinnedShelves.tokens + document.library.pinnedShelves)
                        .mapNotNull(ShelfPin::of)
                        .toSet(),
                ),
                settings = settings.value,
                settingsChangedAt = settings.changedAt,
                themes = themes.value,
                themesChangedAt = themes.changedAt,
                progress = progress,
                covers = local.covers + LibraryImport.coversArriving(document, local),
            ),
            conflicts = conflicts,
            certificatePinsAdded = LibraryImport.pinsArriving(document, local),
            sourcesNeedingSignIn = LibraryImport.signInsNeeded(document, local),
        )
    }

    /**
     * Positions by ADR-0006, then each one the document now agrees on stamped as synchronised.
     *
     * `library-sync` task 3.2. The stamp is [ReadingProgress.syncedPosition], as
     * `KavitaExchange.settled` writes it for a server. Without it, a position that moved on the
     * other device after this sync would meet a stale watermark and raise a conflict that did
     * not happen. A Kavita position is neither merged nor stamped: its watermark is Kavita's.
     */
    private fun mergingProgress(document: LibraryDocument, local: LibrarySnapshot):
        Pair<List<ReadingProgress>, List<ProgressPull.Conflict>> {
        val arriving = LibraryImport.readableProgress(document)
            .filterNot { local.ownedByKavita(it.identity) }
        val pull = ProgressPull.merging(arriving) { identity ->
            local.progress.firstOrNull { it.identity.matches(identity) }
        }
        val merged = local.progress.toMutableList()
        for (record in pull.toSave) {
            val existing = merged.indexOfFirst { it.identity.matches(record.identity) }
            if (existing >= 0) merged[existing] = record else merged += record
        }
        val settled = merged.map {
            if (local.ownedByKavita(it.identity)) it else it.copy(syncedPosition = it.position)
        }
        return settled to pull.conflicts
    }
}
