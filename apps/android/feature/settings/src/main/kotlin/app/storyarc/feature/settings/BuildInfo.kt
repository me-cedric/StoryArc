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
     * pre-filled, and no personal data". All three, in the order iOS's `BuildInfo.issue`
     * writes them. The device class had been settled here in prose and stated only in the
     * diagnostic export, so a reader who tapped Report a problem sent a report that did
     * not say what they were holding.
     */
    fun issueUrl(context: Context): String {
        val body = Uri.encode(
            issueBody(
                platform = "Android ${Build.VERSION.RELEASE} (API ${Build.VERSION.SDK_INT})",
                deviceClass = deviceClass(context),
            ),
        )
        return "https://github.com/me-cedric/StoryArc/issues/new?body=$body"
    }

    /**
     * The three facts, in order, and nothing else.
     *
     * Its own function because it is the part of the scenario worth asserting, and the two
     * values around it need a `Context` and a device to read. iOS's `BuildInfo.issueBody`
     * is the same function, asserted the same way.
     */
    internal fun issueBody(platform: String, deviceClass: String): String =
        "StoryArc $version ($build)\n$platform\n$deviceClass\n\n"

    /**
     * Phone or tablet, and nothing narrower.
     *
     * Device *class* rather than device: `Build.MODEL` is not personal on its own, but it
     * narrows a person far more than "phone" does, and the spec asked for the class. iOS
     * answers the same question from `userInterfaceIdiom`; Android has no such property,
     * so the answer comes from the width the platform itself uses to pick `sw600dp`
     * resources.
     *
     * One function, two readers: the issue link and the diagnostic export. Two copies of
     * this threshold is how a report and an export come to disagree about the device they
     * describe.
     */
    fun deviceClass(context: Context): String =
        if (context.resources.configuration.smallestScreenWidthDp >= TABLET_WIDTH_DP) {
            "tablet"
        } else {
            "phone"
        }

    /** The width at which Android itself starts loading `sw600dp` resources. */
    private const val TABLET_WIDTH_DP = 600

    fun open(context: Context, url: String) {
        runCatching {
            context.startActivity(Intent(Intent.ACTION_VIEW, Uri.parse(url)))
        }
    }
}
