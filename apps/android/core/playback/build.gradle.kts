plugins {
    alias(libs.plugins.android.library)
}

android {
    namespace = "app.storyarc.core.playback"
    compileSdk = 37
    defaultConfig {
        minSdk = 31
        testInstrumentationRunner = "androidx.test.runner.AndroidJUnitRunner"
    }

    // The audio fixtures, as assets of the instrumented suite. `ChapterMarks` needs the
    // platform's own MP4 extractor, so a real M4B on a real device is the only way to prove
    // that a chaptered container names its chapters before it plays. `:core:format` shares
    // the same corpus the same way.
    sourceSets {
        getByName("androidTest") {
            assets.srcDir(
                rootProject.layout.projectDirectory.dir("../../packages/test-fixtures")
            )
        }
    }

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

    // `MediaItem.Builder.setUri(String)` calls `Uri.parse`, and the unit-test JVM has no
    // implementation of it. Robolectric supplies the Android runtime rather than
    // `isReturnDefaultValues`, which would make every unmocked platform call answer null
    // in silence — including ones a test meant to exercise.
    testOptions { unitTests { isIncludeAndroidResources = true } }
}

dependencies {
    implementation(project(":core:model"))
    implementation(libs.kotlinx.coroutines.core)

    // The decoder and the platform's media contract. `api`, not `implementation`, for
    // the session: the app module builds a `MediaController` against the service this
    // module declares, and a `SessionToken` on a public signature has to be on the
    // consumer's compile classpath.
    implementation(libs.androidx.media3.exoplayer)
    implementation(libs.androidx.media3.inspector)
    api(libs.androidx.media3.session)

    testImplementation(libs.junit)
    testImplementation(libs.kotlinx.coroutines.test)
    testImplementation(libs.robolectric)

    androidTestImplementation(libs.androidx.test.junit)
    androidTestRuntimeOnly(libs.androidx.test.runner)
    androidTestImplementation(libs.kotlinx.coroutines.test)
}
