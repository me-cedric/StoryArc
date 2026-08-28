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
import androidx.compose.material3.Surface
import androidx.compose.material3.Text
import androidx.compose.runtime.Composable
import androidx.compose.runtime.getValue
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.res.stringResource
import androidx.compose.ui.text.font.FontFamily
import androidx.compose.ui.text.input.ImeAction
import androidx.compose.ui.text.input.KeyboardType
import androidx.compose.ui.text.input.PasswordVisualTransformation
import androidx.compose.ui.unit.dp
import androidx.lifecycle.compose.collectAsStateWithLifecycle
import app.storyarc.core.catalogue.OpdsError
import app.storyarc.core.designsystem.theme.LocalStoryArcPalette
import app.storyarc.core.designsystem.tokens.StoryArcRadius
import app.storyarc.core.designsystem.tokens.StoryArcSpace
import app.storyarc.core.model.Source

/**
 * Adding an OPDS catalogue.
 *
 * One step at a time rather than one screen with everything on it. A reader adding a
 * catalogue that works never sees the credential fields or the certificate warning, and a
 * reader who does see the warning is looking at nothing else. iOS's `CatalogueSheet` is the
 * same flow in a sheet of its own.
 */
// `ModalBottomSheet` is still marked experimental in Material 3 and is the component the
// platform intends for this. Opted in here rather than hand-rolling a sheet, and confined
// to this file so the opt-in cannot spread by accident.
@OptIn(androidx.compose.material3.ExperimentalMaterial3Api::class)
@Composable
fun CatalogueSheet(
    connection: CatalogueConnection,
    onAdd: (Source) -> Unit,
    onDismiss: () -> Unit,
) {
    val palette = LocalStoryArcPalette.current
    val step by connection.step.collectAsStateWithLifecycle()
    val address by connection.address.collectAsStateWithLifecycle()

    ModalBottomSheet(
        onDismissRequest = onDismiss,
    ) {
        Column(
            modifier = Modifier
                .verticalScroll(rememberScrollState())
                .padding(horizontal = StoryArcSpace.gutter)
                .padding(bottom = StoryArcSpace.xl),
            verticalArrangement = Arrangement.spacedBy(StoryArcSpace.md),
        ) {
            Text(
                text = stringResource(R.string.catalogue_title),
                style = MaterialTheme.typography.headlineSmall,
                color = palette.textPrimary,
            )

            OutlinedTextField(
                value = address,
                onValueChange = { connection.address.value = it },
                label = { Text(stringResource(R.string.catalogue_address_label)) },
                placeholder = { Text(stringResource(R.string.catalogue_address_prompt)) },
                singleLine = true,
                // A URL is not a sentence. Capitalisation and autocorrection on an address
                // field turn `komga.local` into `Komga. Local` and the reader has to fight
                // it back.
                keyboardOptions = KeyboardOptions(
                    keyboardType = KeyboardType.Uri,
                    imeAction = ImeAction.Go,
                ),
                modifier = Modifier.fillMaxWidth(),
            )

            Text(
                text = stringResource(R.string.catalogue_address_hint),
                style = MaterialTheme.typography.bodySmall,
                color = palette.textSecondary,
            )

            Button(
                onClick = { connection.connect() },
                enabled = address.isNotBlank() && step !is CatalogueConnection.Step.Connecting,
                modifier = Modifier.fillMaxWidth(),
            ) {
                Text(stringResource(R.string.catalogue_connect))
            }

            when (val current = step) {
                is CatalogueConnection.Step.Entering -> Unit

                is CatalogueConnection.Step.Connecting -> Row(
                    text = stringResource(R.string.catalogue_connecting),
                )

                is CatalogueConnection.Step.AskingCredentials ->
                    CatalogueSignIn(connection, current.scheme)

                is CatalogueConnection.Step.Untrusted ->
                    CatalogueCertificateWarning(current.certificate) { connection.trustCertificate() }

                is CatalogueConnection.Step.Confirmed -> {
                    Text(
                        text = stringResource(R.string.catalogue_confirmed, current.title),
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
                        Text(stringResource(R.string.catalogue_add))
                    }
                }

                is CatalogueConnection.Step.Failed -> {
                    Surface(
                        color = palette.surfaceRaised,
                        shape = androidx.compose.foundation.shape.RoundedCornerShape(StoryArcRadius.md),
                        modifier = Modifier.fillMaxWidth(),
                    ) {
                        Column(
                            modifier = Modifier.padding(StoryArcSpace.md),
                            verticalArrangement = Arrangement.spacedBy(StoryArcSpace.sm),
                        ) {
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
    }
}

/** A line of text beside a spinner. */
@Composable
private fun Row(text: String) {
    val palette = LocalStoryArcPalette.current
    androidx.compose.foundation.layout.Row(
        verticalAlignment = Alignment.CenterVertically,
        horizontalArrangement = Arrangement.spacedBy(StoryArcSpace.sm),
    ) {
        CircularProgressIndicator(modifier = Modifier.padding(StoryArcSpace.xs), strokeWidth = 2.dp)
        Text(text, style = MaterialTheme.typography.bodyMedium, color = palette.textSecondary)
    }
}

/** The credential prompt, for whichever scheme the server asked for. */
@Composable
private fun CatalogueSignIn(
    connection: CatalogueConnection,
    scheme: OpdsError.AuthenticationScheme?,
) {
    val palette = LocalStoryArcPalette.current
    val user by connection.user.collectAsStateWithLifecycle()
    val password by connection.password.collectAsStateWithLifecycle()
    val token by connection.token.collectAsStateWithLifecycle()

    Column(verticalArrangement = Arrangement.spacedBy(StoryArcSpace.sm)) {
        Text(
            text = stringResource(R.string.catalogue_sign_in_title),
            style = MaterialTheme.typography.titleMedium,
            color = palette.textPrimary,
        )

        if (scheme == OpdsError.AuthenticationScheme.BEARER) {
            OutlinedTextField(
                value = token,
                onValueChange = { connection.token.value = it },
                label = { Text(stringResource(R.string.catalogue_sign_in_token)) },
                singleLine = true,
                visualTransformation = PasswordVisualTransformation(),
                modifier = Modifier.fillMaxWidth(),
            )
        } else {
            OutlinedTextField(
                value = user,
                onValueChange = { connection.user.value = it },
                label = { Text(stringResource(R.string.catalogue_sign_in_user)) },
                singleLine = true,
                modifier = Modifier.fillMaxWidth(),
            )
            OutlinedTextField(
                value = password,
                onValueChange = { connection.password.value = it },
                label = { Text(stringResource(R.string.catalogue_sign_in_password)) },
                singleLine = true,
                visualTransformation = PasswordVisualTransformation(),
                keyboardOptions = KeyboardOptions(keyboardType = KeyboardType.Password),
                modifier = Modifier.fillMaxWidth(),
            )
        }

        // Said where the secret is entered, not buried in Privacy. `sources` promises the
        // secure store; a reader typing a password is the moment that promise is worth
        // anything.
        Text(
            text = stringResource(R.string.catalogue_sign_in_stored),
            style = MaterialTheme.typography.bodySmall,
            color = palette.textSecondary,
        )

        Button(
            onClick = { connection.submitCredentials() },
            modifier = Modifier.fillMaxWidth(),
        ) {
            Text(stringResource(R.string.catalogue_sign_in_submit))
        }
    }
}

/**
 * The warning shown before a certificate can be pinned.
 *
 * `opds-catalog` requires the fingerprint and "an explicit warning" before the offer, in
 * that order. The order is the whole point: an offer above a warning is a button people
 * press.
 */
@Composable
private fun CatalogueCertificateWarning(
    certificate: app.storyarc.core.catalogue.UntrustedCertificate,
    onTrust: () -> Unit,
) {
    val palette = LocalStoryArcPalette.current
    Column(verticalArrangement = Arrangement.spacedBy(StoryArcSpace.sm)) {
        Text(
            text = stringResource(R.string.catalogue_untrusted_title),
            style = MaterialTheme.typography.titleMedium,
            color = palette.textPrimary,
        )
        Text(
            text = stringResource(R.string.catalogue_untrusted_explanation),
            style = MaterialTheme.typography.bodyMedium,
            color = palette.textSecondary,
        )
        Surface(
            color = palette.surfaceRaised,
            shape = androidx.compose.foundation.shape.RoundedCornerShape(StoryArcRadius.md),
            modifier = Modifier.fillMaxWidth(),
        ) {
            Column(modifier = Modifier.padding(StoryArcSpace.md)) {
                Text(
                    text = stringResource(R.string.catalogue_untrusted_fingerprint),
                    style = MaterialTheme.typography.labelSmall,
                    color = palette.textSecondary,
                )
                // Monospaced. Sixty-four hex digits are compared character by character, and
                // a proportional font makes that harder than it needs to be.
                Text(
                    text = certificate.fingerprint,
                    style = MaterialTheme.typography.bodySmall.copy(fontFamily = FontFamily.Monospace),
                    color = palette.textPrimary,
                )
                Text(
                    text = certificate.subject,
                    style = MaterialTheme.typography.bodySmall,
                    color = palette.textSecondary,
                )
            }
        }
        // Outlined, not filled. This is the risky choice on the screen and should not be the
        // one the eye lands on.
        OutlinedButton(onClick = onTrust, modifier = Modifier.fillMaxWidth()) {
            Text(stringResource(R.string.catalogue_untrusted_trust))
        }
    }
}
