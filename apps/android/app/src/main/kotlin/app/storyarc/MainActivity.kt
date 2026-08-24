package app.storyarc

import android.os.Bundle
import androidx.activity.ComponentActivity
import androidx.activity.compose.setContent
import androidx.activity.enableEdgeToEdge
import app.storyarc.core.designsystem.theme.AppearanceMode
import app.storyarc.core.designsystem.theme.StoryArcTheme
import androidx.lifecycle.viewmodel.compose.viewModel
import app.storyarc.feature.library.LibraryScreen
import app.storyarc.feature.library.LibraryViewModel

class MainActivity : ComponentActivity() {
    override fun onCreate(savedInstanceState: Bundle?) {
        // `native-experience`: draw edge to edge and handle insets, rather than
        // avoiding them. Not optional on API 35+, and correct below it anyway.
        enableEdgeToEdge()
        super.onCreate(savedInstanceState)

        setContent {
            // Appearance and dynamic-colour preferences move into a settings
            // store with the `settings-and-about` capability. Defaults here
            // match what that capability specifies: follow the system, and use
            // Material You where the device offers it.
            StoryArcTheme(appearance = AppearanceMode.SYSTEM, useDynamicColor = true) {
                LibraryScreen(viewModel = viewModel<LibraryViewModel>())
            }
        }
    }
}
