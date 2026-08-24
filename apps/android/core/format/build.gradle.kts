plugins {
    alias(libs.plugins.android.library)
}

android {
    namespace = "app.storyarc.core.format"
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

    testImplementation(libs.junit)
    // Runtime only — the JsonElement API needs no serialization compiler plugin,
    // so reading the fixture manifest costs no build configuration.
    testImplementation(libs.kotlinx.serialization.json)
}
