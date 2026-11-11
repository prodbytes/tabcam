package com.nu01.tabcam

import android.media.MediaRecorder
import org.junit.Assert.assertEquals
import org.junit.Assert.assertFalse
import org.junit.Assert.assertTrue
import org.junit.Test

/** The take sound's arithmetic ([TakeSoundMath]), on the JVM. */
class TakeSoundMathTest {
    private val rate = 48_000

    @Test
    fun sourcesBestFirst() {
        assertEquals(
            listOf(
                MediaRecorder.AudioSource.UNPROCESSED,
                MediaRecorder.AudioSource.VOICE_PERFORMANCE,
                MediaRecorder.AudioSource.MIC,
            ),
            TakeSoundMath.sources(unprocessedSupported = true, sdk = 34),
        )
        assertEquals(
            listOf(MediaRecorder.AudioSource.VOICE_PERFORMANCE, MediaRecorder.AudioSource.MIC),
            TakeSoundMath.sources(unprocessedSupported = false, sdk = 29),
        )
        assertEquals(
            listOf(MediaRecorder.AudioSource.MIC),
            TakeSoundMath.sources(unprocessedSupported = false, sdk = 28),
        )
    }

    @Test
    fun leadInStep() {
        // The video started 100 ms after the sound: 4800 frames dropped.
        assertEquals(4800L, TakeSoundMath.leadFrames(1_000_000_000L, 1_100_000_000L, rate))
        // 10 ms before it: 480 frames of silence first.
        assertEquals(-480L, TakeSoundMath.leadFrames(1_000_000_000L, 990_000_000L, rate))
        // Kept within 2 s of silence and 10 s dropped.
        assertEquals(-2L * rate, TakeSoundMath.leadFrames(10_000_000_000L, 0L, rate))
        assertEquals(10L * rate, TakeSoundMath.leadFrames(0L, 60_000_000_000L, rate))
    }

    @Test
    fun timestampsTellTheFirstFrame() {
        // Frame 48000 captured at 5 s: the first at 4 s.
        assertEquals(4_000_000_000L, TakeSoundMath.firstFrameNs(5_000_000_000L, 48_000L, rate))
        assertEquals(
            4_980_000_000L,
            TakeSoundMath.firstFrameFromReadNs(5_000_000_000L, 960L, rate),
        )
        assertEquals(1_000_000L, TakeSoundMath.framesToUs(48_000L, rate))
    }

    @Test
    fun driftFromAClockOffItsRate() {
        // A microphone at 47,995 Hz for its nominal 48 kHz: after 10
        // minutes it has given 3,000 frames fewer, so a timestamp then
        // tells its first frame 62.5 ms later than it was.
        val reference = 1_000_000_000L
        val after = 600_000_000_000L
        val position = 47_995L * 600
        val implied = TakeSoundMath.firstFrameNs(reference + after, position, rate)
        assertEquals(3_000L, TakeSoundMath.driftFrames(implied, reference, rate))
        // A faster one: negative.
        val fast = TakeSoundMath.firstFrameNs(reference + after, 48_005L * 600, rate)
        assertEquals(-3_000L, TakeSoundMath.driftFrames(fast, reference, rate))
    }

    @Test
    fun believableDrift() {
        // A clock's worth either way, or frames lost at once.
        assertTrue(TakeSoundMath.believable(0, 5, rate))
        assertTrue(TakeSoundMath.believable(100, 95, rate))
        assertTrue(TakeSoundMath.believable(0, 24_000, rate))
        assertTrue(TakeSoundMath.believable(0, 10L * rate, rate))
        // Frames can't come back, nor more than 10 s go at once.
        assertFalse(TakeSoundMath.believable(0, -2_400, rate))
        assertFalse(TakeSoundMath.believable(24_000, 0, rate))
        assertFalse(TakeSoundMath.believable(0, 10L * rate + 1, rate))
    }

    @Test
    fun correctionNudgesOrFillsAGap() {
        assertEquals(2_400L, TakeSoundMath.gapFrames(rate))
        assertEquals(48L, TakeSoundMath.slackFrames(rate))
        // Within 1 ms: nothing.
        assertEquals(0L, TakeSoundMath.correction(0, rate))
        assertEquals(0L, TakeSoundMath.correction(48, rate))
        assertEquals(0L, TakeSoundMath.correction(-48, rate))
        // A clock off: a frame at a time.
        assertEquals(1L, TakeSoundMath.correction(49, rate))
        assertEquals(1L, TakeSoundMath.correction(2_399, rate))
        assertEquals(-1L, TakeSoundMath.correction(-49, rate))
        assertEquals(-1L, TakeSoundMath.correction(-100_000, rate))
        // Frames lost: all of them back at once, as silence.
        assertEquals(2_400L, TakeSoundMath.correction(2_400, rate))
        assertEquals(30_000L, TakeSoundMath.correction(30_000, rate))
    }

    @Test
    fun aClockOffItsRateIsKeptInStep() {
        // 10 minutes of 20 ms chunks from a 100 ppm slow microphone, a
        // timestamp each second: corrected a frame at a time, the sound
        // never more than about 1 ms out of step, and never with silence.
        val chunk = 960L
        var made = 0L
        var silence = 0L
        var worst = 0L
        for (i in 0 until 30_000) {
            val measured = (i / 50) * 50 * chunk / 10_000 // 100 ppm, told each second
            val fix = TakeSoundMath.correction(measured - made, rate)
            if (fix > 1) silence += fix
            made += fix
            worst = maxOf(worst, kotlin.math.abs(measured - made))
        }
        assertEquals(0L, silence)
        assertTrue("worst $worst", worst <= TakeSoundMath.slackFrames(rate) + 5)
    }

    @Test
    fun priming() {
        assertEquals(2, TakeSoundMath.primingFrames(2048))
        assertEquals(1, TakeSoundMath.primingFrames(1600))
        assertEquals(0, TakeSoundMath.primingFrames(0))
        assertTrue(TakeSoundMath.keepAudio(0, 1_000))
        assertFalse(TakeSoundMath.keepAudio(-1, 1_000))
        assertFalse(TakeSoundMath.keepAudio(1_000, 1_000))
        assertTrue(TakeSoundMath.keepAudio(5_000, 0))
    }
}
