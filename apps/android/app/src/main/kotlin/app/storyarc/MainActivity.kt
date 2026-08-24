package app.storyarc

import android.os.Bundle
import androidx.activity.ComponentActivity
import androidx.activity.compose.setContent
import androidx.activity.enableEdgeToEdge
import app.storyarc.core.designsystem.theme.AppearanceMode
import app.storyarc.core.designsystem.theme.StoryArcTheme
import androidx.lifecycle.viewmodel.compose.viewModel
import androidx.lifecycle.ViewModelProvider
import androidx.lifecycle.viewmodel.initializer
import androidx.lifecycle.viewmodel.viewModelFactory
import app.storyarc.core.model.Publication
import app.storyarc.core.persistence.ProgressStore
import app.storyarc.feature.library.LibraryScreen
import app.storyarc.feature.library.LibraryViewModel
import app.storyarc.feature.reader.ReaderScreen
import app.storyarc.feature.reader.ReaderViewModel
import androidx.compose.runtime.getValue
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

                if (selection == null) {
                    val libraryViewModel = viewModel<LibraryViewModel>(
                        factory = viewModelFactory {
                            initializer { LibraryViewModel(application, progress) }
                        },
                    )
                    LibraryScreen(
                        viewModel = libraryViewModel,
                        onOpen = { publication, path -> reading = publication to path },
                    )
                } else {
                    // Keyed on the publication so opening a different one builds a
                    // fresh model rather than showing the previous book's pages.
                    val readerViewModel = remember(selection.first.id) {
                        ReaderViewModel(
                            selection.first,
                            contentResolver,
                            selection.second,
                            progress,
                        )
                    }
                    BackHandler { reading = null }
                    ReaderScreen(viewModel = readerViewModel, onClose = { reading = null })
                }
            }
        }
    }
}
