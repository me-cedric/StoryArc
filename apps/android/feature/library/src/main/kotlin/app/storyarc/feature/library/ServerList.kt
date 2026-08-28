package app.storyarc.feature.library

/**
 * One reading list a Kavita server holds.
 *
 * Carries the server it belongs to, because a list can only hold that server's own
 * publications and the check has to be made before the change is sent.
 */
data class ServerList(val server: KavitaPage, val id: Int, val title: String)
