plugins {
    alias(libs.plugins.android.library)
}

android {
    namespace = "app.storyarc.core.smb"
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

    packaging {
        resources {
            // Two libraries can each ship one, and two of the same file is a packaging
            // error rather than a choice to make.
            excludes += "META-INF/DEPENDENCIES"
        }
    }
}

// `SmbDiscoveryResolverTest` reads this module's own source, because the rule it guards is an
// identity rule about an `NsdManager` call and this module has JUnit alone. The source
// directory is declared an input as well: a `Test` task's inputs are its classpath and its
// candidate classes, never the module's Kotlin sources, so nothing otherwise ties this task's
// up-to-date check to the tree it reads -- and the guard is only worth having if editing that
// file re-runs it.
tasks.withType<Test>().configureEach {
    systemProperty("storyarc.smb.projectDir", projectDir.absolutePath)
    inputs.files(layout.projectDirectory.dir("src/main/kotlin"))
        .withPropertyName("smbDiscoverySources")
        .withPathSensitivity(PathSensitivity.RELATIVE)
}

dependencies {
    api(project(":core:format"))
    // `ShareTransport`, which `SmbIdentity` hands to callers, so that this client and the
    // two screens that state what it negotiated read one type. Pure Kotlin.
    api(project(":core:model"))
    // SMB 2 and 3, with SMB 3 transport encryption. Its own runtime dependencies are
    // Bouncy Castle (the ciphers), asn-one (SPNEGO), MBassador (events) and the SLF4J API.
    // ADR-0019 records the swap from jcifs-ng.
    implementation(libs.smbj)
    implementation(libs.kotlinx.coroutines.core)

    testImplementation(libs.junit)
    testImplementation(libs.kotlinx.coroutines.test)
}
