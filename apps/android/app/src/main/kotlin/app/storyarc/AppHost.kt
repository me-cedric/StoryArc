package app.storyarc

import androidx.activity.ComponentActivity
import androidx.compose.runtime.MutableState
import app.storyarc.core.model.DownloadLibrary
import app.storyarc.core.model.Publication
import app.storyarc.core.model.Source
import app.storyarc.core.persistence.RemovedDownload
import app.storyarc.feature.library.LibraryViewModel
import app.storyarc.navigation.AppNavigation
import app.storyarc.navigation.AppSheet

/**
 * What a hosted screen needs to reach the rest of the app, in one parameter.
 *
 * A feature module never depends on another feature module, so every move between features
 * is reported to the app layer and answered here: the library reports that a publication
 * was chosen, and this is what knows a reader exists. Gathering those answers into one
 * value is what keeps each screen's signature to the two or three things it is actually
 * about, rather than the twelve the app layer happens to hold.
 *
 * Deliberately not a container of everything: [AppDependencies] holds the stores, this
 * holds the verbs.
 */
internal class AppHost(
    val activity: ComponentActivity,
    val dependencies: AppDependencies,
    val library: LibraryViewModel,
    /**
     * What is on the device, read as state so the download destination and Settings see the
     * same list change at the same moment.
     */
    val downloads: MutableState<DownloadLibrary>,
    /** A download removed within the last ten seconds, still offering to come back. */
    val removed: MutableState<RemovedDownload?>,
    /**
     * Move. `navigate { push(Screen.Shelves) }` — the only way anything changes where the
     * app is, so there is one writer and no second copy of the truth.
     */
    val navigate: (AppNavigation.() -> AppNavigation) -> Unit,
    /**
     * Open a publication in whichever reader it needs, from wherever it was chosen.
     *
     * One rule, four callers — the library, an online library, a shared folder and a file
     * the system handed over. Three copies of it is how one of them ends up opening a
     * reflowable book in the comic reader.
     */
    val open: (Publication, String) -> Unit,
    /**
     * Browse a source, or say plainly why it cannot be browsed right now.
     *
     * The second argument is a term the library already had the reader typing, which a
     * Kavita server answers itself; empty everywhere else. One entry point rather than two,
     * because the reachability checks in front of it must not be reachable around.
     */
    val browse: (Source, String) -> Unit,
    /** Present, or dismiss, the one modal the app layer hosts. */
    val sheet: (AppSheet?) -> Unit,
)
