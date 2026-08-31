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
 * The four places the app can be.
 *
 * `navigation-shell` requires that the app "SHALL NOT add, remove or reorder a destination in
 * response to anything the reader configures". An `enum` rather than a list built from the
 * source registry is how that promise is kept by construction: there is no expression
 * anywhere that could produce a fifth, and adding a ninth Kavita server produces none.
 *
 * ## Search was deliberately absent, and is deliberately here
 *
 * **The argument this comment used to make.** "Material ranks a search bar above a search
 * destination and only permits the destination for an app whose primary action *is*
 * searching; StoryArc's is browsing, so search is a field at the top of Home and the
 * library." Material's sentence is quoted correctly and still says that: *"If search is the
 * primary action, focused search can be a standalone destination reached from a navigation
 * bar."* It is permission conditioned on a judgement, and the judgement was ours to make.
 *
 * **Why the judgement changed**, for a reason about this app rather than about apps in
 * general: StoryArc's publications arrive from a device, a folder, an OPDS catalogue, a
 * Kavita server and an SMB share, and **no shelf shows all of them at once in a way a reader
 * can scan**. Search is the only surface that spans the sources. In an app whose library is
 * one folder, search is a filter; in this one it is the way in. A field belonging to the
 * library also made searching something you do *to* the shelf, which is the wrong shape for
 * the one question that is not about a shelf.
 *
 * The old note said iOS "diverges here on purpose". It no longer diverges on *this* — both
 * platforms make search a destination. What still diverges is the container: iOS keeps its
 * floating capsule, Android's bar is edge-to-edge, because `ShortNavigationBar` exposes no
 * `shape` parameter at all. That divergence is the live one.
 *
 * Carries no label and no icon: what a destination *is* belongs to the app, what it looks
 * like belongs to the shell that draws it. Keeping the resource identifier and the vector
 * out of here is also what lets the whole navigation model be exercised on a plain JVM.
 */
enum class AppDestination {
    HOME,
    LIBRARY,
    DOWNLOADS,

    /**
     * The one surface that spans every configured source. Last, because it is where a reader
     * goes when the three shelves before it did not have the answer.
     */
    SEARCH,
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
     * The state this screen returns to when it is backed out of, or `null` when backing out
     * of it leaves it altogether.
     *
     * A screen may **name** its own previous state. It may not **handle** the gesture: there
     * is one back rule, in [AppNavigation.back], and a screen that installed its own
     * handler is a fifteenth answer to a question that must only have one. This exists for
     * the one honest case — a screen with something open on top of it that is not worth a
     * position of its own.
     */
    val previous: Screen? get() = null

    /**
     * A page of an online library, and optionally the publication chosen from it.
     *
     * The chosen publication rides on the page rather than taking a position of its own, so
     * that the browser and its download queue survive being opened and closed: two
     * positions would discard what was remembered at the first and build a second HTTP
     * client for the same catalogue, and the page behind would come back re-fetched and
     * scrolled to the top.
     */
    data class Catalogue(val page: CataloguePage, val entry: OpdsEntry? = null) : Screen {
        override val previous: Screen? get() = if (entry == null) null else copy(entry = null)
    }

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

    /**
     * The page a publication has: what it is, what can be done with it, and where it lives.
     *
     * Keeps the navigation bar. It is somewhere a reader *is* — the seam between the shelf
     * and the reader — rather than a task they came back from, so a lateral move out of it
     * is a move they may legitimately want.
     *
     * A different verb from [Reader], and `publication-detail` makes the distinction a
     * requirement rather than an accident: a cover leads here, and a resume affordance opens
     * the book with this page not in between.
     *
     * `PublicationPage` rather than `Publication`, which would shadow the domain type inside
     * this interface's own body and silently retype [Reader]'s first parameter.
     */
    data class PublicationPage(val publication: Publication) : Screen

    /** A publication open in the comic reader, and the decoder path it was opened from. */
    data class Reader(val publication: Publication, val path: String) : Screen {
        override val hidesNavigation: Boolean = true
    }

    /**
     * The full player, for whatever is playing.
     *
     * **A destination, not a sheet.** `design.md` records why: Material points at a
     * standard bottom sheet for exactly this, and `BottomSheetScaffold` has a `topBar`
     * slot and no `bottomBar` slot — so its peek row would sit behind the navigation bar.
     * The drag-to-expand sheet is deferred to its own change and this is a screen until
     * then.
     *
     * It carries no publication. What is playing is `PlaybackHost`'s, and a screen holding
     * a copy would be a second answer to "what is playing" that could disagree with the
     * compact bar three dp below it.
     */
    data object Player : Screen {
        // The navigation control stays. The player is somewhere a listener goes *to* while
        // the book plays, and taking the destinations away would strand them there.
        override val hidesNavigation: Boolean get() = false
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
