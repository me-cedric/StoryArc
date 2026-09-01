package app.storyarc.core.model

import kotlinx.serialization.Serializable

/**
 * One of the five faces of the mark a reader can put on the home screen.
 *
 * `settings-and-about`: "faces of one mark, not different marks — a reader picking a
 * lighter tile is still holding StoryArc". The five are the ones
 * `scripts/brand-mark.swift` renders, and this type carries the *names* of what that
 * generator wrote rather than any geometry of its own.
 *
 * In the domain rather than in `:feature:settings`, for the reason [AppearanceMode] is: it
 * is a *choice*, the mapping to an `<activity-alias>` is the platform's business, and a
 * value type is what a JVM test can assert against without a device. Mirrored case for case
 * by iOS's `AppIconChoice` — including the order, because that is the order the chooser
 * draws them in.
 *
 * **The platform is the store.** There is deliberately no entry for this in [AppSettings].
 * Android persists a component's enabled state itself and iOS persists `alternateIconName`
 * itself, so a preference beside either would be a second answer to a question the platform
 * already answers — and the spec asks the chooser to show "what was applied", which is the
 * platform's answer and never a stored intention.
 *
 * [AppIconAliases] is the half iOS has no counterpart for: `setAlternateIconName` is one
 * call and this platform has no equivalent, so the swap is a *sequence* of component-state
 * writes and the sequence has an invariant worth a test of its own.
 */
@Serializable
enum class AppIconChoice {
    /** The near-black plate the artwork leads with. What a fresh install draws. */
    INK,

    /** The warm off-white plate, for a light home screen. */
    PAPER,

    /** The pale lavender plate the artwork's third variant uses. */
    BLOOM,

    /** The saturated violet plate. The loud one. */
    ARC,

    /**
     * Ink's plate with the mark in a single ink — and the art `<monochrome>` points at, which
     * is why it is a face rather than only a layer.
     */
    MONO,
    ;

    /**
     * Whether this is the face the app ships with.
     *
     * `settings-and-about`: "the default is marked as the default, so a reader can find it
     * without remembering which one it was".
     */
    val isDefault: Boolean get() = this == DEFAULT

    /**
     * The `<activity-alias>` in the app's manifest that draws this face.
     *
     * **Every face is an alias, including the default, and that is a correction the device
     * forced.** The design document asks for the default to be `MainActivity` itself, so that
     * a fresh install and a reset land in the same state. On this platform that shape breaks
     * the app: choosing any other face means disabling `MainActivity`, and an alias whose
     * *target* is disabled stops resolving — `am start` on the alias leaves no process and the
     * MAIN/LAUNCHER intent answers "unable to resolve", while the launcher goes on drawing the
     * icon it cached. A reader would tap it and nothing would happen.
     *
     * The reason behind that requirement survives whole: [AppIconAliases.plan] writes
     * [AppIconAliasState.DEFAULT] to all five when the default is chosen, which is byte for
     * byte the state a fresh install holds. Only the mechanism moved, and `MainActivity` is
     * now never written to at all.
     *
     * A class name as a string, in a module that owns no activity: the manifest is the other
     * half of this pair and nothing in the compiler joins them, so `AppIconManifestTest`
     * reads the manifest and asserts every name below is declared there — and that none of
     * them is the activity the aliases point at. That test is the join, and it is the reason
     * these live beside the faces rather than in the feature.
     */
    val componentClassName: String
        get() = when (this) {
            INK -> "app.storyarc.MainActivityInk"
            PAPER -> "app.storyarc.MainActivityPaper"
            BLOOM -> "app.storyarc.MainActivityBloom"
            ARC -> "app.storyarc.MainActivityArc"
            MONO -> "app.storyarc.MainActivityMono"
        }

    companion object {
        /**
         * What a fresh install draws, and what "reset" returns to.
         *
         * [INK] and not merely "the first entry": the default is a product decision, and a
         * reorder of the chooser must not be able to change which icon a new reader gets.
         */
        val DEFAULT = INK

        /**
         * The activity every alias points at, which no face may ever name.
         *
         * Named here so the guard can assert it: the one write that would make the app
         * unreachable is a write to this component, and nothing in this file's shape stops a
         * future face from claiming it by name.
         */
        const val TARGET_ACTIVITY = "app.storyarc.MainActivity"
    }
}

/**
 * What a component's enabled setting is left as.
 *
 * Three values rather than a boolean, because [DEFAULT] is not a synonym for either of the
 * others: it hands the component back to what the manifest declares. That is what makes a
 * reset land on the state a fresh install has, byte for byte, rather than on a state that
 * merely looks the same from the launcher.
 */
enum class AppIconAliasState { DEFAULT, ENABLED, DISABLED }

/** One step of a swap: a component, and the state it is to be left in. */
data class AppIconAliasStep(val face: AppIconChoice, val state: AppIconAliasState)

/**
 * The order the components are written in when a reader picks a face.
 *
 * Android has no `setAlternateIconName`. The mechanism is one `<activity-alias>` per face,
 * each carrying the launcher intent filter, with exactly one enabled — and the consequences
 * of that are the reason this is a planner rather than two lines at a call site:
 *
 * - **Zero enabled makes the app vanish from the launcher**, and is unrecoverable without a
 *   reinstall. Every claim below is about avoiding that, not about tidiness.
 * - **The enable precedes every disable.** Disabling the currently-enabled component first
 *   can close the task, and for one instant would leave nothing on the launcher at all.
 * - **The plan is total.** It names *every* face's state, not just the two that change, so
 *   applying it from any starting state — including one a half-applied earlier plan left
 *   behind — lands on exactly one enabled. That is what makes a failure mid-sequence
 *   recoverable rather than a state the app has to remember it is in.
 * - **The plan is idempotent.** Choosing the face already in use rewrites the same states
 *   and changes nothing, so a double tap cannot open a window with none enabled.
 * - **It never writes to the activity the aliases point at.** An alias whose target is
 *   disabled does not merely lose its icon — it stops resolving, and the app becomes
 *   unlaunchable while the launcher goes on drawing a cached icon. That is why every face,
 *   including the default, is an alias of its own; see [AppIconChoice.componentClassName].
 *
 * `AppIconAliasesTest` asserts all five over every transition, including the same face twice
 * and a failure at each step.
 */
object AppIconAliases {

    /** The writes that leave [target] as the one face the launcher draws, in order. */
    fun plan(target: AppIconChoice): List<AppIconAliasStep> = buildList {
        add(AppIconAliasStep(target, stateFor(target, enabled = true)))
        for (face in AppIconChoice.entries) {
            if (face != target) add(AppIconAliasStep(face, stateFor(face, enabled = false)))
        }
    }

    /**
     * Whether a component left in [state] draws on the launcher.
     *
     * [AppIconAliasState.DEFAULT] means "whatever the manifest says", and what the manifest
     * says is that the default face's component is enabled and every alias is not.
     */
    fun isEnabled(face: AppIconChoice, state: AppIconAliasState): Boolean = when (state) {
        AppIconAliasState.DEFAULT -> face.isDefault
        AppIconAliasState.ENABLED -> true
        AppIconAliasState.DISABLED -> false
    }

    /**
     * The state that leaves [face] enabled or not, preferring the manifest's own answer.
     *
     * A component whose wanted state is already the manifest's is set to
     * [AppIconAliasState.DEFAULT] rather than to an explicit one, which is why choosing the
     * default face returns the whole app to the component states a fresh install has.
     */
    private fun stateFor(face: AppIconChoice, enabled: Boolean): AppIconAliasState = when {
        enabled == face.isDefault -> AppIconAliasState.DEFAULT
        enabled -> AppIconAliasState.ENABLED
        else -> AppIconAliasState.DISABLED
    }
}
