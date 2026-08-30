package app.storyarc

import androidx.compose.runtime.Composable
import androidx.compose.runtime.remember
import app.storyarc.core.model.Source
import app.storyarc.core.model.SourceKind
import app.storyarc.feature.library.CatalogueConnection
import app.storyarc.feature.library.CatalogueSheet
import app.storyarc.feature.library.KavitaConnection
import app.storyarc.feature.library.KavitaSheet
import app.storyarc.feature.library.SmbConnection
import app.storyarc.feature.library.SmbSheet
import app.storyarc.navigation.AppSheet

/**
 * The one modal the app layer hosts, whichever it currently is.
 *
 * Somewhere to read from is added over the top of whatever the reader was looking at, which
 * is why these are sheets and not screens: nothing is left behind, and dismissing one puts
 * the reader back exactly where they were. They are outside [app.storyarc.navigation.AppNavigation]
 * for the same reason — a sheet is not a place, and it brings Material's own back handling
 * with it.
 */
@Composable
internal fun AppSheets(host: AppHost, sheet: AppSheet?) {
    val context = host.activity.applicationContext
    val dependencies = host.dependencies
    val dismiss = { host.sheet(null) }
    when (sheet) {
        null -> Unit

        AppSheet.AddOnlineLibrary -> {
            val connection = remember {
                CatalogueConnection(
                    context,
                    dependencies.pins,
                    dependencies.pinStore,
                    dependencies.credentials,
                )
            }
            CatalogueSheet(
                connection = connection,
                onAdd = { host.library.addSource(it) },
                onDismiss = {
                    dismiss()
                    connection.reset()
                },
            )
        }

        AppSheet.AddKavita -> {
            val connection = remember { KavitaConnection(context, dependencies.credentials) }
            KavitaSheet(
                connection = connection,
                onAdd = { host.library.addSource(it) },
                onDismiss = {
                    dismiss()
                    connection.reset()
                },
            )
        }

        AppSheet.AddSharedFolder -> {
            val connection = remember { SmbConnection(context, dependencies.credentials) }
            SmbSheet(
                connection = connection,
                onAdd = { host.library.addSource(it) },
                onDismiss = {
                    dismiss()
                    connection.reset()
                },
            )
        }

        is AppSheet.Reconnect -> ReconnectSheet(host, sheet.source)
    }
}

/**
 * Signing in again to a source whose sign-in was refused.
 *
 * The sheet the source was added through, re-opened — not a smaller password prompt: a
 * refused credential is often a symptom of the address having moved, and a form that only
 * offers the secret cannot fix that. What comes back carries the same identifier, so it
 * replaces the row rather than joining it.
 */
@Composable
private fun ReconnectSheet(host: AppHost, source: Source) {
    val context = host.activity.applicationContext
    val dependencies = host.dependencies
    val done: (Source) -> Unit = {
        host.library.reconnectSource(it)
        host.sheet(null)
    }
    val dismiss = { host.sheet(null) }
    when (source.kind) {
        SourceKind.KAVITA_SERVER -> {
            val connection = remember(source.id) {
                KavitaConnection(context, dependencies.credentials).apply { prefill(source) }
            }
            KavitaSheet(connection, onAdd = done, onDismiss = dismiss)
        }

        SourceKind.OPDS_CATALOG -> {
            val connection = remember(source.id) {
                CatalogueConnection(
                    context,
                    dependencies.pins,
                    dependencies.pinStore,
                    dependencies.credentials,
                ).apply { prefill(source) }
            }
            CatalogueSheet(connection, onAdd = done, onDismiss = dismiss)
        }

        SourceKind.NETWORK_SHARE -> {
            val connection = remember(source.id) {
                SmbConnection(context, dependencies.credentials).apply { prefill(source) }
            }
            SmbSheet(connection, onAdd = done, onDismiss = dismiss)
        }

        // Never reached: a folder has no credential to refuse, so `SourceDiagnosis` never
        // offers the action for one. Answered rather than defaulted, so a fifth kind has to
        // be thought about here too.
        SourceKind.LOCAL_FOLDER -> Unit
    }
}
