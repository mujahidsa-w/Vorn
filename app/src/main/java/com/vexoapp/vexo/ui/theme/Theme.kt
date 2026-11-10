package com.vexoapp.vexo.ui.theme

import androidx.compose.foundation.isSystemInDarkTheme
import androidx.compose.material3.MaterialTheme
import androidx.compose.material3.darkColorScheme
import androidx.compose.material3.lightColorScheme
import androidx.compose.runtime.Composable

private val Violet = androidx.compose.ui.graphics.Color(0xFF6C4CF1)

@Composable
fun VexoTheme(content: @Composable () -> Unit) {
    val colors = if (isSystemInDarkTheme()) {
        darkColorScheme(primary = Violet)
    } else {
        lightColorScheme(primary = Violet)
    }
    MaterialTheme(colorScheme = colors, content = content)
}
