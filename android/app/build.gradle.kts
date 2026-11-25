plugins {
    alias(libs.plugins.android.application)
    alias(libs.plugins.kotlin.compose)
}

// One version for every platform, from the VERSION file at the repository root.
val appVersion = rootProject.file("../VERSION").readText().trim()

android {
    namespace = "com.lazyscan.lazyscan"
    compileSdk = 37

    defaultConfig {
        applicationId = "com.lazyscan.lazyscan"
        minSdk = 26
        targetSdk = 37
        versionCode = 1
        versionName = appVersion
        ndk {
            abiFilters += setOf("arm64-v8a", "x86_64")
        }
    }

    signingConfigs {
        // The upload key lives outside the repository; its path and passwords come from ~/.gradle/gradle.properties.
        findProperty("lazyscanKeystore")?.let { keystore ->
            create("upload") {
                storeFile = file(keystore as String)
                storePassword = findProperty("lazyscanStorePassword") as String
                keyAlias = findProperty("lazyscanKeyAlias") as String
                keyPassword = findProperty("lazyscanKeyPassword") as String
            }
        }
    }

    buildTypes {
        debug {
            applicationIdSuffix = ".debug"
            versionNameSuffix = "-debug"
        }
        release {
            isMinifyEnabled = true
            isShrinkResources = true
            proguardFiles(getDefaultProguardFile("proguard-android-optimize.txt"), "proguard-rules.pro")
            signingConfig = signingConfigs.findByName("upload")
        }
    }

    compileOptions {
        sourceCompatibility = JavaVersion.VERSION_17
        targetCompatibility = JavaVersion.VERSION_17
    }

    buildFeatures {
        buildConfig = true
        compose = true
    }
}

dependencies {
    implementation(platform(libs.compose.bom))
    implementation(libs.compose.ui)
    implementation(libs.compose.material3)
    implementation(libs.activity.compose)

    testImplementation(libs.junit)
}
