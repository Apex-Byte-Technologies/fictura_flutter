allprojects {
    repositories {
        google()
        mavenCentral()
        // FICTURA_MAVEN_LOCAL=1: use a fictura-android from `publishToMavenLocal` (an unreleased SDK change).
        if (System.getenv("FICTURA_MAVEN_LOCAL") == "1") mavenLocal()
    }
}

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
