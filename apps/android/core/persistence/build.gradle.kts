plugins {
    alias(libs.plugins.android.library)
    alias(libs.plugins.kotlin.serialization)
    alias(libs.plugins.ksp)
}

android {
    namespace = "app.storyarc.core.persistence"
    compileSdk = 37
    defaultConfig {
        minSdk = 31
        testInstrumentationRunner = "androidx.test.runner.AndroidJUnitRunner"
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
}

// `LibraryTransferTest` opens the committed sealed-secrets vector, the one both platforms and a
// third implementation agree on. The repository root is handed over rather than discovered, the
// way `:core:model` does it: a walk up from the working directory escapes a worktree. The file is
// a declared input, so the test does not sit UP-TO-DATE when the vector changes.
tasks.withType<Test>().configureEach {
    systemProperty("storyarc.repoRootDir", rootDir.parentFile.parentFile.absolutePath)
    inputs.files("${rootDir.parentFile.parentFile}/packages/test-fixtures/library/sealed-secrets.json")
        .withPropertyName("sealedSecretsVector")
        .withPathSensitivity(PathSensitivity.RELATIVE)
}

dependencies {
    implementation(project(":core:model"))

    // ADR-0006 names Room here and SwiftData on iOS. The schema semantics are
    // shared; the implementations are not.
    implementation(libs.androidx.room.runtime)
    implementation(libs.androidx.room.ktx)
    ksp(libs.androidx.room.compiler)

    testImplementation(libs.junit)
    testImplementation(libs.kotlinx.coroutines.test)
    // 10.10: RememberedFilesTest is this module's first use of android.net.Uri in a unit
    // test, which the plain JVM test jar stubs out entirely.
    testImplementation(libs.robolectric)

    androidTestImplementation(libs.androidx.test.junit)
    androidTestImplementation(libs.androidx.test.runner)
    androidTestImplementation(libs.kotlinx.coroutines.test)
}
