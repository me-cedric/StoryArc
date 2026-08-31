package app.storyarc

import android.content.Context
import android.content.Intent
import android.net.Uri
import android.os.Bundle
import android.view.KeyEvent
import androidx.activity.ComponentActivity
import androidx.activity.compose.setContent
import androidx.activity.enableEdgeToEdge
import androidx.compose.runtime.CompositionLocalProvider
import androidx.compose.runtime.LaunchedEffect
import androidx.compose.runtime.getValue
import androidx.compose.runtime.mutableStateOf
import androidx.compose.runtime.remember
import androidx.compose.runtime.setValue
import app.storyarc.core.designsystem.theme.LocalVolumeTurns
import app.storyarc.core.designsystem.theme.StoryArcTheme
import app.storyarc.core.designsystem.theme.VolumeTurns
import app.storyarc.core.model.QuickActionRequest
import app.storyarc.core.persistence.SettingsStore
import app.storyarc.core.persistence.chosenLanguage
import app.storyarc.core.persistence.speaking
import app.storyarc.feature.settings.BuildInfo

/**
 * The activity, and only what has to be one.
 *
 * Volume keys, a language chosen inside the app, the intents the system delivers, and the
 * stores the whole app shares. Everything about *where the app is* lives in [AppShell] and
 * the typed navigation model under it: this file used to be 1168 lines against an 800-line
 * cap, most of it a chain of fourteen booleans deciding which screen was drawn and a
 * `BackHandler` inside each branch.
 */
class MainActivity : ComponentActivity() {
    /**
     * Filled in by whichever reader is on screen, read by [onKeyDown].
     *
     * A volume key never reaches Compose: it arrives here, and only here can it be consumed
     * before the system changes the volume. `page-transitions` asks for the volume buttons
     * "where enabled in settings", so both halves have to be true — a reader on screen *and*
     * the setting on.
     */
    private val volumeTurns = VolumeTurns()

    /**
     * A file the system handed over, waiting for the composition to pick it up.
     *
     * A `MutableState` rather than a plain field, because the intent can arrive before the
     * first composition (a cold start from a file manager) or long after it ([onNewIntent],
     * when the app is already open). Both have to reach the same reader.
     */
    private val handedOver = mutableStateOf<Uri?>(null)

    /**
     * A quick action the launcher sent, waiting for the composition to pick it up.
     *
     * A `MutableState` for the same reason [handedOver] is one.
     */
    private val quickAction = mutableStateOf<QuickActionRequest?>(null)

    /** Read on each key press rather than cached: the setting can change mid-session. */
    private val volumeTurnsEnabled: Boolean
        get() = SettingsStore.open(applicationContext).settings().turnPagesWithVolumeButtons

    /**
     * Volume keys, when a reader asked for them and the reader turned them on.
     *
     * Consumed rather than passed on, which is the whole point and also the risk: a reader
     * who cannot find why their volume keys stopped working has a defect, not a feature.
     * That is why the setting is off by default and says what it does.
     */
    override fun onKeyDown(keyCode: Int, event: KeyEvent?): Boolean {
        val forward = when (keyCode) {
            KeyEvent.KEYCODE_VOLUME_DOWN -> true
            KeyEvent.KEYCODE_VOLUME_UP -> false
            else -> return super.onKeyDown(keyCode, event)
        }
        val turn = volumeTurns.turn ?: return super.onKeyDown(keyCode, event)
        if (!volumeTurnsEnabled) return super.onKeyDown(keyCode, event)
        return turn(forward) || super.onKeyDown(keyCode, event)
    }

    /** The app was already open when the system handed a file over. */
    override fun onNewIntent(intent: Intent) {
        super.onNewIntent(intent)
        setIntent(intent)
        OpenedFile.uriFrom(intent)?.let { handedOver.value = it }
        HomeScreenActions.requestFrom(intent)?.let { quickAction.value = it }
    }

    /**
     * The language this activity was built with.
     *
     * Kept so a change can be told from the value it already has: the composition reads the
     * setting on every launch, and recreating on that would be a loop.
     */
    private var language: String? = null

    /**
     * `localization`: the reader's own language, before anything reads a resource.
     *
     * Here rather than in the composition because a `Popup` -- every dropdown menu in the
     * app -- is its own window built from this context, and would otherwise stay in the
     * system's language while the screen behind it changed.
     *
     * `EpubReaderActivity` carries the same three lines, because an activity that does not
     * is an activity in the system's language. Both call the same `InterfaceLanguage` in
     * `:core:persistence`; a second mechanism is how the two would come to disagree.
     */
    override fun attachBaseContext(newBase: Context) {
        language = newBase.chosenLanguage()
        super.attachBaseContext(newBase.speaking(language))
    }

    override fun onCreate(savedInstanceState: Bundle?) {
        // `native-experience`: draw edge to edge and handle insets, rather than avoiding
        // them. Not optional on API 35+, and correct below it anyway.
        enableEdgeToEdge()
        super.onCreate(savedInstanceState)
        // A cold start from a file manager or a share sheet. Until this line existed the
        // system handed StoryArc a file and StoryArc showed its library instead.
        handedOver.value = OpenedFile.uriFrom(intent)
        // And the other kind of cold start: the reader held the app icon down and chose an
        // entry. `native-experience` asks for quick actions, and until this line the
        // launcher started the app and the choice was dropped on the floor.
        quickAction.value = HomeScreenActions.requestFrom(intent)

        val dependencies = AppDependencies.open(applicationContext)
        BuildInfo.read(applicationContext)

        setContent {
            // Read as state, so `settings-and-about`'s "applies immediately across the whole
            // app without a restart" is what the code does rather than something it has to
            // arrange: the theme recomposes because the value it reads changed.
            var settings by remember { mutableStateOf(dependencies.settings.settings()) }

            // `localization`: a language chosen here is applied by rebuilding the activity
            // against it, because a composition local does not reach a menu -- see
            // `InterfaceLanguage`. Guarded on a real change so this does not fire on launch.
            LaunchedEffect(settings.language) {
                if (settings.language != language) recreate()
            }

            StoryArcTheme(
                appearance = settings.appearance,
                useDynamicColor = settings.useDynamicColor,
            ) {
                // Provided around the whole app so both readers can fill it in, and so
                // `onKeyDown` has something to read. Volume-down turns forward, which is the
                // convention every reader app that offers this uses — down is "next", like a
                // scroll.
                CompositionLocalProvider(LocalVolumeTurns provides volumeTurns) {
                    AppShell(
                        activity = this,
                        dependencies = dependencies,
                        settings = settings,
                        onSettingsChange = {
                            settings = it
                            dependencies.settings.save(it)
                        },
                        onResetSettings = {
                            // Both stores, and only what each one calls a setting. The
                            // reading *defaults* are settings; a theme chosen while reading
                            // is not, and neither is progress.
                            dependencies.settings.reset()
                            settings = dependencies.settings.settings()
                            dependencies.readerPreferences.save(
                                dependencies.readerPreferences.themes().clearingDefaults(),
                            )
                        },
                        handedOver = handedOver,
                        quickAction = quickAction,
                    )
                }
            }
        }
    }
}
