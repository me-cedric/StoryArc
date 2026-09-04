package app.storyarc.feature.library

import androidx.compose.runtime.Composable
import androidx.compose.runtime.LaunchedEffect
import androidx.compose.runtime.getValue
import androidx.compose.runtime.rememberUpdatedState
import androidx.compose.ui.platform.LocalContext
import androidx.lifecycle.Lifecycle
import androidx.lifecycle.compose.LifecycleEventEffect
import androidx.lifecycle.compose.LocalLifecycleOwner
import androidx.lifecycle.repeatOnLifecycle
import app.storyarc.core.model.RetryTrigger
import app.storyarc.core.model.SourceReachability

/**
 * The two occasions a source is asked again that the backoff does not cover.
 *
 * `sources`' *Retry policy* names them beside the schedule: the app "retries immediately,
 * once, when the device regains network connectivity or the app returns to the foreground".
 * Neither is a consequence of the loop -- a backoff that is waiting five minutes is still
 * waiting five minutes when the Wi-Fi comes back.
 *
 * Emits nothing. It is a pair of effects, drawn beside the library rather than inside it,
 * for the reason the probe itself is: the secrets a probe needs belong to the app layer, so
 * the app layer is where the trigger is answered. iOS's `SourceRetryTriggers` is the same
 * two occasions as a `ViewModifier` on its library view.
 *
 * **Both go through one call, deliberately.** [SourceReachability.shouldProbe] is where the
 * reading guard and the "something is away" condition live, and two call sites is how one of
 * them ends up without the guard -- which is the whole reason [RetryTrigger] is one type
 * naming two occasions rather than two unrelated callbacks.
 *
 * @param onTrigger what to do with an occasion. Called on the main thread; it is expected to
 *   hand the trigger to [LibraryViewModel.probe], which decides whether it earns a probe.
 */
@Composable
fun SourceRetryTriggers(onTrigger: (RetryTrigger) -> Unit) {
    val context = LocalContext.current
    val lifecycle = LocalLifecycleOwner.current.lifecycle
    val latest by rememberUpdatedState(onTrigger)

    // **Collected only while the activity is started, and that is the reading guard's other
    // half.** The EPUB reader is an activity of its own, so while a reader is in a chapter
    // this one is stopped and `LibraryViewModel` cannot see a reader open at all -- the
    // navigation state it would ask holds a library, not a book. Suspending the collection
    // is what keeps a dropped Wi-Fi mid-chapter from probing every configured server behind
    // the page the reader is on.
    LaunchedEffect(context, lifecycle) {
        lifecycle.repeatOnLifecycle(Lifecycle.State.STARTED) {
            SourceReachability.triggers(NetworkPaths.satisfied(context)).collect { latest(it) }
        }
    }

    // The other occasion. Not the effect above restarting: that one restarts on *start*, and
    // it restarts for a rotation and for a return from any other activity as well, so it
    // says nothing about the app having been away. This one is the event itself.
    //
    // It also fires on the first resume, when nothing has been probed yet and every source
    // still reads `Connecting`. `shouldProbe` refuses that on its own -- a trigger arriving
    // while nothing is unreachable has nothing to reconnect -- so the first composition
    // costs no request.
    LifecycleEventEffect(Lifecycle.Event.ON_RESUME) {
        latest(RetryTrigger.RETURNED_TO_FOREGROUND)
    }
}
