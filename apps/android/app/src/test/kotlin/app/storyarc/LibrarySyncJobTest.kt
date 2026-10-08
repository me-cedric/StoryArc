package app.storyarc

import android.app.job.JobScheduler
import android.content.Context
import androidx.test.core.app.ApplicationProvider
import app.storyarc.core.model.LibrarySyncOutcome
import app.storyarc.core.model.SyncFile
import app.storyarc.core.model.SyncPlace
import app.storyarc.core.persistence.LibrarySyncRunner
import app.storyarc.core.persistence.SyncPlaceChoice
import app.storyarc.core.persistence.SyncPlaceStore
import java.util.concurrent.TimeUnit
import kotlinx.coroutines.test.runTest
import org.junit.After
import org.junit.Assert.assertEquals
import org.junit.Assert.assertNotNull
import org.junit.Assert.assertNull
import org.junit.Assert.assertTrue
import org.junit.Test
import org.junit.runner.RunWith
import org.robolectric.RobolectricTestRunner
import org.robolectric.annotation.Config

/**
 * `library-sync` task 4.3: the periodic job exists only while sync is on, at the 15-minute floor
 * with a network required, and it runs the same sync entry point as every other trigger.
 */
@RunWith(RobolectricTestRunner::class)
@Config(sdk = [34])
class LibrarySyncJobTest {

    private val context: Context get() = ApplicationProvider.getApplicationContext()
    private val scheduler: JobScheduler get() = context.getSystemService(JobScheduler::class.java)

    private object NoPlace : SyncPlace {
        override suspend fun names() = emptyList<String>()
        override suspend fun read(name: String): SyncFile? = null
        override suspend fun write(name: String, text: String, replacing: String?) = true
        override suspend fun delete(name: String) = true
    }

    @After
    fun forgetRunner() = LibrarySyncHub.install(null)

    @Test
    fun `sync off schedules no job`() {
        LibrarySyncJob.update(context, isOn = false)
        assertNull(scheduler.getPendingJob(LibrarySyncJob.JOB_ID))
    }

    @Test
    fun `sync on schedules a periodic job at the 15-minute floor that needs a network, and off cancels it`() {
        LibrarySyncJob.update(context, isOn = true)
        val job = scheduler.getPendingJob(LibrarySyncJob.JOB_ID)!!
        assertTrue(job.isPeriodic)
        assertEquals(TimeUnit.MINUTES.toMillis(15), job.intervalMillis)
        assertNotNull("the job needs a network", job.requiredNetwork)
        assertEquals(LibrarySyncJobService::class.java.name, job.service.className)

        LibrarySyncJob.update(context, isOn = false)
        assertNull(scheduler.getPendingJob(LibrarySyncJob.JOB_ID))
    }

    @Test
    fun `the job runs the same sync the other triggers run`() = runTest {
        val places = SyncPlaceStore.open(context)
        places.choose(SyncPlaceChoice.Folder("content://tree/Sync"))
        var syncs = 0
        LibrarySyncHub.install(
            LibrarySyncRunner(
                places = places,
                placeFor = { NoPlace },
                sync = {
                    syncs++
                    LibrarySyncOutcome.Busy
                },
            ),
        )

        assertTrue(LibrarySyncJob.runOnce(context))
        assertEquals(1, syncs)
    }
}
