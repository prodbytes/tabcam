package com.nu01.tabcam

import android.graphics.Bitmap
import android.graphics.Color
import android.media.MediaMetadataRetriever
import java.io.ByteArrayOutputStream
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

    /** A [color] PNG, [width] x [height]. */
    private fun png(color: Int, width: Int, height: Int): ByteArray {
        val bitmap = Bitmap.createBitmap(width, height, Bitmap.Config.ARGB_8888)
        bitmap.eraseColor(color)
        val out = ByteArrayOutputStream()
        bitmap.compress(Bitmap.CompressFormat.PNG, 100, out)
        bitmap.recycle()
        return out.toByteArray()
    }

    /** [file]'s frame at [ms], and its colour at ([x], [y]) (fractions of it). */
    private fun pixel(file: File, ms: Long, x: Float, y: Float): Int {
        val retriever = MediaMetadataRetriever()
        try {
            retriever.setDataSource(file.path)
            val frame = retriever.getFrameAtTime(ms * 1000, MediaMetadataRetriever.OPTION_CLOSEST)!!
            return frame.getPixel((x * (frame.width - 1)).toInt(), (y * (frame.height - 1)).toInt())
        } finally {
            retriever.release()
        }
    }

    private fun isRed(color: Int) = Color.red(color) > 180 && Color.green(color) < 90 && Color.blue(color) < 90

    @Test
    fun drawsTheLayersOverThePictureWhileTheyShow() {
        val video = asset("riff.mp4")
        // A red band along the bottom for the first half second of the kept
        // part (which starts 0.5 s in), and a red square at the top left,
        // 20% of the short side, 5% in, all along.
        val output = File(dir, "layers.mp4")
        val (error, _) = render(
            RenderPlan(
                input = video, output = output, video = true, startMs = 500, endMs = 1500,
                ownVolume = 1f, song = null,
                images = listOf(png(Color.RED, 64, 16), png(Color.RED, 32, 32)),
                layers = listOf(
                    PlanLayer("tab", 0, LayerAnchor.BOTTOM_FULL, fromMs = 0, toMs = 500),
                    PlanLayer("title", 1, LayerAnchor.TOP_LEFT, heightU = 0.2f, marginU = 0.05f),
                ),
            ),
        )
        assertNull(error)
        // The band while it shows (from the kept part's start: the time base
        // is the first frame's), not after.
        assertTrue(isRed(pixel(output, 250, 0.5f, 0.99f)))
        assertTrue(!isRed(pixel(output, 800, 0.5f, 0.99f)) || isRed(pixel(asset("riff.mp4"), 1300, 0.5f, 0.99f)))
        // The square, by its anchor.
        val (w, h) = MediaMetadataRetriever().let { r ->
            try {
                r.setDataSource(output.path)
                val frame = r.getFrameAtTime(0)!!
                frame.width to frame.height
            } finally {
                r.release()
            }
        }
        val short = minOf(w, h)
        val inside = (0.05f + 0.1f) * short
        assertTrue(isRed(pixel(output, 600, inside / w, inside / h)))
        // The sound alone: no layers, nothing to draw them on.
        val sound = File(dir, "layers.m4a")
        assertNull(
            render(
                RenderPlan(
                    input = video, output = sound, video = false, startMs = 500, endMs = 1500,
                    ownVolume = 1f, song = null, images = listOf(png(Color.RED, 4, 4)),
                    layers = listOf(PlanLayer("tab", 0, LayerAnchor.BOTTOM_FULL)),
                ),
            ).first,
        )
    }

    private fun brightness(color: Int) = (Color.red(color) + Color.green(color) + Color.blue(color)) / 3

    @Test
    fun fadesThePictureFromAndToBlackWithItsSound() {
        val video = asset("riff.mp4")
        val song = asset("tone.m4a")
        // A white square over the middle all along, so there's something
        // bright to fade; 400 ms in and out of a 1.2 s kept part.
        val output = File(dir, "fades.mp4")
        val (error, _) = render(
            RenderPlan(
                input = video, output = output, video = true, startMs = 300, endMs = 1500,
                ownVolume = 1f, song = SongLane(song, 1f, listOf(SongClip(0, 0, 1200))),
                images = listOf(png(Color.WHITE, 32, 32)),
                layers = listOf(PlanLayer("title", 0, LayerAnchor.TOP_LEFT, heightU = 0.9f, marginU = 0.05f)),
                fades = Fades(fadeInMs = 400, fadeOutMs = 400, lengthMs = 1200),
            ),
        )
        assertNull(error)
        val (ms, hasVideo, hasAudio) = probe(output)
        assertEquals(1200.0, ms.toDouble(), 150.0)
        assertTrue(hasVideo && hasAudio)
        // Black at the start (the square too: the black is over the layers),
        // bright in the middle.
        assertTrue(brightness(pixel(output, 0, 0.3f, 0.3f)) < 40)
        assertTrue(brightness(pixel(output, 600, 0.3f, 0.3f)) > 200)
        // The sound alone fades too (its gain on the mix): still made.
        assertNull(
            render(
                RenderPlan(
                    input = video, output = File(dir, "fades.m4a"), video = false, startMs = 300,
                    endMs = 1500, ownVolume = 1f, song = null,
                    fades = Fades(fadeInMs = 400, fadeOutMs = 400, lengthMs = 1200),
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
