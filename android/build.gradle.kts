plugins {
    id("com.android.application") version "8.11.1" apply false
    id("com.android.library") version "8.11.1" apply false
    
    // Sửa từ 1.9.22 thành 2.1.0 ở đây
    id("org.jetbrains.kotlin.android") version "2.1.0" apply false 
    
    id("com.google.gms.google-services") version "4.4.1" apply false
}

allprojects {
    repositories {
        google()
        mavenCentral()
    }
}

// Cấu hình lại thư mục build để tránh lỗi đường dẫn dài trên Windows/MacOS
val newBuildDir: Directory =
    rootProject.layout.buildDirectory
        .dir("../../build")
        .get()
rootProject.layout.buildDirectory.value(newBuildDir)

subprojects {
    val newSubprojectBuildDir: Directory = newBuildDir.dir(project.name)
    project.layout.buildDirectory.value(newSubprojectBuildDir)
}

subprojects {
    project.evaluationDependsOn(":app")
}

tasks.register<Delete>("clean") {
    delete(rootProject.layout.buildDirectory)
}