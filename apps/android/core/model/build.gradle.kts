plugins {
    alias(libs.plugins.android.library)
    alias(libs.plugins.kotlin.serialization)
}

android {
    namespace = "app.storyarc.core.model"
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

// `AppIconManifestTest` is a source-level guard: it reads `:app`'s manifest and its icon
// resources, and the brand generator's own palette, and asserts they agree with
// `AppIconChoice`. Nothing else can — no compiler reads a resource XML, no compiler reads a
// Swift script, and a typo in an alias name is a chooser that throws on the one press it
// exists for.
//
// The Android root is *handed over* rather than discovered, the way
// `:core:designsystem`'s arc-stops guard has it: a walk up from the working directory
// escapes a worktree. And every file the guard reads is declared a task input — a `Test`
// task's inputs are its classpath and its candidate classes, never another module's
// resources, so without this the guard sits UP-TO-DATE while the manifest it guards changes.
tasks.withType<Test>().configureEach {
    systemProperty("storyarc.repoRootDir", rootDir.parentFile.parentFile.absolutePath)
    // `inputs.files` rather than `inputs.file`: a guarded file going missing should reach the
    // test, which says what it was looking for, rather than failing input snapshotting with a
    // path and no explanation.
    inputs.files(
        files(
            "$rootDir/app/src/main/AndroidManifest.xml",
            "$rootDir/app/src/main/res/values/colors.xml",
            "$rootDir/app/src/main/res/mipmap-anydpi-v26",
            "${rootDir.parentFile.parentFile}/scripts/brand-mark.swift",
        ),
    )
        .withPropertyName("appIconGuardSources")
        .withPathSensitivity(PathSensitivity.RELATIVE)
}

dependencies {
    implementation(libs.kotlinx.coroutines.core)
    // `api`, not `implementation`: the persistence layer serialises these types, so
    // the annotations and the serializers have to be visible to it.
    api(libs.kotlinx.serialization.json)

    testImplementation(libs.junit)
    testImplementation(libs.kotlinx.coroutines.test)
}
