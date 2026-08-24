plugins {
    alias(libs.plugins.android.library)
}

android {
    namespace = "app.storyarc.core.format"
    compileSdk = 37
    // Pinned because this module compiles vendored C. Letting AGP pick its
    // default would mean the toolchain that built libarchive changes with the
    // plugin version, silently, and a miscompile there is a corrupt page rather
    // than a build error.
    ndkVersion = "28.2.13676358"
    defaultConfig {
        minSdk = 31
        testInstrumentationRunner = "androidx.test.runner.AndroidJUnitRunner"
    }

    // The vendored libarchive RAR readers, compiled from the same sources SwiftPM
    // compiles for iOS. One copy under third_party/, referenced rather than
    // duplicated — see third_party/libarchive/VENDORING.md.
    externalNativeBuild {
        cmake {
            path = file("src/main/cpp/CMakeLists.txt")
        }
    }

    // The shared corpus lives outside this module (ADR-0001). Instrumented tests
    // run on a device, so the fixtures have to travel with the test APK.
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
}

// The fixture corpus lives outside this module — both platforms read the same
// files, which is what stops the two implementations from privately disagreeing
// about what a correct parse is (ADR-0001). `java.util.zip.ZipFile` needs a real
// path rather than a classpath stream, so the location is handed to the test JVM
// as a property instead of being copied into test resources.
tasks.withType<Test>().configureEach {
    systemProperty(
        "storyarc.fixtures",
        rootProject.layout.projectDirectory.dir("../../packages/test-fixtures").asFile.absolutePath,
    )
}

dependencies {
    implementation(project(":core:model"))
    // Flow, for LibraryScanner. Already a main dependency of :core:model and on
    // the app's classpath through Compose, so this declares what is used rather
    // than adding anything to the build.
    implementation(libs.kotlinx.coroutines.core)

    testImplementation(libs.junit)
    // runBlocking, for driving the suspending reader from JVM unit tests.
    testImplementation(libs.kotlinx.coroutines.test)

    androidTestImplementation(libs.androidx.test.junit)
    // Explicit: androidx.test.ext:junit does not pull the runner in, and the
    // testInstrumentationRunner above names a class from it.
    androidTestRuntimeOnly(libs.androidx.test.runner)
    androidTestImplementation(libs.kotlinx.coroutines.test)
    // Runtime only — the JsonElement API needs no serialization compiler plugin,
    // so reading the fixture manifest costs no build configuration.
    testImplementation(libs.kotlinx.serialization.json)
}
