plugins {
    alias(libs.plugins.android.library)
}

android {
    namespace = "app.storyarc.core.playback"
    compileSdk = 37
    defaultConfig { minSdk = 31 }

    compileOptions {
        sourceCompatibility = JavaVersion.VERSION_21
        targetCompatibility = JavaVersion.VERSION_21
    }

    kotlin {
        compilerOptions {
            jvmTarget.set(org.jetbrains.kotlin.gradle.dsl.JvmTarget.JVM_21)
            allWarningsAsErrors.set(true)
        }
    }
}

dependencies {
    implementation(project(":core:model"))
    implementation(libs.kotlinx.coroutines.core)

    // The decoder and the platform's media contract. `api`, not `implementation`, for
    // the session: the app module builds a `MediaController` against the service this
    // module declares, and a `SessionToken` on a public signature has to be on the
    // consumer's compile classpath.
    implementation(libs.androidx.media3.exoplayer)
    api(libs.androidx.media3.session)

    testImplementation(libs.junit)
    testImplementation(libs.kotlinx.coroutines.test)
}
