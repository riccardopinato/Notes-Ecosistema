package it.notes.ecosystem.ui

import androidx.compose.foundation.shape.RoundedCornerShape
import androidx.compose.material3.*
import androidx.compose.runtime.Composable
import androidx.compose.ui.graphics.Color
import androidx.compose.ui.text.TextStyle
import androidx.compose.ui.text.font.FontFamily
import androidx.compose.ui.text.font.FontWeight
import androidx.compose.ui.unit.dp
import androidx.compose.ui.unit.sp

private val Day = lightColorScheme(
    primary = Color(0xFF3559E0), onPrimary = Color.White,
    primaryContainer = Color(0xFFE1E7FF), onPrimaryContainer = Color(0xFF182B75),
    secondary = Color(0xFF69574B), secondaryContainer = Color(0xFFF0E4D9),
    onSecondaryContainer = Color(0xFF34281F),
    background = Color(0xFFF6F4EF), onBackground = Color(0xFF17212B),
    surface = Color(0xFFFFFDFA), onSurface = Color(0xFF17212B),
    surfaceVariant = Color(0xFFEBE8E1), onSurfaceVariant = Color(0xFF555D65),
    surfaceContainer = Color(0xFFF0EEE8), surfaceContainerLow = Color(0xFFF9F7F2),
    surfaceContainerHigh = Color(0xFFEAE7E0), outline = Color(0xFF777D84),
    outlineVariant = Color(0xFFDCDAD3),
)
private val Night = darkColorScheme(
    primary = Color(0xFFADBEFF), onPrimary = Color(0xFF14276C),
    primaryContainer = Color(0xFF293C79), onPrimaryContainer = Color(0xFFE1E7FF),
    secondary = Color(0xFFDFC1A9), secondaryContainer = Color(0xFF44382F),
    onSecondaryContainer = Color(0xFFF1DDCD),
    background = Color(0xFF111820), onBackground = Color(0xFFF0F3F7),
    surface = Color(0xFF1B2632), onSurface = Color(0xFFF0F3F7),
    surfaceVariant = Color(0xFF293541), onSurfaceVariant = Color(0xFFBDC7D1),
    surfaceContainer = Color(0xFF19232E), surfaceContainerLow = Color(0xFF16202A),
    surfaceContainerHigh = Color(0xFF26323E), outline = Color(0xFF8B98A5),
    outlineVariant = Color(0xFF3A4754),
)
private val EditorialType = Typography(
    headlineLarge = TextStyle(fontFamily = FontFamily.Serif, fontWeight = FontWeight.Medium, fontSize = 36.sp, lineHeight = 42.sp),
    headlineMedium = TextStyle(fontFamily = FontFamily.Serif, fontWeight = FontWeight.Medium, fontSize = 30.sp, lineHeight = 36.sp),
    headlineSmall = TextStyle(fontFamily = FontFamily.Serif, fontWeight = FontWeight.Medium, fontSize = 25.sp, lineHeight = 32.sp),
    displayMedium = TextStyle(fontFamily = FontFamily.Serif, fontWeight = FontWeight.Medium, fontSize = 48.sp, lineHeight = 56.sp),
    titleLarge = TextStyle(fontWeight = FontWeight.SemiBold, fontSize = 22.sp, lineHeight = 28.sp),
    titleMedium = TextStyle(fontWeight = FontWeight.SemiBold, fontSize = 18.sp, lineHeight = 25.sp),
    bodyLarge = TextStyle(fontSize = 17.sp, lineHeight = 27.sp),
    bodyMedium = TextStyle(fontSize = 15.sp, lineHeight = 23.sp),
)

@Composable
fun NotesTheme(dark: Boolean, content: @Composable () -> Unit) {
    MaterialTheme(colorScheme = if (dark) Night else Day, typography = EditorialType,
        shapes = Shapes(small = RoundedCornerShape(12.dp), medium = RoundedCornerShape(20.dp),
            large = RoundedCornerShape(28.dp), extraLarge = RoundedCornerShape(32.dp)), content = content)
}
