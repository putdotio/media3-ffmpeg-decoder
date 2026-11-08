pluginManagement {
    repositories {
        google()
        mavenCentral()
        gradlePluginPortal()
    }
}

dependencyResolutionManagement {
    repositoriesMode = RepositoriesMode.FAIL_ON_PROJECT_REPOS
    repositories {
        google()
        mavenCentral()
    }
    versionCatalogs {
        create("media3") {
            from(files("media/gradle/libs.versions.toml"))
        }
    }
}

rootProject.name = "media3-ffmpeg-decoder"
