package app.storyarc.core.persistence

import android.content.SharedPreferences

/**
 * A [SharedPreferences] that keeps its values in a map.
 *
 * Written rather than mocked because what the stores in this module are asserted on
 * is that their values actually round-trip: a mock that returns what it was told to
 * return proves nothing about the keys the store reads and writes. The interface is
 * the whole contract, so nothing here touches the framework and nothing here needs a
 * device or Robolectric.
 *
 * Shared by every store's test. It used to be private to `FinishedCleanupTest` and
 * handled one string, which is all that test needed; a second store with a dozen
 * values made one honest fake cheaper than two half ones.
 *
 * Edits apply immediately — `apply()` is asynchronous on a device and there is
 * nothing here to be asynchronous about.
 */
internal class FakePreferences : SharedPreferences {
    private val values = mutableMapOf<String, Any?>()

    override fun getAll(): MutableMap<String, *> = values.toMutableMap()

    override fun getString(key: String?, defValue: String?): String? =
        values[key] as? String ?: defValue

    @Suppress("UNCHECKED_CAST")
    override fun getStringSet(key: String?, defValues: MutableSet<String>?): MutableSet<String>? =
        values[key] as? MutableSet<String> ?: defValues

    override fun getInt(key: String?, defValue: Int): Int = values[key] as? Int ?: defValue

    override fun getLong(key: String?, defValue: Long): Long = values[key] as? Long ?: defValue

    override fun getFloat(key: String?, defValue: Float): Float = values[key] as? Float ?: defValue

    override fun getBoolean(key: String?, defValue: Boolean): Boolean =
        values[key] as? Boolean ?: defValue

    override fun contains(key: String?): Boolean = values.containsKey(key)

    override fun edit(): SharedPreferences.Editor = Editor()

    override fun registerOnSharedPreferenceChangeListener(
        listener: SharedPreferences.OnSharedPreferenceChangeListener?,
    ) = Unit

    override fun unregisterOnSharedPreferenceChangeListener(
        listener: SharedPreferences.OnSharedPreferenceChangeListener?,
    ) = Unit

    private inner class Editor : SharedPreferences.Editor {
        override fun putString(key: String?, value: String?): SharedPreferences.Editor =
            edited { set(key, value) }

        override fun putStringSet(
            key: String?,
            value: MutableSet<String>?,
        ): SharedPreferences.Editor = edited { set(key, value) }

        override fun putInt(key: String?, value: Int): SharedPreferences.Editor =
            edited { set(key, value) }

        override fun putLong(key: String?, value: Long): SharedPreferences.Editor =
            edited { set(key, value) }

        override fun putFloat(key: String?, value: Float): SharedPreferences.Editor =
            edited { set(key, value) }

        override fun putBoolean(key: String?, value: Boolean): SharedPreferences.Editor =
            edited { set(key, value) }

        override fun remove(key: String?): SharedPreferences.Editor = edited { values.remove(key) }

        override fun clear(): SharedPreferences.Editor = edited { values.clear() }

        override fun commit(): Boolean = true

        override fun apply() = Unit

        /** A null key reaches no real store either, so it is dropped rather than crashing. */
        private fun set(key: String?, value: Any?) {
            if (key != null) values[key] = value
        }

        private fun edited(change: () -> Unit): SharedPreferences.Editor {
            change()
            return this
        }
    }
}
