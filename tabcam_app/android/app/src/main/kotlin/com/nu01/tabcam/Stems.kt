package com.nu01.tabcam

import androidx.media3.common.C
import androidx.media3.common.audio.AudioProcessor
import androidx.media3.common.audio.BaseAudioProcessor
import androidx.media3.common.util.UnstableApi
import java.nio.ByteBuffer
import kotlin.math.PI
import kotlin.math.cos
import kotlin.math.min
import kotlin.math.sin

/**
 * A lane split into its instruments (the channel's `stems`): each one's
 * gain (0 to 1, 0 when muted) and the crossover's frequencies. The app's
 * `StemSplit` (lib/capture/stem_split.dart) says how it's split; this is a
 * copy of its `apply`.
 */
data class StemGains(
    val vocals: Float,
    val drums: Float,
    val bass: Float,
    val other: Float,
    val bassHz: Double,
    val drumsHz: Double,
) {
    companion object {
        /** The channel's `stems`; null when left out. */
        fun fromArgs(value: Any?): StemGains? {
            val map = value as? Map<*, *> ?: return null
            fun gain(key: String): Float =
                ((map[key] as? Number)?.toFloat() ?: 1f).let { if (it.isNaN()) 1f else it.coerceIn(0f, 1f) }
            fun hz(key: String, default: Double): Double =
                (map[key] as? Number)?.toDouble()?.takeIf { it.isFinite() && it > 0 } ?: default
            return StemGains(
                vocals = gain("vocals"),
                drums = gain("drums"),
                bass = gain("bass"),
                other = gain("other"),
                bassHz = hz("bassHz", 200.0),
                drumsHz = hz("drumsHz", 4000.0),
            )
        }
    }
}

/** A biquad (transposed direct form II, in doubles), as `StemSplit.coefficients` makes it. */
class Biquad(
    private val b0: Double,
    private val b1: Double,
    private val b2: Double,
    private val a1: Double,
    private val a2: Double,
) {
    private var z1 = 0.0
    private var z2 = 0.0

    fun next(x: Double): Double {
        val y = b0 * x + z1
        z1 = b1 * x - a1 * y + z2
        z2 = b2 * x - a2 * y
        return y
    }

    companion object {
        private const val Q = 0.7071067811865476

        fun lowPass(hz: Double, rate: Int) = make(0, hz, rate)
        fun highPass(hz: Double, rate: Int) = make(1, hz, rate)
        fun allPass(hz: Double, rate: Int) = make(2, hz, rate)

        private fun make(kind: Int, hz: Double, rate: Int): Biquad {
            val w = 2 * PI * min(hz, rate * 0.45) / rate
            val cosW = cos(w)
            val alpha = sin(w) / (2 * Q)
            val a0 = 1 + alpha
            val (b0, b1, b2) = when (kind) {
                0 -> Triple((1 - cosW) / 2, 1 - cosW, (1 - cosW) / 2)
                1 -> Triple((1 + cosW) / 2, -(1 + cosW), (1 + cosW) / 2)
                else -> Triple(1 - alpha, -2 * cosW, 1 + alpha)
            }
            return Biquad(b0 / a0, b1 / a0, b2 / a0, -2 * cosW / a0, (1 - alpha) / a0)
        }
    }
}

/**
 * One channel's three bands (`StemSplit.bands`): the bass (two low-passes
 * at the bass's frequency, an all-pass at the drums'), the rest above it
 * (two high-passes), and from that the middle band (two low-passes at the
 * drums') and the drums (two high-passes).
 */
class StemBands(gains: StemGains, rate: Int) {
    private val bassFilters = arrayOf(
        Biquad.lowPass(gains.bassHz, rate),
        Biquad.lowPass(gains.bassHz, rate),
        Biquad.allPass(gains.drumsHz, rate),
    )
    private val aboveFilters = arrayOf(Biquad.highPass(gains.bassHz, rate), Biquad.highPass(gains.bassHz, rate))
    private val middleFilters = arrayOf(Biquad.lowPass(gains.drumsHz, rate), Biquad.lowPass(gains.drumsHz, rate))
    private val drumsFilters = arrayOf(Biquad.highPass(gains.drumsHz, rate), Biquad.highPass(gains.drumsHz, rate))

    var bass = 0.0
        private set
    var middle = 0.0
        private set
    var drums = 0.0
        private set

    fun next(x: Double) {
        var b = x
        for (f in bassFilters) b = f.next(b)
        var above = x
        for (f in aboveFilters) above = f.next(above)
        var m = above
        for (f in middleFilters) m = f.next(m)
        var d = above
        for (f in drumsFilters) d = f.next(d)
        bass = b
        middle = m
        drums = d
    }
}

/**
 * A lane's instruments at their [gains], on 16-bit or float PCM: each
 * channel split into its bands ([StemBands]), the bass and the drums at
 * theirs, and of a stereo sound's middle band, its middle (what both
 * channels have alike) at the vocals' and its sides at the rest's; a sound
 * with one channel (or more than two) has no sides, each channel's middle
 * band at the vocals'. Each sample is held within its range.
 */
@UnstableApi
class StemsProcessor(private val gains: StemGains) : BaseAudioProcessor() {
    private var bands: Array<StemBands> = emptyArray()
    private var frame = DoubleArray(0)

    override fun onConfigure(inputAudioFormat: AudioProcessor.AudioFormat): AudioProcessor.AudioFormat {
        if (inputAudioFormat.encoding != C.ENCODING_PCM_16BIT && inputAudioFormat.encoding != C.ENCODING_PCM_FLOAT) {
            throw AudioProcessor.UnhandledAudioFormatException(inputAudioFormat)
        }
        return inputAudioFormat
    }

    override fun onFlush() = fresh()

    override fun onReset() {
        bands = emptyArray()
        frame = DoubleArray(0)
    }

    private fun fresh() {
        val channels = inputAudioFormat.channelCount
        bands = Array(channels) { StemBands(gains, inputAudioFormat.sampleRate) }
        frame = DoubleArray(channels)
    }

    override fun queueInput(inputBuffer: ByteBuffer) {
        if (!inputBuffer.hasRemaining()) return
        if (bands.size != inputAudioFormat.channelCount) fresh()
        val channels = bands.size
        val short = inputAudioFormat.encoding == C.ENCODING_PCM_16BIT
        val bytes = if (short) 2 else 4
        val output = replaceOutputBuffer(inputBuffer.remaining())
        val same = (gains.vocals + gains.other) / 2.0
        val cross = (gains.vocals - gains.other) / 2.0
        while (inputBuffer.remaining() >= channels * bytes) {
            for (c in 0 until channels) {
                val x = if (short) inputBuffer.getShort() / 32768.0 else inputBuffer.getFloat().toDouble()
                bands[c].next(x)
            }
            if (channels == 2) {
                val (l, r) = bands
                frame[0] = gains.bass * l.bass + gains.drums * l.drums + same * l.middle + cross * r.middle
                frame[1] = gains.bass * r.bass + gains.drums * r.drums + cross * l.middle + same * r.middle
            } else {
                for (c in 0 until channels) {
                    val b = bands[c]
                    frame[c] = gains.bass * b.bass + gains.drums * b.drums + gains.vocals * b.middle
                }
            }
            for (v in frame) {
                val y = v.coerceIn(-1.0, 1.0)
                if (short) {
                    output.putShort((y * 32768.0).coerceIn(-32768.0, 32767.0).toInt().toShort())
                } else {
                    output.putFloat(y.toFloat())
                }
            }
        }
        // A partial frame (never sent, in practice) goes on as it is.
        while (inputBuffer.hasRemaining()) output.put(inputBuffer.get())
        output.flip()
    }
}
