package com.senpai.androlaunch.companion.ui.theme

import android.os.Build
import androidx.compose.foundation.isSystemInDarkTheme
import androidx.compose.material3.MaterialTheme
import androidx.compose.material3.Shapes
import androidx.compose.material3.Typography
import androidx.compose.material3.darkColorScheme
import androidx.compose.material3.dynamicDarkColorScheme
import androidx.compose.material3.dynamicLightColorScheme
import androidx.compose.material3.lightColorScheme
import androidx.compose.runtime.Composable
import androidx.compose.ui.graphics.Color
import androidx.compose.ui.platform.LocalContext

// Brand green sampled from the AndroLaunch app icon (fallback palette below API 31).
private val Brand = Color(0xFF4CB250)
private val BrandBright = Color(0xFF6FE07A)
private val BrandDeep = Color(0xFF1F5A28)

private val LightColors = lightColorScheme(
    primary = Color(0xFF2F7D36),
    onPrimary = Color.White,
    primaryContainer = Color(0xFFB7F0B9),
    onPrimaryContainer = Color(0xFF002105),
    secondary = Brand,
    onSecondary = Color.White,
    secondaryContainer = Color(0xFFD6F5D6),
    onSecondaryContainer = Color(0xFF06210A),
    tertiary = BrandDeep,
    onTertiary = Color.White,
    background = Color(0xFFFBFDF8),
    onBackground = Color(0xFF191C19),
    surface = Color(0xFFFBFDF8),
    onSurface = Color(0xFF191C19),
    surfaceVariant = Color(0xFFDDE5DB),
    onSurfaceVariant = Color(0xFF414941),
    surfaceContainerLowest = Color(0xFFFFFFFF),
    surfaceContainerLow = Color(0xFFF3F8F1),
    surfaceContainer = Color(0xFFEDF3EB),
    surfaceContainerHigh = Color(0xFFE7EDE5),
    surfaceContainerHighest = Color(0xFFE1E7DF),
    surfaceDim = Color(0xFFD9DFD6),
    surfaceBright = Color(0xFFFBFDF8),
    outline = Color(0xFF717971),
    outlineVariant = Color(0xFFC1C9BF),
    error = Color(0xFFBA1A1A),
    onError = Color.White,
    errorContainer = Color(0xFFFFDAD6),
    onErrorContainer = Color(0xFF410002),
)

private val DarkColors = darkColorScheme(
    primary = BrandBright,
    onPrimary = Color(0xFF00390F),
    primaryContainer = BrandDeep,
    onPrimaryContainer = Color(0xFFB7F0B9),
    secondary = Brand,
    onSecondary = Color(0xFF00390F),
    secondaryContainer = Color(0xFF2C5A31),
    onSecondaryContainer = Color(0xFFD6F5D6),
    tertiary = BrandBright,
    onTertiary = Color(0xFF00390F),
    background = Color(0xFF111411),
    onBackground = Color(0xFFE2E3DD),
    surface = Color(0xFF111411),
    onSurface = Color(0xFFE2E3DD),
    surfaceVariant = Color(0xFF414941),
    onSurfaceVariant = Color(0xFFC1C9BF),
    surfaceContainerLowest = Color(0xFF0C0F0C),
    surfaceContainerLow = Color(0xFF191D19),
    surfaceContainer = Color(0xFF1D221D),
    surfaceContainerHigh = Color(0xFF282D28),
    surfaceContainerHighest = Color(0xFF323732),
    surfaceDim = Color(0xFF111411),
    surfaceBright = Color(0xFF373C37),
    outline = Color(0xFF8B938A),
    outlineVariant = Color(0xFF414941),
    error = Color(0xFFFFB4AB),
    onError = Color(0xFF690005),
    errorContainer = Color(0xFF93000A),
    onErrorContainer = Color(0xFFFFDAD6),
)

/**
 * Material 3 theme for AndroLaunch Comp.
 *
 * On Android 12+ the palette comes from the user's wallpaper (Material You
 * dynamic colour). Below Android 12 it falls back to the brand-green scheme so
 * the product still looks like AndroLaunch.
 */
@Composable
fun AndroLaunchTheme(
    darkTheme: Boolean = isSystemInDarkTheme(),
    dynamicColor: Boolean = true,
    content: @Composable () -> Unit,
) {
    val context = LocalContext.current
    val colorScheme = when {
        dynamicColor && Build.VERSION.SDK_INT >= Build.VERSION_CODES.S -> {
            if (darkTheme) dynamicDarkColorScheme(context) else dynamicLightColorScheme(context)
        }
        darkTheme -> DarkColors
        else -> LightColors
    }
    MaterialTheme(
        colorScheme = colorScheme,
        typography = Typography(),
        shapes = Shapes(),
        content = content,
    )
}
