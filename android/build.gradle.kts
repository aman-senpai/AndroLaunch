// Root build file for the AndroLaunch Comp Android companion.
//
// The companion UI is Jetpack Compose (Kotlin, Material 3); the daemon,
// notification and call layers remain plain Java so the ADB protocol code did
// not have to change for the UI migration.
plugins {
    id("com.android.application") version "8.7.3" apply false
    id("org.jetbrains.kotlin.android") version "2.0.21" apply false
    id("org.jetbrains.kotlin.plugin.compose") version "2.0.21" apply false
}
