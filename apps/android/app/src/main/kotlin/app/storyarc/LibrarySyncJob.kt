package app.storyarc

import android.annotation.SuppressLint
import android.app.job.JobInfo
import android.app.job.JobParameters
import android.app.job.JobScheduler
import android.app.job.JobService
import android.content.ComponentName
import android.content.Context
import app.storyarc.core.persistence.LibrarySyncRunner
import java.util.concurrent.TimeUnit
import kotlinx.coroutines.CoroutineScope
import kotlinx.coroutines.Dispatchers
import kotlinx.coroutines.Job
import kotlinx.coroutines.SupervisorJob
import kotlinx.coroutines.cancel
import kotlinx.coroutines.launch

/**
 * The background sync, as far as Android allows it.
 *
 * `library-sync` task 4.3. A periodic job at the platform's floor of 15 minutes, with a network
 * required, scheduled only while sync is on. The platform's own `JobScheduler`, so no new
 * dependency. The job runs the same entry point as every other trigger: [LibrarySyncRunner.run].
 */
internal object LibrarySyncJob {
    const val JOB_ID = 0x5359_4e43

    /** Schedules the job while sync is on, and cancels it while sync is off. */
    fun update(context: Context, isOn: Boolean) {
        val scheduler = context.getSystemService(JobScheduler::class.java) ?: return
        if (!isOn) {
            scheduler.cancel(JOB_ID)
            return
        }
        // Scheduling again would restart the period, so a job already there is left alone.
        if (scheduler.getPendingJob(JOB_ID) != null) return
        scheduler.schedule(
            JobInfo.Builder(JOB_ID, ComponentName(context, LibrarySyncJobService::class.java))
                .setPeriodic(TimeUnit.MINUTES.toMillis(PERIOD_MINUTES))
                .setRequiredNetworkType(JobInfo.NETWORK_TYPE_ANY)
                .build(),
        )
    }

    /** One background sync. The job service calls this, and so does a test. */
    suspend fun runOnce(context: Context): Boolean =
        LibrarySyncHub.runner(context).run(LibrarySyncRunner.Trigger.BACKGROUND)

    const val PERIOD_MINUTES = 15L
}

/**
 * Runs [LibrarySyncJob.runOnce] when the system starts the job.
 *
 * ponytail: WorkManager is in the app only through Glance, which numbers its own jobs upwards from
 * zero. [LibrarySyncJob.JOB_ID] is above a billion, so the two meet only after that many Glance
 * jobs; declaring WorkManager to give it a range would add a dependency this job does not need.
 */
@SuppressLint("SpecifyJobSchedulerIdRange")
class LibrarySyncJobService : JobService() {
    private val scope = CoroutineScope(SupervisorJob() + Dispatchers.Main)
    private var running: Job? = null

    override fun onStartJob(params: JobParameters): Boolean {
        running = scope.launch {
            LibrarySyncJob.runOnce(applicationContext)
            jobFinished(params, false)
        }
        return true
    }

    override fun onStopJob(params: JobParameters): Boolean {
        running?.cancel()
        return true
    }

    override fun onDestroy() {
        scope.cancel()
        super.onDestroy()
    }
}
