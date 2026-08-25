package app.storyarc.feature.settings

import android.content.Context
import android.content.Intent
import android.net.Uri
import android.os.Build

/**
 * What the About screen can say about this build, and how it opens a link.
 *
 * The version is read from the package rather than hard-coded, because a hard-coded
 * version in an About screen is a version that is wrong by the next release.
 */
object BuildInfo {
    var version: String = "—"
        private set
    var build: String = "—"
        private set

    /**
     * Called once by the host, which is the only thing that has a `Context` this early.
     *
     * Public where the rest of this module is internal, because the host has to call it:
     * a version read lazily from inside a composable would be read on a frame rather
     * than at launch.
     */
    fun read(context: Context) {
        val info = runCatching {
            context.packageManager.getPackageInfo(context.packageName, 0)
        }.getOrNull() ?: return
        version = info.versionName ?: "—"
        build = info.longVersionCode.toString()
    }

    /**
     * The issue tracker, pre-filled with what a bug report needs and nothing else.
     *
     * `settings-and-about`: "the app version, platform version, and device class
     * pre-filled, and no personal data". Device *class* rather than device: `Build.MODEL`
     * is not personal on its own, but it narrows a person far more than "phone" does, and
     * the spec asked for the class.
     */
    fun issueUrl(): String {
        val body = Uri.encode(
            "StoryArc $version ($build)\nAndroid ${Build.VERSION.RELEASE} (API ${Build.VERSION.SDK_INT})\n\n",
        )
        return "https://github.com/me-cedric/StoryArc/issues/new?body=$body"
    }

    fun open(context: Context, url: String) {
        runCatching {
            context.startActivity(Intent(Intent.ACTION_VIEW, Uri.parse(url)))
        }
    }
}
