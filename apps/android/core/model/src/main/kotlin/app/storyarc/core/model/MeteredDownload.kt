package app.storyarc.core.model

/**
 * Whether a download may go over a connection the reader pays for.
 *
 * `offline-downloads`' *Overriding once*: "when a user explicitly downloads a specific
 * publication while on a metered connection, the app confirms with the size and proceeds
 * **for that item only**". Beside it, *Wi-Fi only*: with the setting on and the device on
 * cellular, downloads "pause and state that they are waiting for Wi-Fi".
 *
 * Until now `enqueue` queued unconditionally. There was no per-item override, no
 * confirmation and no size stated anywhere before a single-publication download -- so a
 * four-hundred-megabyte comic tapped on a train either went silently over mobile data, or,
 * with Wi-Fi-only on, sat in a queue the reader had no way to release for that one book. Two
 * different wrong answers to the same question.
 *
 * The rule is pure and lives here so both platforms answer it identically. What is genuinely
 * platform-shaped stays where it is: **whether this is really a mobile link** is
 * [app.storyarc.feature.library.NetworkCost]'s question, and it is the one part of this that
 * cannot be settled at a desk -- `ConnectivityManager` and `NWPathMonitor` both report Wi-Fi
 * to an emulator and a simulator whatever the host is on. Everything below is decided from
 * that answer and is asserted here. iOS keeps the same rule in `MeteredDownload.swift`.
 */
object MeteredDownload {
    /**
     * Whether the reader has to be asked before this one is queued.
     *
     * The question is about the *connection*, not about the reader's Wi-Fi-only setting. The
     * setting says what should happen when nobody is watching; this scenario is a reader
     * watching, having just tapped Download, and `offline-downloads` asks either way -- a
     * reader who left the setting off has still not agreed to spend four hundred megabytes
     * of their allowance on one comic.
     *
     * Asked once per publication. A grant already given is not asked for again, which is
     * what makes *Download* work the second time a reader presses it.
     */
    fun needsConfirmation(isMetered: Boolean, isOverridden: Boolean): Boolean =
        isMetered && !isOverridden

    /**
     * Whether a queued download may start now.
     *
     * The override is *per item*, which is the clause that does the work: a reader who agreed
     * to spend data on one comic has not agreed to release the whole queue behind it.
     * Everything else stays where the setting left it.
     */
    fun mayStart(wifiOnly: Boolean, isMetered: Boolean, isOverridden: Boolean): Boolean =
        isOverridden || !(wifiOnly && isMetered)
}
