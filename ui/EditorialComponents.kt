package it.notes.ecosystem.ui

import androidx.compose.foundation.BorderStroke
import androidx.compose.foundation.layout.*
import androidx.compose.foundation.shape.RoundedCornerShape
import androidx.compose.material.icons.Icons
import androidx.compose.material.icons.filled.*
import androidx.compose.material3.*
import androidx.compose.runtime.Composable
import androidx.compose.ui.Modifier
import androidx.compose.ui.platform.LocalDensity
import androidx.compose.ui.text.font.FontFamily
import androidx.compose.ui.text.style.TextOverflow
import androidx.compose.ui.unit.dp
import androidx.compose.ui.unit.sp
import java.time.Instant
import java.time.ZoneId
import java.time.format.DateTimeFormatter
import java.util.Locale

@Composable
internal fun EditorialEyebrow(text: String, modifier: Modifier = Modifier) {
    Text(text, modifier, style = MaterialTheme.typography.labelSmall, letterSpacing = 1.5.sp,
        color = LocalContentColor.current.copy(alpha = 0.85f))
}
@Composable
internal fun EditorialBadge(text: String, emphasized: Boolean = false, warning: Boolean = false) {
    Surface(shape = RoundedCornerShape(10.dp), color = when {
        warning -> MaterialTheme.colorScheme.errorContainer
        emphasized -> MaterialTheme.colorScheme.primaryContainer
        else -> MaterialTheme.colorScheme.surfaceContainer
    }, contentColor = when {
        warning -> MaterialTheme.colorScheme.onErrorContainer
        emphasized -> MaterialTheme.colorScheme.onPrimaryContainer
        else -> MaterialTheme.colorScheme.onSurfaceVariant
    }) { Text(text, Modifier.padding(horizontal = 10.dp, vertical = 6.dp), style = MaterialTheme.typography.labelMedium) }
}
@Composable
internal fun EditorialSection(title: String, detail: String? = null) {
    Column(Modifier.padding(top = 8.dp, bottom = 4.dp), verticalArrangement = Arrangement.spacedBy(4.dp)) {
        Text(title, style = MaterialTheme.typography.headlineSmall)
        detail?.let { Text(it, style = MaterialTheme.typography.bodyMedium, color = MaterialTheme.colorScheme.onSurfaceVariant) }
    }
}
@Composable
internal fun EcosystemNavigation(selected: String, enabled: Boolean = true, onSelect: (String) -> Unit) {
    Surface(color = MaterialTheme.colorScheme.surface, border = BorderStroke(1.dp, MaterialTheme.colorScheme.outlineVariant)) {
        NavigationBar(containerColor = MaterialTheme.colorScheme.surface, tonalElevation = 0.dp) {
            listOf("Home" to Icons.Default.Home, "Note" to Icons.Default.Description, "Diario" to Icons.Default.CalendarMonth, "Attività" to Icons.Default.CheckCircle,
                "Cerca" to Icons.Default.Search).forEach { (label, icon) ->
                NavigationBarItem(selected = (if(selected=="Raccolte") "Note" else selected) == label, enabled = enabled, onClick = { onSelect(label) },
                    icon = { Icon(icon, contentDescription = null) }, label = { Text(label, maxLines = 1) },
                    colors = NavigationBarItemDefaults.colors(indicatorColor = MaterialTheme.colorScheme.primaryContainer,
                        selectedIconColor = MaterialTheme.colorScheme.onPrimaryContainer, selectedTextColor = MaterialTheme.colorScheme.primary))
            }
        }
    }
}
internal fun editorialDate(timestamp: Long): String = Instant.ofEpochMilli(timestamp).atZone(ZoneId.systemDefault())
    .format(DateTimeFormatter.ofPattern("d MMM yyyy", Locale.ITALIAN))

@Composable
internal fun EditorialAppTitle(title: String, eyebrow: String = "NOTES / ECOSISTEMA") {
    Column {
        if (LocalDensity.current.fontScale <= 1.3f) EditorialEyebrow(eyebrow)
        Text(title, style = MaterialTheme.typography.titleLarge, fontFamily = FontFamily.Serif,
            maxLines = 1, overflow = TextOverflow.Ellipsis)
    }
}
internal fun editorialDue(value: String): String = java.time.LocalDate.parse(value)
    .format(DateTimeFormatter.ofPattern("d MMM yyyy", Locale.ITALIAN))
