package app.storyarc.feature.settings

import android.content.ComponentName
import android.content.Context
import android.content.pm.PackageManager
import app.storyarc.core.model.AppIconAliasState
import app.storyarc.core.model.AppIconAliases
import app.storyarc.core.model.AppIconChoice

/**
 * Puts a face on the launcher by enabling one of the app's launcher components.
 *
 * This platform has no `setAlternateIconName`, so the whole mechanism is
 * `PackageManager.setComponentEnabledSetting` over the aliases the manifest declares.
 * [AppIconAliases] decides the order and [AppIconAliasesTest] guards the invariant; this
 * class is the part that touches the platform, and it is a thin one on purpose.
 *
 * **`DONT_KILL_APP` on every write.** Without it the system may stop the app's process the
 * moment a component it hosts changes state — which here would close the reader's session in
 * the middle of a settings change, five times over.
 *
 * **It stops at the first failure, and the order is why that is safe.** The enable is the
 * first write, so a failure there means nothing has been disabled and the launcher still
 * draws what it drew. A failure on a later write leaves *two* components enabled, which is
 * untidy and harmless — the reader sees the icon they asked for, and the next successful plan
 * settles it, because the plan names every face rather than only the ones that change.
 *
 * The two seams are injected so a JVM test can drive the sequence without a device.
 * `AppIconSwitcherTest` is that test; [of] is the only implementation that ships.
 */
internal class AppIconSwitcher(
    private val read: (AppIconChoice) -> AppIconAliasState,
    private val write: (AppIconChoice, AppIconAliasState) -> Unit,
) {

    /**
     * The face the launcher is drawing, as the platform reports it, or `null` when it is
     * drawing none.
     *
     * **The platform is the store**, so this is a query rather than a remembered value: a
     * component's enabled setting survives a launch, an update and a backup restore, and
     * `settings-and-about` asks the chooser to show what was *applied*. A preference beside
     * this would disagree with it the first time a write was refused.
     *
     * More than one enabled should be impossible, and if it happens the first in the
     * chooser's own order wins rather than an arbitrary one — a deterministic answer is what
     * lets the next plan settle the device instead of flickering between two.
     *
     * **Nothing enabled is `null`, not the default, and that distinction is the only way back
     * from it.** A device can reach zero enabled without this app's help — the platform parks
     * an unused component as `COMPONENT_ENABLED_STATE_DISABLED_UNTIL_USED`, which [stateOf]
     * reads as off, and a package tool can disable the one that was on. That is the state
     * [AppIconAliases] calls unrecoverable, and answering [AppIconChoice.DEFAULT] for it was
     * what made it so: the chooser marked Ink as in use, and its no-op guard then read the one
     * press that would put the launcher entry back as a press on the face already drawn and
     * refused it. `null` equals no face, so every row is pressable and the first press
     * recovers.
     */
    fun applied(): AppIconChoice? = try {
        AppIconChoice.entries.firstOrNull { AppIconAliases.isEnabled(it, read(it)) }
    } catch (failure: RuntimeException) {
        // A platform that will not say gets the default rather than a crash — and rather than
        // the `null` above — for the same reason `choose` refuses rather than throwing: this is
        // a settings row, and a reader who opened Appearance must not be shown a stack trace.
        // The default is the honest answer too, and it is a different claim from the one
        // `null` makes: a device that cannot report a component's state is one where nothing
        // has changed it, where a device that reports every component off has had them
        // changed and has no launcher entry left.
        AppIconChoice.DEFAULT
    }

    /**
     * Applies [choice], and reports whether every write landed.
     *
     * `false` is a refusal the reader is told about: `settings-and-about` says the app "says
     * the icon could not be changed and which one is still in use", and [applied] answers the
     * second half honestly because it re-reads the platform rather than trusting this call.
     */
    fun choose(choice: AppIconChoice): Boolean {
        for (step in AppIconAliases.plan(choice)) {
            try {
                write(step.face, step.state)
            } catch (failure: RuntimeException) {
                // Deliberately broad, and deliberately not rethrown. `PackageManager` answers
                // a component it cannot change with a `SecurityException` or an
                // `IllegalArgumentException` depending on why, some launchers' own restrictions
                // surface as neither, and a reader who taps an icon must not be shown a crash
                // for it. The refusal path exists for exactly this.
                return false
            }
        }
        return true
    }

    companion object {
        /**
         * The real one, over this app's own components.
         *
         * `context.packageName` rather than a literal: the debug build carries a `.debug`
         * suffix, and a hard-coded package would silently address the release app's
         * components — or nothing at all.
         */
        fun of(context: Context): AppIconSwitcher {
            val packages = context.packageManager
            fun component(face: AppIconChoice) =
                ComponentName(context.packageName, face.componentClassName)
            return AppIconSwitcher(
                read = { face -> stateOf(packages.getComponentEnabledSetting(component(face))) },
                write = { face, state ->
                    packages.setComponentEnabledSetting(
                        component(face),
                        flagOf(state),
                        PackageManager.DONT_KILL_APP,
                    )
                },
            )
        }

        /** What the platform reports, as the three states the planner speaks in. */
        private fun stateOf(flag: Int): AppIconAliasState = when (flag) {
            PackageManager.COMPONENT_ENABLED_STATE_ENABLED -> AppIconAliasState.ENABLED
            // Three flags mean "off", and the two beyond the plain one are the platform's own
            // doing: a reader disabling a component and the system parking an unused one. All
            // three are "not on the launcher", and treating an unrecognised value as DEFAULT
            // means a future flag reads as the manifest's answer rather than as nothing.
            PackageManager.COMPONENT_ENABLED_STATE_DISABLED,
            PackageManager.COMPONENT_ENABLED_STATE_DISABLED_USER,
            PackageManager.COMPONENT_ENABLED_STATE_DISABLED_UNTIL_USED,
            -> AppIconAliasState.DISABLED
            else -> AppIconAliasState.DEFAULT
        }

        /** And back, for a write. */
        private fun flagOf(state: AppIconAliasState): Int = when (state) {
            AppIconAliasState.DEFAULT -> PackageManager.COMPONENT_ENABLED_STATE_DEFAULT
            AppIconAliasState.ENABLED -> PackageManager.COMPONENT_ENABLED_STATE_ENABLED
            AppIconAliasState.DISABLED -> PackageManager.COMPONENT_ENABLED_STATE_DISABLED
        }
    }
}
