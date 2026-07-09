plugins {
    id("com.android.application")
    id("kotlin-android")
    // The Flutter Gradle Plugin must be applied after the Android and Kotlin Gradle plugins.
    id("dev.flutter.flutter-gradle-plugin")
}

android {
    namespace = "com.zoneroyale.zone_royale"
    compileSdk = flutter.compileSdkVersion
    ndkVersion = flutter.ndkVersion

    compileOptions {
        sourceCompatibility = JavaVersion.VERSION_17
        targetCompatibility = JavaVersion.VERSION_17
    }

    kotlinOptions {
        jvmTarget = JavaVersion.VERSION_17.toString()
    }

    defaultConfig {
        // TODO: Specify your own unique Application ID (https://developer.android.com/studio/build/application-id.html).
        applicationId = "com.zoneroyale.zone_royale"
        // You can update the following values to match your application needs.
        // For more information, see: https://flutter.dev/to/review-gradle-config.
        minSdk = flutter.minSdkVersion
        targetSdk = flutter.targetSdkVersion
        versionCode = flutter.versionCode
        versionName = flutter.versionName

        // Build native code only for real ARM phones (your device is arm64).
        // This skips the x86/x86_64 emulator builds — the x86 one was crashing
        // the audio engine's CMake step. For the Play Store, ship an app bundle
        // (.aab) which includes all ABIs; add "armeabi-v7a" for old 32-bit phones.
        ndk {
            abiFilters.add("arm64-v8a")
        }
    }

    buildTypes {
        release {
            // TODO: Add your own signing config for the release build.
            // Signing with the debug keys for now, so `flutter run --release` works.
            signingConfig = signingConfigs.getByName("debug")
            // The antivirus on this machine deletes the R8-optimized classes.dex
            // mid-build (obfuscated dex trips a false positive), which crashes
            // :app:packageRelease. Disabling R8/shrinking avoids that step and
            // builds reliably. Re-enable for a size-optimized Play Store release
            // on a machine where the antivirus won't quarantine the dex.
            isMinifyEnabled = false
            isShrinkResources = false
        }
    }
}

flutter {
    source = "../.."
}
