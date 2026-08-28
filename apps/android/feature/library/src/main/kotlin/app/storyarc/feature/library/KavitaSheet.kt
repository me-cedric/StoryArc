package app.storyarc.feature.library

import androidx.compose.foundation.layout.Arrangement
import androidx.compose.foundation.layout.Column
import androidx.compose.foundation.layout.fillMaxWidth
import androidx.compose.foundation.layout.padding
import androidx.compose.foundation.rememberScrollState
import androidx.compose.foundation.text.KeyboardOptions
import androidx.compose.foundation.verticalScroll
import androidx.compose.material3.Button
import androidx.compose.material3.CircularProgressIndicator
import androidx.compose.material3.MaterialTheme
import androidx.compose.material3.ModalBottomSheet
import androidx.compose.material3.OutlinedButton
import androidx.compose.material3.OutlinedTextField
import androidx.compose.material3.Text
import androidx.compose.runtime.Composable
import androidx.compose.runtime.getValue
import androidx.compose.ui.Modifier
import androidx.compose.ui.res.stringResource
import androidx.compose.ui.text.input.KeyboardType
import androidx.compose.ui.text.input.PasswordVisualTransformation
import androidx.compose.ui.unit.dp
import androidx.lifecycle.compose.collectAsStateWithLifecycle
import app.storyarc.core.designsystem.theme.LocalStoryArcPalette
import app.storyarc.core.designsystem.tokens.StoryArcSpace
import app.storyarc.core.model.Source

/**
 * Adding a Kavita server.
 *
 * The same shape as [CatalogueSheet], because it is the same job: an address, whatever proof
 * of identity the server wants, and a confirmation before anything is saved.
 */
@OptIn(androidx.compose.material3.ExperimentalMaterial3Api::class)
@Composable
fun KavitaSheet(
    connection: KavitaConnection,
    onAdd: (Source) -> Unit,
    onDismiss: () -> Unit,
) {
    val palette = LocalStoryArcPalette.current
    val step by connection.step.collectAsStateWithLifecycle()
    val address by connection.address.collectAsStateWithLifecycle()
    val apiKey by connection.apiKey.collectAsStateWithLifecycle()
    val carriesKey = connection.carriesKey(address)

    ModalBottomSheet(onDismissRequest = onDismiss) {
        Column(
            modifier = Modifier
                .verticalScroll(rememberScrollState())
                .padding(horizontal = StoryArcSpace.gutter)
                .padding(bottom = StoryArcSpace.xl),
            verticalArrangement = Arrangement.spacedBy(StoryArcSpace.md),
        ) {
            Text(
                text = stringResource(R.string.kavita_title),
                style = MaterialTheme.typography.headlineSmall,
                color = palette.textPrimary,
            )

            OutlinedTextField(
                value = address,
                onValueChange = { connection.address.value = it },
                label = { Text(stringResource(R.string.kavita_address_label)) },
                placeholder = { Text(stringResource(R.string.kavita_address_prompt)) },
                singleLine = true,
                keyboardOptions = KeyboardOptions(keyboardType = KeyboardType.Uri),
                modifier = Modifier.fillMaxWidth(),
            )
            Text(
                text = stringResource(R.string.kavita_address_hint),
                style = MaterialTheme.typography.bodySmall,
                color = palette.textSecondary,
            )

            // Hidden when the address already carries a key: asking for something the reader
            // has already given is how a form makes someone feel they typed it wrong.
            if (carriesKey) {
                Text(
                    text = stringResource(R.string.kavita_key_from_address),
                    style = MaterialTheme.typography.bodySmall,
                    color = palette.accent,
                )
            } else {
                OutlinedTextField(
                    value = apiKey,
                    onValueChange = { connection.apiKey.value = it },
                    label = { Text(stringResource(R.string.kavita_key_label)) },
                    singleLine = true,
                    visualTransformation = PasswordVisualTransformation(),
                    modifier = Modifier.fillMaxWidth(),
                )
                Text(
                    text = stringResource(R.string.kavita_key_hint),
                    style = MaterialTheme.typography.bodySmall,
                    color = palette.textSecondary,
                )
            }

            Button(
                onClick = { connection.connect() },
                enabled = address.isNotBlank() &&
                    (carriesKey || apiKey.isNotBlank()) &&
                    step !is KavitaConnection.Step.Connecting,
                modifier = Modifier.fillMaxWidth(),
            ) {
                Text(stringResource(R.string.kavita_connect))
            }

            when (val current = step) {
                is KavitaConnection.Step.Entering -> Unit

                is KavitaConnection.Step.Connecting ->
                    CircularProgressIndicator(strokeWidth = 2.dp, modifier = Modifier.padding(2.dp))

                is KavitaConnection.Step.Confirmed -> {
                    Text(
                        text = stringResource(
                            R.string.kavita_confirmed,
                            current.identity.username,
                            current.identity.version.toString(),
                        ),
                        style = MaterialTheme.typography.titleMedium,
                        color = palette.textPrimary,
                    )
                    Button(
                        onClick = {
                            connection.source()?.let(onAdd)
                            onDismiss()
                        },
                        modifier = Modifier.fillMaxWidth(),
                    ) {
                        Text(stringResource(R.string.kavita_add))
                    }
                }

                is KavitaConnection.Step.Failed -> {
                    Text(
                        text = current.message,
                        style = MaterialTheme.typography.bodyMedium,
                        color = palette.textPrimary,
                    )
                    OutlinedButton(onClick = { connection.connect() }) {
                        Text(stringResource(R.string.catalogue_retry))
                    }
                }
            }
        }
    }
}
