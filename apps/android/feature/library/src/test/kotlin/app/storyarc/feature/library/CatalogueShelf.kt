package app.storyarc.feature.library

import android.app.Application
import android.graphics.Bitmap
import androidx.test.core.app.ApplicationProvider
import app.storyarc.core.model.Publication
import app.storyarc.core.model.PublicationFormat
import app.storyarc.core.model.ReadState
import app.storyarc.core.snapshots.Fixtures

/**
 * The library the catalogue draws: a dozen titles, with covers, authors and a series, so a
 * snapshot shows a shelf as a reader would see one. No file and no network.
 */
internal object CatalogueShelf {
    private val titles = listOf(
        Triple("Harbour Lights", "Mara Quill", PublicationFormat.CBZ),
        Triple("Cinder Season", "Tomas Reyes", PublicationFormat.EPUB),
        Triple("Tin Kingdom", "Ada Okoye", PublicationFormat.CBZ),
        Triple("The Long Tide", "Ines Varga", PublicationFormat.PDF),
        Triple("Paper Moons", "Jun Park", PublicationFormat.CBZ),
        Triple("A Winter Ledger", "Oskar Lind", PublicationFormat.EPUB),
        Triple("Brass and Bone", "Mara Quill", PublicationFormat.CBZ),
        Triple("Salt Road", "Ada Okoye", PublicationFormat.CBZ),
        Triple("Night Ferry", "Ines Varga", PublicationFormat.EPUB),
        Triple("Glass Orchard", "Jun Park", PublicationFormat.CBZ),
        Triple("Low Orbit", "Tomas Reyes", PublicationFormat.CBZ),
        Triple("Velvet Static", "Oskar Lind", PublicationFormat.PDF),
    )

    val publications: List<Publication> = titles.mapIndexed { index, (title, author, format) ->
        Fixtures.publication(
            title = title,
            format = format,
            authors = listOf(author),
            pageCount = 24 + index * 8,
            summary = "A fixture summary for $title. It is long enough to run onto a second line " +
                "of the publication page, and short enough to read at a glance.",
            publisher = "Fixture Press",
            year = 2014 + index,
        )
    }

    fun cover(publication: Publication): Bitmap = Fixtures.cover(publication.displayTitle.length + publication.displayTitle.first().code)

    fun entry(
        publication: Publication,
        fraction: Double = 0.0,
        pagesRemaining: Int? = null,
        state: ReadState = if (fraction > 0.0) ReadState.IN_PROGRESS else ReadState.UNREAD,
    ) = HomeEntry(
        publication = publication,
        isReadableNow = true,
        pagesRemaining = pagesRemaining ?: if (fraction > 0.0) 18 else null,
        fraction = fraction,
        state = state,
    )

    private val extraTitles = listOf(
        "Amber Gate", "Bright Hollow", "Copper Hymn", "Dust Cartographer", "Emberfall", "Fathom Street",
        "Granite Sky", "Hollow Crown", "Iron Meadow", "Juniper Wake", "Kite Season", "Lantern Row",
        "Marrow Sea", "Northern Lamp", "Opal Frontier", "Quiet Harbour", "Rook and Ruin", "Stone Archive",
    )

    /** Thirty titles, past the point where the library divides into letters and draws an index. */
    val longShelf: List<Publication> = publications + extraTitles.mapIndexed { index, title ->
        Fixtures.publication(
            title = title,
            authors = listOf("Fixture Author"),
            pageCount = 32 + index,
            year = 2000 + index,
        )
    }

    /** A view model with no store behind it, holding [shelf] and a cover for each of them. */
    fun viewModel(shelf: List<Publication> = publications, withCovers: Boolean = true): LibraryViewModel {
        val model = LibraryViewModel(ApplicationProvider.getApplicationContext<Application>())
        model._publications.value = shelf
        if (withCovers) shelf.forEach { model.covers[it.id] = cover(it) }
        model.rebuild()
        return model
    }
}
