package com.omnirunner.watch.ui.theme

import androidx.compose.runtime.Composable
import androidx.wear.compose.material.MaterialTheme
import androidx.wear.compose.material.Colors
import androidx.compose.ui.graphics.Color

private val OmniRunnerColors = Colors(
    primary = Color(0xFF4CAF50),
    primaryVariant = Color(0xFF388E3C),
    secondary = Color(0xFF03DAC6),
    secondaryVariant = Color(0xFF018786),
    error = Color(0xFFCF6679),
    onPrimary = Color.Black,
    onSecondary = Color.Black,
    onError = Color.Black,
    background = Color.Black,
    onBackground = Color.White,
    surface = Color(0xFF1E1E1E),
    onSurface = Color.White,
    onSurfaceVariant = Color(0xFFB0BEC5),
)

@Composable
fun OmniRunnerWatchTheme(
    content: @Composable () -> Unit,
) {
    MaterialTheme(
        colors = OmniRunnerColors,
        content = content,
    )
}
