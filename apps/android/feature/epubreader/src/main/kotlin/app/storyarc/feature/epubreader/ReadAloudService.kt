package app.storyarc.feature.epubreader

import android.app.Notification
import android.app.NotificationChannel
import android.app.NotificationManager
import android.app.PendingIntent
import android.app.Service
import android.content.Context
import android.content.Intent
import android.content.pm.ServiceInfo
import android.media.MediaMetadata
import android.media.session.MediaSession
import android.media.session.PlaybackState
import android.os.IBinder

/** What the lock screen and the notification can ask the reader to do. */
internal interface ReadAloudCommands {
    fun toggle()
    fun skip(forward: Boolean)
    fun stop()
}

/**
 * What keeps a book talking once its screen is gone, and puts its controls where a reader
 * reaches for them.
 *
 * `ebook-reader`: "playback continues, and platform media controls show the publication
 * title and offer play, pause, and sentence skip". On Android those are one requirement
 * with one answer — a foreground service of type `mediaPlayback` holding a `MediaSession`.
 * Without the service the process is frozen the moment the reader leaves the app and the
 * voice stops mid-sentence; without the session the lock screen has nothing to draw.
 *
 * The speaking itself stays in [ReadAloudController], which is the activity's: the walk
 * needs Readium's `Publication`, and a `Publication` is not something a service can be
 * handed through an `Intent`. So this holds the notification and the session, and forwards
 * every button to whoever is currently speaking.
 *
 * iOS needs no equivalent: `UIBackgroundModes: audio` and `MPRemoteCommandCenter` are the
 * whole of it there, which is one of the two places the platforms diverge — see ADR-0017.
 */
internal class ReadAloudService : Service() {

    private var session: MediaSession? = null

    override fun onBind(intent: Intent?): IBinder? = null

    override fun onCreate() {
        super.onCreate()
        getSystemService(NotificationManager::class.java).createNotificationChannel(
            NotificationChannel(
                CHANNEL,
                getString(R.string.readaloud_channel),
                // Low, not default: a book being read aloud is a state, not an event, and
                // a notification that made a sound every time the chapter changed would
                // interrupt the thing it is about.
                NotificationManager.IMPORTANCE_LOW,
            ),
        )
        session = MediaSession(this, SESSION).apply {
            setCallback(
                object : MediaSession.Callback() {
                    override fun onPlay() { commands?.toggle() }
                    override fun onPause() { commands?.toggle() }
                    override fun onSkipToNext() { commands?.skip(forward = true) }
                    override fun onSkipToPrevious() { commands?.skip(forward = false) }
                    override fun onStop() { commands?.stop() }
                },
            )
            isActive = true
        }
    }

    override fun onStartCommand(intent: Intent?, flags: Int, startId: Int): Int {
        isRunning = true
        when (intent?.action) {
            ACTION_TOGGLE -> commands?.toggle()
            ACTION_NEXT -> commands?.skip(forward = true)
            ACTION_PREVIOUS -> commands?.skip(forward = false)
            ACTION_STOP -> commands?.stop()
            ACTION_SHOW -> Unit
            else -> {
                // Started by the system with no intent — a restart this service has no way
                // to honour, because the book it was reading is gone with the process.
                stopSelf()
                return START_NOT_STICKY
            }
        }

        val label = SpokenLabel(
            title = intent.getStringExtra(EXTRA_TITLE).orEmpty(),
            detail = intent.getStringExtra(EXTRA_DETAIL),
        )
        val isSpeaking = intent.getBooleanExtra(EXTRA_SPEAKING, false)
        publish(label, isSpeaking)
        startForeground(
            NOTIFICATION,
            notification(label, isSpeaking),
            ServiceInfo.FOREGROUND_SERVICE_TYPE_MEDIA_PLAYBACK,
        )
        // Not sticky: a restarted service would hold a transport for a book nobody has
        // open, and the only honest thing it could do is stop itself.
        return START_NOT_STICKY
    }

    override fun onDestroy() {
        isRunning = false
        session?.isActive = false
        session?.release()
        session = null
        super.onDestroy()
    }

    /** What the lock screen reads, and which of its buttons are live. */
    private fun publish(label: SpokenLabel, isSpeaking: Boolean) {
        val session = session ?: return
        session.setMetadata(
            MediaMetadata.Builder()
                .putString(MediaMetadata.METADATA_KEY_TITLE, label.title)
                .putString(MediaMetadata.METADATA_KEY_ARTIST, label.detail.orEmpty())
                .build(),
        )
        session.setPlaybackState(
            PlaybackState.Builder()
                .setActions(
                    PlaybackState.ACTION_PLAY or
                        PlaybackState.ACTION_PAUSE or
                        PlaybackState.ACTION_PLAY_PAUSE or
                        PlaybackState.ACTION_SKIP_TO_NEXT or
                        PlaybackState.ACTION_SKIP_TO_PREVIOUS or
                        PlaybackState.ACTION_STOP,
                )
                .setState(
                    if (isSpeaking) PlaybackState.STATE_PLAYING else PlaybackState.STATE_PAUSED,
                    // A book has no seconds. Reporting an unknown position is what keeps
                    // the system from drawing a scrubber this reader could not honour.
                    PlaybackState.PLAYBACK_POSITION_UNKNOWN,
                    if (isSpeaking) 1f else 0f,
                )
                .build(),
        )
    }

    private fun notification(label: SpokenLabel, isSpeaking: Boolean): Notification {
        val builder = Notification.Builder(this, CHANNEL)
            .setSmallIcon(R.drawable.ic_read_aloud)
            .setContentTitle(label.title)
            .setContentText(label.detail.orEmpty())
            .setOngoing(isSpeaking)
            .setContentIntent(reopen())
            .setDeleteIntent(command(ACTION_STOP))
            .addAction(
                action(
                    android.R.drawable.ic_media_previous,
                    R.string.readaloud_previous,
                    ACTION_PREVIOUS,
                ),
            )
            .addAction(
                action(
                    if (isSpeaking) {
                        android.R.drawable.ic_media_pause
                    } else {
                        android.R.drawable.ic_media_play
                    },
                    if (isSpeaking) R.string.readaloud_pause else R.string.readaloud_play,
                    ACTION_TOGGLE,
                ),
            )
            .addAction(
                action(android.R.drawable.ic_media_next, R.string.readaloud_next, ACTION_NEXT),
            )

        session?.let {
            builder.style = Notification.MediaStyle()
                .setMediaSession(it.sessionToken)
                // All three in the collapsed row: play, and the two skips beside it. There
                // is nothing else worth the space, because a book has no track list.
                .setShowActionsInCompactView(0, 1, 2)
        }
        return builder.build()
    }

    private fun action(icon: Int, label: Int, action: String): Notification.Action =
        Notification.Action.Builder(
            android.graphics.drawable.Icon.createWithResource(this, icon),
            getString(label),
            command(action),
        ).build()

    private fun command(action: String): PendingIntent =
        PendingIntent.getService(
            this,
            action.hashCode(),
            Intent(this, ReadAloudService::class.java).setAction(action),
            PendingIntent.FLAG_UPDATE_CURRENT or PendingIntent.FLAG_IMMUTABLE,
        )

    /**
     * Back to the book.
     *
     * The launcher's own entry point rather than the reader activity: the reader needs a
     * publication and a location to be started with, and neither survives in a notification
     * that may outlive the screen that made it.
     */
    private fun reopen(): PendingIntent? =
        packageManager.getLaunchIntentForPackage(packageName)?.let {
            PendingIntent.getActivity(this, 0, it, PendingIntent.FLAG_IMMUTABLE)
        }

    internal companion object {
        private const val CHANNEL = "read-aloud"
        private const val SESSION = "StoryArc read aloud"
        private const val NOTIFICATION = 1

        private const val ACTION_SHOW = "app.storyarc.readaloud.SHOW"
        private const val ACTION_TOGGLE = "app.storyarc.readaloud.TOGGLE"
        private const val ACTION_NEXT = "app.storyarc.readaloud.NEXT"
        private const val ACTION_PREVIOUS = "app.storyarc.readaloud.PREVIOUS"
        private const val ACTION_STOP = "app.storyarc.readaloud.STOP"

        private const val EXTRA_TITLE = "title"
        private const val EXTRA_DETAIL = "detail"
        private const val EXTRA_SPEAKING = "speaking"

        /**
         * Whoever is speaking, or null.
         *
         * One at a time, because one reader is open at a time and the audio focus this
         * holds is a single device resource. Cleared by the controller when its screen goes
         * away, so a button pressed on a stale notification reaches nothing rather than a
         * dead reader.
         */
        var commands: ReadAloudCommands? = null

        /**
         * Whether this service is up.
         *
         * Not cosmetic. From Android 12 an app in the background may not *start* a
         * foreground service, but it may go on delivering commands to one that is already
         * running — and a chapter turning over while the reader's screen is off is exactly
         * a refresh that arrives from the background.
         */
        private var isRunning = false

        /** Starts or refreshes the transport. */
        fun show(context: Context, label: SpokenLabel, isSpeaking: Boolean) {
            val intent = Intent(context, ReadAloudService::class.java)
                .setAction(ACTION_SHOW)
                .putExtra(EXTRA_TITLE, label.title)
                .putExtra(EXTRA_DETAIL, label.detail)
                .putExtra(EXTRA_SPEAKING, isSpeaking)
            if (isRunning) {
                context.startService(intent)
            } else {
                context.startForegroundService(intent)
            }
        }

        /** Takes it down. */
        fun dismiss(context: Context) {
            if (!isRunning) return
            isRunning = false
            context.stopService(Intent(context, ReadAloudService::class.java))
        }
    }
}
