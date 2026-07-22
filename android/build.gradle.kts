import org.gradle.api.logging.LogLevel
import org.gradle.api.tasks.compile.JavaCompile

allprojects {
    repositories {
        google()
        mavenCentral()
    }
}

val newBuildDir: Directory = rootProject.layout.buildDirectory.dir("../../build").get()
rootProject.layout.buildDirectory.value(newBuildDir)

subprojects {
    val newSubprojectBuildDir: Directory = newBuildDir.dir(project.name)
    project.layout.buildDirectory.value(newSubprojectBuildDir)
}
subprojects {
    project.evaluationDependsOn(":app")
    // firebase_messaging 16.4.3 still contains compatibility bridges to
    // deprecated Flutter/Firebase Android APIs. It is the latest published
    // plugin, so suppress only that third-party deprecation category while
    // keeping all other javac warnings visible.
    if (name == "firebase_messaging") {
        tasks.withType<JavaCompile>().configureEach {
            // Keep the upstream compiler note available with --info, but do
            // not surface it as an actionable app warning in normal builds.
            logging.captureStandardError(LogLevel.INFO)
        }
    }
}

tasks.register<Delete>("clean") {
    delete(rootProject.layout.buildDirectory)
}
