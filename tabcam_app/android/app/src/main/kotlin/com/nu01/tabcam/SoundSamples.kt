package com.nu01.tabcam

import android.media.AudioFormat
import android.media.MediaCodec
import android.media.MediaExtractor
import android.media.MediaFormat
import java.nio.ByteOrder

/**
 * Reads a part of a sound or video file's sound as samples, for the app to
 * compare one sound with another (lib/capture/song_sync.dart): decoded with
 * the device's own decoder (MediaExtractor and MediaCodec), mixed to one
 * channel and brought to the rate asked for.
 *
 * Channel `tabcam/video_edit`, method `samples`: `path`, `fromMs`,
 * `lengthMs`, `rate`. Replies with the samples (floats from -1 to 1), fewer
 * where the file ends; the error `failed` when it has no sound or it can't
 * be decoded.
 */
object SoundSamples {
    /** The decoder is given a tenth of a second before the part, to settle. */
    private const val LEAD_US = 100_000L

    fun read(path: String, fromMs: Long, lengthMs: Long, rate: Int): FloatArray {
        require(lengthMs > 0 && rate > 0 && fromMs >= 0) { "Nothing to read" }
        val extractor = MediaExtractor()
        var codec: MediaCodec? = null
        try {
            extractor.setDataSource(path)
            val track = (0 until extractor.trackCount).firstOrNull {
                extractor.getTrackFormat(it).getString(MediaFormat.KEY_MIME)?.startsWith("audio/") == true
            } ?: throw IllegalStateException("No sound in the file")
            val format = extractor.getTrackFormat(track)
            extractor.selectTrack(track)
            val fromUs = fromMs * 1000
            val endUs = fromUs + lengthMs * 1000
            extractor.seekTo(maxOf(0, fromUs - LEAD_US), MediaExtractor.SEEK_TO_PREVIOUS_SYNC)
            val decoder = MediaCodec.createDecoderByType(format.getString(MediaFormat.KEY_MIME)!!)
            codec = decoder
            decoder.configure(format, null, null, 0)
            decoder.start()
            val bins = SampleBins(fromUs, (lengthMs * rate / 1000).toInt(), rate)
            var channels = format.getInteger(MediaFormat.KEY_CHANNEL_COUNT)
            var sourceRate = format.getInteger(MediaFormat.KEY_SAMPLE_RATE)
            var float = false
            val info = MediaCodec.BufferInfo()
            var fed = false
            var done = false
            // Should the decoder stall, give up rather than wait for ever.
            var idle = 0
            while (!done && idle < 500) {
                if (!fed) {
                    val index = decoder.dequeueInputBuffer(10_000)
                    if (index >= 0) {
                        val size = extractor.readSampleData(decoder.getInputBuffer(index)!!, 0)
                        // Past the part: the decoder is told the sound ends.
                        if (size < 0 || extractor.sampleTime > endUs + LEAD_US) {
                            decoder.queueInputBuffer(index, 0, 0, 0, MediaCodec.BUFFER_FLAG_END_OF_STREAM)
                            fed = true
                        } else {
                            decoder.queueInputBuffer(index, 0, size, extractor.sampleTime, 0)
                            extractor.advance()
                        }
                    }
                }
                val index = decoder.dequeueOutputBuffer(info, 10_000)
                when {
                    index == MediaCodec.INFO_OUTPUT_FORMAT_CHANGED -> {
                        val now = decoder.outputFormat
                        channels = now.getInteger(MediaFormat.KEY_CHANNEL_COUNT)
                        sourceRate = now.getInteger(MediaFormat.KEY_SAMPLE_RATE)
                        float = now.containsKey(MediaFormat.KEY_PCM_ENCODING) &&
                            now.getInteger(MediaFormat.KEY_PCM_ENCODING) == AudioFormat.ENCODING_PCM_FLOAT
                    }
                    index >= 0 -> {
                        idle = 0
                        if (info.size > 0 && channels > 0 && sourceRate > 0) {
                            val buffer = decoder.getOutputBuffer(index)!!
                            buffer.position(info.offset).limit(info.offset + info.size)
                            buffer.order(ByteOrder.nativeOrder())
                            val frames = info.size / (channels * if (float) 4 else 2)
                            val floats = if (float) buffer.asFloatBuffer() else null
                            val shorts = if (float) null else buffer.asShortBuffer()
                            for (f in 0 until frames) {
                                var sum = 0f
                                for (c in 0 until channels) {
                                    sum += floats?.get(f * channels + c)
                                        ?: (shorts!!.get(f * channels + c) / 32768f)
                                }
                                bins.add(info.presentationTimeUs, f, sourceRate, sum / channels)
                            }
                        }
                        decoder.releaseOutputBuffer(index, false)
                        if (info.flags and MediaCodec.BUFFER_FLAG_END_OF_STREAM != 0 ||
                            info.presentationTimeUs >= endUs
                        ) {
                            done = true
                        }
                    }
                    else -> idle++
                }
            }
            return bins.samples()
        } finally {
            try {
                codec?.stop()
            } catch (_: Exception) {
            }
            codec?.release()
            extractor.release()
        }
    }
}

/**
 * Samples at one rate from frames at another: [count] samples, [rate] a
 * second, the first at [fromUs] in the file. Each frame decoded goes into
 * the sample its time falls in ([add]), and a sample is the mean of its
 * frames (a plain way down to a low rate: all it's used for is finding one
 * sound in another, both brought down the same way). A sample no frame fell
 * in takes the one before.
 */
class SampleBins(private val fromUs: Long, count: Int, private val rate: Int) {
    private val sums = FloatArray(maxOf(0, count))
    private val counts = IntArray(maxOf(0, count))
    private var last = -1

    /** Frame [frame] of a buffer that starts at [bufferUs], at [sourceRate] frames a second. */
    fun add(bufferUs: Long, frame: Int, sourceRate: Int, value: Float) {
        // To the microsecond: far finer than a sample at the rate asked for.
        val us = (bufferUs - fromUs) + frame * 1_000_000L / sourceRate
        if (us < 0) return
        val at = us * rate / 1_000_000L
        if (at >= sums.size) return
        val i = at.toInt()
        sums[i] += value
        counts[i]++
        if (i > last) last = i
    }

    /** The samples, up to the last a frame fell in. */
    fun samples(): FloatArray {
        val out = FloatArray(last + 1)
        var before = 0f
        for (i in out.indices) {
            if (counts[i] > 0) before = sums[i] / counts[i]
            out[i] = before
        }
        return out
    }
}
