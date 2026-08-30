package app.storyarc.navigation

import androidx.compose.runtime.saveable.Saver

/**
 * Where the app is, whole, in one value.
 *
 * Three destinations, and one stack of [Screen]s per destination. Everything the shell
 * draws and every answer the back gesture gives is a function of this — which is the point.
 * The state it replaces was fourteen independent booleans and nullables read by an `if`
 * chain, with a `BackHandler` inside each branch: fourteen back rules that had to be kept
 * consistent by hand, and a rail selection re-derived from whichever of four nullables
 * happened to be set.
 *
 * `navigation-shell` asks for two things this shape gives for free. "The destination they
 * left keeps its scroll position, its active filters and its selection" — a destination's
 * stack is untouched while another is on screen. And "the platform's own back affordance
 * retraces that destination's own path rather than a single path shared by all three" —
 * [back] pops the current destination's stack and no other.
 *
 * Immutable, and every operation returns a new value: the shell holds one `mutableStateOf`
 * and recomposition follows from replacing it. There is no second copy of the truth to
 * disagree with the first.
 */
data class AppNavigation(
    val destination: AppDestination = AppDestination.start,
    private val stacks: Map<AppDestination, List<Screen>> = emptyMap(),
) {
    /** What the reader has descended into on the destination they are on. */
    val stack: List<Screen> get() = stacks[destination].orEmpty()

    /** The screen on top, or `null` when the destination's own root is showing. */
    val current: Screen? get() = stack.lastOrNull()

    /** Whether the navigation control is drawn. See [Screen.hidesNavigation]. */
    val showsNavigation: Boolean get() = current?.hidesNavigation != true

    /**
     * Whether back has anything of the app's to do.
     *
     * False only at the root of the home destination, which is where the system takes the
     * gesture and leaves the app — the one place a reader expects that.
     */
    val canGoBack: Boolean
        get() = stack.isNotEmpty() || destination != AppDestination.start

    /**
     * The reader chose a destination from the navigation control.
     *
     * Choosing the one already showing returns it to its root, which is Material's own
     * behaviour for a navigation bar and the only way back out of a deep stack in one
     * gesture. Choosing another leaves both stacks alone, so coming back is a return
     * rather than a reset.
     */
    fun select(destination: AppDestination): AppNavigation =
        if (destination == this.destination) root() else copy(destination = destination)

    /**
     * Open a destination at its root, whatever was stacked on it.
     *
     * What a quick action means: the launcher entry promises the shelf, not wherever the
     * reader last was inside it.
     */
    fun open(destination: AppDestination): AppNavigation =
        copy(destination = destination, stacks = stacks + (destination to emptyList()))

    /** Descend into a screen from wherever the reader is. */
    fun push(screen: Screen): AppNavigation =
        copy(stacks = stacks + (destination to stack + screen))

    /**
     * Replace the screen on top rather than stacking onto it.
     *
     * For a move sideways: the next volume opened from the end of the last one, or a series
     * opened from a server's collection. Stacking those would leave a pile of readers
     * behind a long series.
     */
    fun replace(screen: Screen): AppNavigation =
        if (stack.isEmpty()) push(screen) else copy(stacks = stacks + (destination to stack.dropLast(1) + screen))

    /** One step back up the current destination's own path. */
    fun pop(): AppNavigation =
        if (stack.isEmpty()) this else copy(stacks = stacks + (destination to stack.dropLast(1)))

    /** The current destination, with everything stacked on it unwound. */
    fun root(): AppNavigation = copy(stacks = stacks + (destination to emptyList()))

    /**
     * The one back rule.
     *
     * Take the step the screen on top names, if it names one; otherwise pop this
     * destination's stack; at its root, fall back to the destination the app opens on; at
     * that root, hand the gesture to the system. Four lines, one place. A screen may say
     * what it returns to ([Screen.previous]) and may not answer the gesture itself — which
     * is what stops the fourteenth branch from being the one that forgets.
     */
    fun back(): AppNavigation {
        val step = current?.previous
        return when {
            step != null -> replace(step)
            stack.isNotEmpty() -> pop()
            destination != AppDestination.start -> copy(destination = AppDestination.start)
            else -> this
        }
    }

    /**
     * A key naming this exact position, for the saved state of the screen drawn at it.
     *
     * Depth and kind rather than the screen's own equality: two folders of the same share
     * are different positions and must not share a scroll offset, while the same catalogue
     * page with a publication open over it is the same position and must keep one.
     */
    val stateKey: String
        get() = "${destination.name}/${stack.size}/${current?.let { it::class.simpleName } ?: "root"}"

    companion object {
        /**
         * What survives the activity being rebuilt: the destination, and not the path.
         *
         * A destination is a name. A screen on the path is a live page of an online
         * library, an open publication or a server address, none of which belongs in a
         * saved-state bundle — so a rebuilt activity lands on the destination the reader was
         * on, at its root, rather than on the home surface as it did before. The font size
         * changing is the commonest way to meet this, and it used to lose everything.
         */
        val Saver: Saver<AppNavigation, String> =
            Saver(
                save = { it.destination.name },
                restore = { name ->
                    AppNavigation(
                        AppDestination.entries.firstOrNull { it.name == name }
                            ?: AppDestination.start,
                    )
                },
            )
    }
}
