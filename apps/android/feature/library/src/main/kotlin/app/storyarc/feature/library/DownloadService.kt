package app.storyarc.feature.library

import android.app.Notification
import android.app.NotificationChannel
import android.app.NotificationManager
import android.app.Service
import android.content.Context
import android.content.Intent
import android.content.pm.ServiceInfo
import android.os.Build
import android.os.IBinder
import androidx.core.app.NotificationCompat

/**
 * Keeps the process alive while a download is running.
 *
 * `offline-downloads`: a backgrounded transfer "continues under the platform's background
 * transfer mechanism as far as the platform allows". On Android the transfer itself needs
 * nothing special -- a coroutine keeps running when the app leaves the screen. What it needs
 * is a reason for the system not to kill the process, and a foreground service is that
 * reason. The notification is the price the platform charges, and it is also the honest
 * thing to show: a reader can see the download and can stop it.
 *
 * Started when the queue takes work and stopped when it runs out, so the notification exists
 * exactly as long as the work does.
 */
class DownloadService : Service() {
    override fun onBind(intent: Intent?): IBinder? = null

    override fun onStartCommand(intent: Intent?, flags: Int, startId: Int): Int {
        val running = intent?.getIntExtra(EXTRA_RUNNING, 0) ?: 0
        if (running <= 0) {
            stopSelf()
            return START_NOT_STICKY
        }
        startForeground(NOTIFICATION, notification(running), type())
        // Not sticky: a restarted service with no queue behind it would show a notification
        // for work nobody is doing. The queue starts it again when it has something.
        return START_NOT_STICKY
    }

    private fun type(): Int = if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.UPSIDE_DOWN_CAKE) {
        ServiceInfo.FOREGROUND_SERVICE_TYPE_DATA_SYNC
    } else {
        0
    }

    private fun notification(running: Int): Notification {
        val manager = getSystemService(NotificationManager::class.java)
        manager?.createNotificationChannel(
            NotificationChannel(
                CHANNEL,
                getString(R.string.downloads_channel),
                // Low: a download is not an interruption. It belongs in the shade, silent.
                NotificationManager.IMPORTANCE_LOW,
            ),
        )
        return NotificationCompat.Builder(this, CHANNEL)
            .setSmallIcon(android.R.drawable.stat_sys_download)
            .setContentTitle(resources.getQuantityString(R.plurals.downloads_running, running, running))
            .setOngoing(true)
            .setProgress(0, 0, true)
            .build()
    }

    companion object {
        private const val CHANNEL = "downloads"
        private const val NOTIFICATION = 1
        private const val EXTRA_RUNNING = "running"

        /**
         * Matches the service to the work: started with a count, stopped when it reaches zero.
         *
         * Failures are swallowed on purpose. Android refuses a foreground service started
         * from the background, and a download that keeps running unprotected is better than
         * one that crashes the app. A reader who denied notifications still gets the
         * service; only its notification is hidden.
         */
        fun follow(context: Context, running: Int) {
            val intent = Intent(context, DownloadService::class.java)
                .putExtra(EXTRA_RUNNING, running)
            runCatching {
                if (running > 0) {
                    context.startForegroundService(intent)
                } else {
                    context.stopService(intent)
                }
            }
        }
    }
}
