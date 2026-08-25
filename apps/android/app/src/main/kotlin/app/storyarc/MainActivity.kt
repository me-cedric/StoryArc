package app.storyarc

import android.os.Bundle
import androidx.activity.ComponentActivity
import androidx.activity.compose.setContent
import androidx.activity.enableEdgeToEdge
import app.storyarc.core.model.AppearanceMode
import app.storyarc.core.designsystem.theme.StoryArcTheme
import androidx.lifecycle.viewmodel.compose.viewModel
import androidx.lifecycle.ViewModelProvider
import androidx.lifecycle.viewmodel.initializer
import androidx.lifecycle.viewmodel.viewModelFactory
import app.storyarc.core.model.Publication
import app.storyarc.core.model.LibraryIndex
import app.storyarc.core.model.PublicationFormat
import app.storyarc.feature.epubreader.EpubReaderActivity
import app.storyarc.core.persistence.LibraryPreferences
import app.storyarc.core.persistence.ReaderPreferences
import app.storyarc.core.persistence.ProgressStore
import app.storyarc.feature.library.LibraryScreen
import app.storyarc.feature.library.LibraryViewModel
import app.storyarc.feature.reader.ReaderScreen
import app.storyarc.feature.reader.ReaderViewModel
import androidx.compose.runtime.getValue
import androidx.lifecycle.compose.collectAsStateWithLifecycle
import androidx.compose.runtime.mutableStateOf
import androidx.compose.runtime.remember
import androidx.compose.runtime.setValue
import androidx.activity.compose.BackHandler

class MainActivity : ComponentActivity() {
    override fun onCreate(savedInstanceState: Bundle?) {
        // `native-experience`: draw edge to edge and handle insets, rather than
        // avoiding them. Not optional on API 35+, and correct below it anyway.
        enableEdgeToEdge()
        super.onCreate(savedInstanceState)

        // One store for the whole app. ADR-0006 makes the local record
        // authoritative, so the reader writing and the library reading have to be
        // the same store — two would disagree about where the user is.
        val progress = ProgressStore.open(applicationContext)
        val preferences = LibraryPreferences.open(applicationContext)
        val readerPreferences = ReaderPreferences.open(applicationContext)

        setContent {
            // Appearance and dynamic-colour preferences move into a settings
            // store with the `settings-and-about` capability. Defaults here
            // match what that capability specifies: follow the system, and use
            // Material You where the device offers it.
            StoryArcTheme(appearance = AppearanceMode.SYSTEM, useDynamicColor = true) {
                // The app layer owns navigation between features, because a
                // feature module never depends on another feature module
                // (docs/architecture). The library reports a choice; the reader
                // accepts one; neither knows the other exists.
                var reading by remember { mutableStateOf<Pair<Publication, String>?>(null) }
                val selection = reading

                // Held across both branches, not just the library's: the reader's
                // end screen asks it what comes next in the series, and a model
                // created inside the library branch would not exist to ask.
                val libraryViewModel = viewModel<LibraryViewModel>(
                    factory = viewModelFactory {
                        initializer { LibraryViewModel(application, progress, preferences) }
                    },
                )

                if (selection == null) {
                    LibraryScreen(
                        viewModel = libraryViewModel,
                        onOpen = { publication, path ->
                            // Two readers, chosen by what the publication *is*
                            // rather than by a mode the user picks. A reflowable
                            // book is laid out by a rendering engine (ADR-0005); a
                            // comic is a list of images and needs none. A
                            // fixed-layout EPUB is the third case and belongs with
                            // the comic reader — it has pages, at a fixed aspect
                            // ratio — which is what `ebook-reader` asks for.
                            if (publication.format == PublicationFormat.EPUB &&
                                !publication.isFixedLayout
                            ) {
                                startActivity(
                                    EpubReaderActivity.intent(
                                        this@MainActivity,
                                        path,
                                        publication.displayTitle,
                                        publication.series,
                                    ),
                                )
                            } else {
                                reading = publication to path
                            }
                        },
                    )
                } else {
                    val publications by libraryViewModel.publications.collectAsStateWithLifecycle()
                    // Keyed on the publication so opening a different one builds a
                    // fresh model rather than showing the previous book's pages.
                    val readerViewModel = remember(selection.first.id) {
                        ReaderViewModel(
                            selection.first,
                            contentResolver,
                            selection.second,
                            progress,
                            // The same store the ebook reader uses, and a different
                            // scope inside it: `reading-themes` gives comics and
                            // reflowable text separate defaults.
                            shelfStore = readerPreferences,
                        )
                    }
                    BackHandler { reading = null }
                    ReaderScreen(
                        viewModel = readerViewModel,
                        onClose = { reading = null },
                        preferences = readerPreferences,
                        // `comic-reader`: the end of one volume offers the next.
                        // The app layer answers this because it is the only place
                        // that can see both the reader and the library.
                        // Collected rather than read off the flow: a `.value` in a
                        // composition is a snapshot nothing recomposes on, so the
                        // end screen would offer whatever was there when the reader
                        // opened.
                        nextInSeries = LibraryIndex.next(selection.first, publications),
                        onOpenNext = { publication ->
                            // The selection is replaced rather than a second reader
                            // pushed: stacking them would leave a pile behind a
                            // long series.
                            libraryViewModel.location(publication)?.let {
                                reading = publication to it
                            }
                        },
                    )
                }
            }
        }
    }
}
