plugins {
    id("com.android.application")
    id("org.jetbrains.kotlin.android")
    id("dev.flutter.flutter-gradle-plugin") // Dòng này cực kỳ quan trọng
    id("com.google.gms.google-services")
}

android {
    namespace = "vn.edu.vinhuni.studentapp"
    compileSdk = flutter.compileSdkVersion
    ndkVersion = flutter.ndkVersion

    compileOptions {
        sourceCompatibility = JavaVersion.VERSION_11
        targetCompatibility = JavaVersion.VERSION_11
    }

    kotlinOptions {
        // Nâng cấp lên 11 để tương thích với Kotlin 2.1.0 và chip M4
        jvmTarget = "11" 
    }

    defaultConfig {
        applicationId = "vn.edu.vinhuni.studentapp"
        minSdk = flutter.minSdkVersion // Hoặc flutter.minSdkVersion
        targetSdk = flutter.targetSdkVersion
        versionCode = flutter.versionCode
        versionName = flutter.versionName
    }

    buildTypes {
        getByName("release") {
            // Lưu ý: Sau này bạn nên thay bằng signingConfigs.getByName("release")
            signingConfig = signingConfigs.getByName("debug") 
            isMinifyEnabled = false
            isShrinkResources = false
        }
    }
}

dependencies {
    implementation(platform("com.google.firebase:firebase-bom:33.1.0"))
    implementation("com.google.firebase:firebase-messaging-ktx") // Thêm -ktx cho Kotlin
}

flutter {
    source = "../.."
}
