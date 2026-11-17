package com.nu01.tabcam

import org.junit.Assert.assertArrayEquals
import org.junit.Assert.assertEquals
import org.junit.Test

/** Samples at one rate from frames at another ([SampleBins]), on the JVM. */
class SampleBinsTest {
    @Test
    fun eachSampleTheMeanOfItsFrames() {
        // 48 kHz down to 8 kHz: six frames a sample.
        val bins = SampleBins(fromUs = 0, count = 4, rate = 8000)
        for (f in 0 until 24) bins.add(0, f, 48_000, if (f < 6) 1f else if (f < 12) f.toFloat() else 0f)
        assertArrayEquals(floatArrayOf(1f, 8.5f, 0f, 0f), bins.samples(), 1e-6f)
    }

    @Test
    fun placedByTheBuffersTime() {
        // The part starts 1 s into the file; a buffer at 0.999 s has 48
        // frames before it (left out), then the part's first.
        val bins = SampleBins(fromUs = 1_000_000, count = 8000, rate = 8000)
        for (f in 0 until 96) bins.add(999_000, f, 48_000, if (f < 48) 9f else 1f)
        val samples = bins.samples()
        assertEquals(8, samples.size)
        assertArrayEquals(FloatArray(8) { 1f }, samples, 1e-6f)
        // A later buffer lands where its time says: 0.5 s into the part.
        bins.add(1_500_000, 0, 48_000, 0.5f)
        assertEquals(4001, bins.samples().size)
        assertEquals(0.5f, bins.samples()[4000], 1e-6f)
    }

    @Test
    fun aRateThatDoesNotDivide() {
        // 44.1 kHz: five or six frames a sample, none lost or past the end.
        val bins = SampleBins(fromUs = 0, count = 80, rate = 8000)
        for (f in 0 until 44_100) bins.add(0, f, 44_100, 0.25f)
        val samples = bins.samples()
        assertEquals(80, samples.size)
        assertArrayEquals(FloatArray(80) { 0.25f }, samples, 1e-6f)
    }

    @Test
    fun aGapTakesTheSampleBefore() {
        // 4 kHz up to 8 kHz: every other sample has no frame of its own.
        val bins = SampleBins(fromUs = 0, count = 6, rate = 8000)
        for (f in 0 until 3) bins.add(0, f, 4000, (f + 1).toFloat())
        assertArrayEquals(floatArrayOf(1f, 1f, 2f, 2f, 3f), bins.samples(), 1e-6f)
    }
}
