package app.storyarc.navigation

import app.storyarc.core.model.Publication
import app.storyarc.core.model.Source
import app.storyarc.feature.library.CataloguePage
import app.storyarc.feature.library.KavitaLevel
import app.storyarc.feature.library.KavitaPage
import app.storyarc.feature.library.ServerShelf
import app.storyarc.feature.library.SmbPage
import app.storyarc.core.catalogue.OpdsEntry
import java.util.UUID

/**
 * The three places the app can be.
 *
 * `navigation-shell`: "exactly three destinations — a home surface, the whole library, and
 * everything readable on this device", and the app "SHALL NOT add, remove or reorder a
 * destination in response to anything the reader configures". An `enum` rather than a list
 * built from the source registry is how that promise is kept by construction: there is no
 * expression anywhere that could produce a fourth.
 *
 * Search is deliberately absent. Material ranks a search bar above a search destination and
 * only permits the destination for an app whose primary action *is* searching; StoryArc's
 * is browsing, so search is a field at the top of Home and the library. iOS diverges here
 * on purpose — see the divergence register in the design direction.
 *
 * Carries no label and no icon: what a destination *is* belongs to the app, what it looks
 * like belongs to the shell that draws it. Keeping the resource identifier and the vector
 * out of here is also what lets the whole navigation model be exercised on a plain JVM.
 */
enum class AppDestination {
    HOME,
    LIBRARY,
    DOWNLOADS,
    ;

    companion object {
        /**
         * Where the app opens. `navigation-shell`: "a reader launches the app normally,
         * then it opens on the home surface".
         */
        val start: AppDestination = HOME
    }
}

/**
 * Somewhere a reader can descend to from a destination.
 *
 * One value per screen, carrying exactly what that screen needs to be drawn. This is the
 * replacement for fourteen booleans and nullables whose combinations decided what was on
 * screen: a state that could express "browsing a share while a collection is open and
 * Settings is showing" and relied on the order of an `if` chain to make that impossible.
 * Here it is not expressible.
 *
 * A screen is a value rather than a composable so the back rule can be a function of the
 * stack alone, and so the whole model can be asserted in a unit test with no device.
 */
sealed interface Screen {
    /**
     * Whether this screen takes the whole window.
     *
     * The reader gets it because `comic-reader` gives the artwork the window. Settings and
     * the two source-trouble screens get it because they are screens a reader comes back
     * from rather than destinations they stay in — a navigation bar under them would offer
     * a lateral move out of a task they were half-way through. Everything else keeps the
     * bar, which is what makes a destination's own path feel like one place.
     */
    val hidesNavigation: Boolean get() = false

    /**
     * A page of an online library, and optionally the publication chosen from it.
     *
     * The entry rides on the page rather than being a screen of its own so that the browser
     * and its download queue are remembered across opening and closing a publication — two
     * screens would build a second HTTP client for the same catalogue.
     */
    data class Catalogue(val page: CataloguePage, val entry: OpdsEntry? = null) : Screen

    /**
     * A Kavita server at one of its three levels.
     *
     * Each level is its own screen on the stack, so back walks chapters → series →
     * libraries → out. The level used to live beside the server as a second piece of state,
     * where the system back gesture left the server entirely from any depth.
     */
    data class Kavita(
        val page: KavitaPage,
        val level: KavitaLevel,
        /** A term the library carried across for the server to answer itself. */
        val search: String = "",
    ) : Screen

    /** One folder of a shared folder on another computer. Entering one pushes another. */
    data class Share(val page: SmbPage, val folder: String? = null) : Screen

    /** A source that is not answering, said plainly rather than as an empty list. */
    data class SourceAway(val source: Source) : Screen {
        override val hidesNavigation: Boolean = true
    }

    /** A source whose stored sign-in the server no longer accepts. */
    data class SourceRefused(val source: Source) : Screen {
        override val hidesNavigation: Boolean = true
    }

    /** Collections and reading lists, the reader's own and their servers'. */
    data object Shelves : Screen

    data class Collection(val id: UUID) : Screen

    data class ReadingList(val id: UUID) : Screen

    /** One of a server's own shelves. */
    data class ServerShelfPage(val shelf: ServerShelf) : Screen

    data class Settings(val opensAtDownloads: Boolean = false) : Screen {
        override val hidesNavigation: Boolean = true
    }

    /** A publication open in the comic reader, and the decoder path it was opened from. */
    data class Reader(val publication: Publication, val path: String) : Screen {
        override val hidesNavigation: Boolean = true
    }
}

/**
 * A modal the app layer hosts on top of whatever is on screen.
 *
 * Not part of [AppNavigation]: a bottom sheet is not a place, it dismisses itself, and it
 * brings its own back handling. Typed all the same, so that four booleans cannot be true at
 * once the way `isAddingCatalogue`, `isAddingKavita`, `isAddingShare` and `reconnecting`
 * could.
 */
sealed interface AppSheet {
    data object AddOnlineLibrary : AppSheet
    data object AddKavita : AppSheet
    data object AddSharedFolder : AppSheet

    /** Signing in again to a source whose credential was refused. */
    data class Reconnect(val source: Source) : AppSheet
}
