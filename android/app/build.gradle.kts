plugins {
    id("com.android.application")
    id("kotlin-android")
    // The Flutter Gradle Plugin must be applied after the Android and Kotlin Gradle plugins.
    id("dev.flutter.flutter-gradle-plugin")
}

android {
    namespace = "com.saleem.videoeditor"
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
        applicationId = "com.saleem.videoeditor"
        // You can update the following values to match your application needs.
        // For more information, see: https://flutter.dev/to/review-gradle-config.
        // FFmpeg Kit and the media3-backed video player both require API 24+.
        minSdk = 24
        targetSdk = flutter.targetSdkVersion
        versionCode = flutter.versionCode
        versionName = flutter.versionName
    }

    packaging {
        // FFmpeg ships prebuilt .so files per ABI; keep them uncompressed so
        // the loader can mmap them directly.
        jniLibs {
            useLegacyPackaging = false

            // Those libraries are ~90 MB each, so a debug APK carrying every
            // ABI is ~355 MB and will not install on an emulator with a small
            // data partition. Setting SV_ABI keeps just that one. Excluding
            // here rather than via abiFilters because the Flutter Gradle
            // plugin rewrites abiFilters after this block runs.
            System.getenv("SV_ABI")?.let { keep ->
                listOf("arm64-v8a", "armeabi-v7a", "x86_64", "x86")
                    .filter { it != keep }
                    .forEach { excludes += "lib/$it/**" }
            }
        }
    }

    buildTypes {
        release {
            // TODO: Add your own signing config for the release build.
            // Signing with the debug keys for now, so `flutter run --release` works.
            signingConfig = signingConfigs.getByName("debug")
        }
    }
}

flutter {
    source = "../.."
}
