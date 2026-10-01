package app.storyarc.core.designsystem.theme

import android.content.ContentResolver
import android.database.ContentObserver
import android.os.Handler
import android.os.Looper
import android.provider.Settings

/**
 * Whether an animator duration scale means Reduce Motion is on.
 *
 * Split out so it can be asserted with no `ContentResolver` at all — the same reason
 * [isHighContrast] is split from [systemContrast] above.
 */
fun isReduceMotionScale(scale: Float): Boolean = scale == 0f

/**
 * Whether the reader has asked the system to remove animations.
 *
 * Android has no `UIAccessibility.isReduceMotionEnabled`; what it has is an animator
 * duration scale a reader can set to zero, in developer options or in accessibility
 * settings. `page-transitions` requires turning it off mid-session to restore the
 * chosen mode "without the reader being reopened", which [observeReduceMotion] is for —
 * a plain read answers only at the moment something else happens to ask again.
 */
fun systemReduceMotion(resolver: ContentResolver): Boolean =
    isReduceMotionScale(Settings.Global.getFloat(resolver, Settings.Global.ANIMATOR_DURATION_SCALE, 1f))

/**
 * Reports a change to the animator duration scale to [report], until the returned
 * function is called.
 *
 * The same `ContentObserver` shape [observeContrast] already uses in this package, for
 * the setting `page-transitions` actually names: the comic and the EPUB reader each read
 * [systemReduceMotion] on demand, which left the mode stuck until an unrelated
 * recomposition — the next page turn — happened to read it again.
 */
fun observeReduceMotion(resolver: ContentResolver, report: (Boolean) -> Unit): () -> Unit {
    val observer = object : ContentObserver(Handler(Looper.getMainLooper())) {
        override fun onChange(selfChange: Boolean) = report(systemReduceMotion(resolver))
    }
    resolver.registerContentObserver(
        Settings.Global.getUriFor(Settings.Global.ANIMATOR_DURATION_SCALE),
        false,
        observer,
    )
    return { resolver.unregisterContentObserver(observer) }
}
