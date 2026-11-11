package com.nu01.tabcam

import android.media.MediaMetadataRetriever
import androidx.media3.common.util.UnstableApi
import androidx.test.ext.junit.runners.AndroidJUnit4
import androidx.test.platform.app.InstrumentationRegistry
import java.io.File
import java.util.Collections
import java.util.concurrent.CountDownLatch
import java.util.concurrent.TimeUnit
import java.util.concurrent.atomic.AtomicReference
import org.junit.After
import org.junit.Assert.assertEquals
import org.junit.Assert.assertNotNull
import org.junit.Assert.assertNull
import org.junit.Assert.assertTrue
import org.junit.Before
import org.junit.Test
import org.junit.runner.RunWith

/**
 * A smoke test of the video editor's renderer ([VideoRenderer], the `render`
 * method of `tabcam/video_edit`), on the device: a 2 s made-up clip (a test
 * pattern with a tone, androidTest/assets/riff.mp4) and a made-up tone as the
 * song (tone.m4a), rendered as the app's plans are. Run with the phone on USB:
 * `./gradlew :app:connectedDebugAndroidTest` in android/.
 */
@UnstableApi
@RunWith(AndroidJUnit4::class)
class VideoRenderTest {
    private val instrumentation = InstrumentationRegistry.getInstrumentation()
    private val context = instrumentation.targetContext
    private lateinit var dir: File

    @Before
    fun setUp() {
        dir = File(context.cacheDir, "render-test").apply {
            deleteRecursively()
            mkdirs()
        }
    }

    @After
    fun tearDown() {
        dir.deleteRecursively()
    }

    private fun asset(name: String): File = File(dir, name).also { file ->
        instrumentation.context.assets.open(name).use { input ->
            file.outputStream().use { input.copyTo(it) }
        }
    }

    /** Renders [plan]: the error (null on success), and the progress reported. */
    private fun render(plan: RenderPlan): Pair<String?, List<Double>> {
        val done = CountDownLatch(1)
        val error = AtomicReference<String?>("not done")
        val progress = Collections.synchronizedList(mutableListOf<Double>())
        VideoRenderer(context).render(plan, { progress.add(it) }) {
            error.set(it)
            done.countDown()
        }
        assertTrue("render timed out", done.await(60, TimeUnit.SECONDS))
        return error.get() to progress.toList()
    }

    private fun probe(file: File): Triple<Long, Boolean, Boolean> {
        val retriever = MediaMetadataRetriever()
        try {
            retriever.setDataSource(file.path)
            val ms = retriever.extractMetadata(MediaMetadataRetriever.METADATA_KEY_DURATION)!!.toLong()
            val video = retriever.extractMetadata(MediaMetadataRetriever.METADATA_KEY_HAS_VIDEO) == "yes"
            val audio = retriever.extractMetadata(MediaMetadataRetriever.METADATA_KEY_HAS_AUDIO) == "yes"
            return Triple(ms, video, audio)
        } finally {
            retriever.release()
        }
    }

    @Test
    fun rendersAPlanWithItsSongAndProgress() {
        val video = asset("riff.mp4")
        val song = asset("tone.m4a")
        // Kept from 0.5 s to 1.5 s, its own sound and the song's first 0.8 s,
        // coming in 0.2 s after the kept part's start, at half its volume.
        val output = File(dir, "out.mp4")
        val (error, progress) = render(
            RenderPlan(
                input = video, output = output, video = true, startMs = 500, endMs = 1500,
                ownVolume = 1f, song = SongLane(song, 0.5f, listOf(SongClip(200, 0, 800))),
            ),
        )
        assertNull(error)
        val (ms, hasVideo, hasAudio) = probe(output)
        assertEquals(1000.0, ms.toDouble(), 150.0)
        assertTrue(hasVideo)
        assertTrue(hasAudio)
        assertEquals(1.0, progress.last(), 0.0)

        // The song alone, the video's sound removed: still a sound track.
        val songOnly = File(dir, "song.mp4")
        assertNull(
            render(
                RenderPlan(
                    input = video, output = songOnly, video = true, startMs = 0, endMs = 1000,
                    ownVolume = null, song = SongLane(song, 1f, listOf(SongClip(300, 0, 500))),
                ),
            ).first,
        )
        assertTrue(probe(songOnly).third)

        // The sound alone: an M4A, no picture.
        val sound = File(dir, "out.m4a")
        assertNull(
            render(
                RenderPlan(
                    input = video, output = sound, video = false, startMs = 500, endMs = 1500,
                    ownVolume = 1f, song = null,
                ),
            ).first,
        )
        val (soundMs, soundVideo, soundAudio) = probe(sound)
        assertEquals(1000.0, soundMs.toDouble(), 150.0)
        assertTrue(!soundVideo)
        assertTrue(soundAudio)

        // No sound and no picture: nothing to make.
        assertNotNull(
            render(
                RenderPlan(
                    input = video, output = File(dir, "none.m4a"), video = false, startMs = 0,
                    endMs = 1000, ownVolume = null, song = null,
                ),
            ).first,
        )
    }

    @Test
    fun readsTheChannelsArguments() {
        val plan = RenderPlan.fromArgs(
            mapOf(
                "input" to "/tmp/in.mp4", "output" to "/tmp/out.mp4", "video" to true,
                "startMs" to 500, "endMs" to 1500, "own" to mapOf("volume" to 0.5),
                "song" to mapOf(
                    "path" to "/tmp/song.m4a", "volume" to 2,
                    "clips" to listOf(mapOf("atMs" to 200, "fromMs" to 0, "toMs" to 800, "speed" to 1.0)),
                ),
            ),
        )
        assertEquals(500L, plan.startMs)
        assertEquals(0.5f, plan.ownVolume!!, 0f)
        assertEquals(1f, plan.song!!.volume, 0f)
        assertEquals(listOf(SongClip(200, 0, 800)), plan.song!!.clips)
        val silent = RenderPlan.fromArgs(
            mapOf("input" to "/tmp/in.mp4", "output" to "/tmp/out.mp4", "startMs" to 0, "endMs" to 1000),
        )
        assertNull(silent.ownVolume)
        assertNull(silent.song)
    }
}
