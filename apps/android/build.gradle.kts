// AGP 9 has built-in Kotlin support: the `org.jetbrains.kotlin.android` plugin
// was removed and must not be applied. Kotlin is configured inside
// `android { kotlin { compilerOptions { } } }` per module. The Compose compiler
// is still a separate plugin.
plugins {
    alias(libs.plugins.android.application) apply false
    alias(libs.plugins.android.library) apply false
    alias(libs.plugins.kotlin.compose) apply false
}
