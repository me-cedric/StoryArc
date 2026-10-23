package app.storyarc.core.designsystem.control

import androidx.compose.foundation.clickable
import androidx.compose.foundation.layout.fillMaxWidth
import androidx.compose.material3.Icon
import androidx.compose.material3.ListItem
import androidx.compose.material3.Text
import androidx.compose.runtime.Composable
import androidx.compose.ui.Modifier
import androidx.compose.ui.graphics.vector.ImageVector

/**
 * One row of a reader's menu: an icon beside words, the whole row the target.
 *
 * A whole list row is well past the platform's minimum touch size. Both readers draw the
 * same five doors with it, each naming the row from its own catalogue.
 */
@Composable
fun MenuRow(label: String, icon: ImageVector, onClick: () -> Unit) {
    ListItem(
        leadingContent = { Icon(imageVector = icon, contentDescription = null) },
        modifier = Modifier.fillMaxWidth().clickable(onClick = onClick),
    ) { Text(label) }
}
