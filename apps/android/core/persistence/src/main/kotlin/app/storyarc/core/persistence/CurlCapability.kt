package app.storyarc.core.persistence

import android.content.Context
import android.content.SharedPreferences
import android.os.Build
import app.storyarc.core.model.CurlVerdict
import app.storyarc.core.model.canCurlOn

/**
 * What a device has shown about its own curl, kept across launches.
 *
 * Per device, because that is the scope `page-transitions` states: "a user who set Curl on a
 * capable device and later opens the library on this one reads with Slide without their stored
 * preference being overwritten". So this is what `TransitionChoices` is told, and the reader's
 * own choice is never written -- a faster phone, or a build that draws the same curl more
 * cheaply, honours a stored Curl again without asking.
 *
 * Only the measurements are stored, never the verdict derived from them. A stored verdict is a
 * second state that can disagree with the first, and a device judged by an older
 * [CurlVerdict.TOLERANCE] would keep that judgement for ever.
 *
 * The strains are joined into one string because [SharedPreferences] has no list of numbers,
 * which is the same thing `LibraryPreferences` does with the recent searches and for the same
 * reason. iOS's `CurlCapability` keeps the same record in `UserDefaults`.
 */
class CurlCapability(private val preferences: SharedPreferences) {

    /**
     * Whether this device has yet to be judged, which is what keeps the instrument running.
     *
     * False for the rest of the device's life once [CurlVerdict.TURNS] turns are in, so a
     * release build pays for the frame clock over three page turns and never again.
     */
    val isUnjudged: Boolean get() = strains().size < CurlVerdict.TURNS

    /** Whether this device has proved it cannot curl. */
    val cannotCurl: Boolean get() = CurlVerdict.cannotCurl(strains()) ?: false

    /** Takes one measured turn. A turn past the ones that decide is dropped. */
    fun record(strain: Double) {
        val all = strains()
        if (all.size >= CurlVerdict.TURNS) return
        preferences.edit().putString(STRAINS, (all + strain).joinToString(SEPARATOR)).apply()
    }

    /** Forgets what this device showed, so it is asked again. Used by the tests. */
    fun reset() {
        preferences.edit().remove(STRAINS).apply()
    }

    private fun strains(): List<Double> =
        preferences.getString(STRAINS, null)
            ?.split(SEPARATOR)
            ?.mapNotNull(String::toDoubleOrNull)
            ?: emptyList()

    companion object {
        fun open(context: Context): CurlCapability =
            CurlCapability(context.getSharedPreferences("app.storyarc.curl", Context.MODE_PRIVATE))

        private const val STRAINS = "strains"
        private const val SEPARATOR = ","
    }
}

/**
 * The whole of this device's answer about the curl: the API floor, and what the device has
 * since shown about itself.
 *
 * One function rather than the same `&&` written out in each reader, because
 * `page-transitions` states one rule and two readers have to meet it. [canCurlOn] is where
 * AGSL's `RuntimeShader` arrives; [CurlCapability] is D11's measurement. Neither writes the
 * reader's stored choice -- `TransitionChoices` falls back and leaves it alone, so a faster
 * phone honours a stored Curl again without asking.
 */
fun canCurlHere(context: Context): Boolean =
    canCurlOn(Build.VERSION.SDK_INT) && !CurlCapability.open(context).cannotCurl
