package app.storyarc.core.persistence

import android.content.SharedPreferences

/**
 * Preferences in a map.
 *
 * Every store in this module reads and writes one string, so a map is the whole of what
 * they need. Shared rather than repeated per test file: the day one of them starts using
 * `getBoolean`, there is one place to teach.
 */
internal class FakePreferences : SharedPreferences {
    private val values = mutableMapOf<String, String?>()

    override fun getString(key: String?, defValue: String?): String? = values[key] ?: defValue
    override fun contains(key: String?): Boolean = values.containsKey(key)
    override fun getAll(): MutableMap<String, *> = values
    override fun getStringSet(key: String?, defValues: MutableSet<String>?) = defValues
    override fun getInt(key: String?, defValue: Int) = defValue
    override fun getLong(key: String?, defValue: Long) = defValue
    override fun getFloat(key: String?, defValue: Float) = defValue
    override fun getBoolean(key: String?, defValue: Boolean) = defValue
    override fun registerOnSharedPreferenceChangeListener(
        listener: SharedPreferences.OnSharedPreferenceChangeListener?,
    ) = Unit
    override fun unregisterOnSharedPreferenceChangeListener(
        listener: SharedPreferences.OnSharedPreferenceChangeListener?,
    ) = Unit

    override fun edit(): SharedPreferences.Editor = Editor()

    private inner class Editor : SharedPreferences.Editor {
        override fun putString(key: String?, value: String?) =
            apply { key?.let { values[it] = value } }
        override fun putStringSet(key: String?, value: MutableSet<String>?) = this
        override fun putInt(key: String?, value: Int) = this
        override fun putLong(key: String?, value: Long) = this
        override fun putFloat(key: String?, value: Float) = this
        override fun putBoolean(key: String?, value: Boolean) = this
        override fun remove(key: String?) = apply { values.remove(key) }
        override fun clear() = apply { values.clear() }
        override fun commit() = true
        override fun apply() = Unit
    }
}
