package com.senpai.androlaunch.companion

import android.os.Bundle
import androidx.activity.ComponentActivity
import androidx.activity.compose.setContent
import androidx.activity.enableEdgeToEdge
import com.senpai.androlaunch.companion.ui.CompanionApp
import com.senpai.androlaunch.companion.ui.theme.AndroLaunchTheme

/**
 * Compose host for the AndroLaunch Comp companion.
 *
 * The native Android/Java daemon (CompanionService), notification relay and call
 * monitor stay as-is; this activity is the Material 3 control surface.
 */
class MainActivity : ComponentActivity() {

    override fun onCreate(savedInstanceState: Bundle?) {
        super.onCreate(savedInstanceState)
        enableEdgeToEdge()
        setContent {
            AndroLaunchTheme {
                CompanionApp()
            }
        }
    }
}
