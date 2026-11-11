package com.nu01.tabcam

import android.media.MediaRecorder
import kotlin.math.max
import kotlin.math.roundToLong

/**
 * The pure parts of [TakeSound] and [TakeMux]: which microphone source and
 * format to try, and the arithmetic that puts the take's sound in step
 * with its video. No Android object is touched here (only constants), so
 * these are checked on the JVM (`android/app/src/test`, TakeSoundMathTest).
 *
 * Times are `SystemClock.elapsedRealtimeNanos()` (BOOTTIME), which is
 * also the time base `AudioRecord.getTimestamp(…, TIMEBASE_BOOTTIME)`
 * gives.
 */
object TakeSoundMath {
    /** A sample rate and channel count to open the microphone with. */
    data class Format(val sampleRate: Int, val channels: Int)

    /**
     * The microphone sources to try, best first:
     * - `UNPROCESSED`, only where the phone says it really is
     *   (`AudioManager.PROPERTY_SUPPORT_AUDIO_SOURCE_UNPROCESSED` is
     *   "true"): no gain control, no noise suppression, no limiter;
     * - `VOICE_PERFORMANCE` (Android 10, API 29, on): meant for live
     *   music, with no voice processing;
     * - `MIC`: the plain microphone (some makers still process it).
     */
    fun sources(unprocessedSupported: Boolean, sdk: Int): List<Int> = buildList {
        if (unprocessedSupported) add(MediaRecorder.AudioSource.UNPROCESSED)
        if (sdk >= 29) add(MediaRecorder.AudioSource.VOICE_PERFORMANCE)
        add(MediaRecorder.AudioSource.MIC)
    }

    /** The formats to try for each source, best first. */
    val formats = listOf(
        Format(48000, 2),
        Format(48000, 1),
        Format(44100, 2),
        Format(44100, 1),
    )

    fun sourceName(source: Int): String = when (source) {
        MediaRecorder.AudioSource.UNPROCESSED -> "unprocessed"
        MediaRecorder.AudioSource.VOICE_PERFORMANCE -> "voice performance"
        MediaRecorder.AudioSource.MIC -> "mic"
        else -> "source $source"
    }

    /**
     * The microphone's buffer, in bytes: generous, so the reading thread
     * can be late by half a second without a gap (at least four times
     * the smallest the system takes).
     */
    fun bufferBytes(minBufferBytes: Int, format: Format): Int =
        max(minBufferBytes * 4, format.sampleRate * format.channels * 2 / 2)

    /** How much is read at a time: 20 ms. */
    fun chunkBytes(format: Format): Int = format.sampleRate / 50 * format.channels * 2

    /** The AAC bitrate: 128 kbps a channel (256 kbps in stereo). */
    fun bitrate(channels: Int): Int = 128_000 * channels

    /**
     * When the sound's first frame was captured: an `AudioTimestamp` says
     * frame [framePosition] (counted from the recording's start, as read)
     * was captured at [nanoTime].
     */
    fun firstFrameNs(nanoTime: Long, framePosition: Long, sampleRate: Int): Long =
        nanoTime - framePosition * 1_000_000_000L / sampleRate

    /**
     * Without a timestamp: the first read returned at [readNs] with
     * [frames] frames, so they began at least that long before (later
     * than the truth by the system's capture latency).
     */
    fun firstFrameFromReadNs(readNs: Long, frames: Long, sampleRate: Int): Long =
        readNs - frames * 1_000_000_000L / sampleRate

    /**
     * The video's start told from Stop instead: when Stop was pressed
     * ([stopNs]) less the video's length. Earlier than the truth by the
     * time Stop takes to reach the camera, and up to a frame.
     */
    fun videoStartFromStopNs(stopNs: Long, videoDurationUs: Long): Long =
        stopNs - videoDurationUs * 1000

    /**
     * How many of the sound's frames come before the video's first frame:
     * they're dropped, so the sound's first frame is the video's.
     * Negative when the sound started after the video: that many frames
     * of silence go first instead. Kept within [-MAX_LEAD_SILENCE_S,
     * MAX_LEAD_S] seconds: further apart, a time is wrong, not the take.
     */
    fun leadFrames(audioStartNs: Long, videoStartNs: Long, sampleRate: Int): Long {
        val lead = ((videoStartNs - audioStartNs).toDouble() * sampleRate / 1e9).roundToLong()
        return lead.coerceIn(-MAX_LEAD_SILENCE_S * sampleRate, MAX_LEAD_S * sampleRate)
    }

    /** At most this much silence is put before the sound… */
    const val MAX_LEAD_SILENCE_S = 2L

    /** …and at most this much of it is dropped. */
    const val MAX_LEAD_S = 10L

    /**
     * The presentation time of PCM frame [frames] of the sound, in µs: the
     * encoder's input times count frames from 0.
     */
    fun framesToUs(frames: Long, sampleRate: Int): Long = frames * 1_000_000L / sampleRate

    /**
     * How many frames the sound has fallen behind since it was put in
     * step: a later timestamp tells its first frame's time as
     * [impliedStartNs] ([firstFrameNs]), against [referenceNs], the one
     * it was put in step by. Positive: frames are missing (lost when the
     * reading fell behind the microphone's buffer, or a microphone clock
     * slower than its rate says); negative: there are too many (a faster
     * clock). The video's times are the system's (`BOOTTIME`), so that
     * is what the sound has to keep to.
     */
    fun driftFrames(impliedStartNs: Long, referenceNs: Long, sampleRate: Int): Long =
        ((impliedStartNs - referenceNs).toDouble() * sampleRate / 1e9).roundToLong()

    /**
     * Whether a timestamp's drift ([next], [driftFrames]) can be believed
     * after the last one ([previous]): the sound can lose frames, by a
     * lot at once, but can't gain more than a clock's worth, so going
     * back by a gap's length or more, or forward by more than
     * [MAX_GAP_S], means the timestamps are wrong (they're then not
     * followed for the rest of the take).
     */
    fun believable(previous: Long, next: Long, sampleRate: Int): Boolean =
        next > previous - gapFrames(sampleRate) && next - previous <= MAX_GAP_S * sampleRate

    /**
     * What to do at the next 20 ms of sound so it keeps in step, with
     * [missing] frames to put in (negative: to take out):
     * - a gap's length or more ([gapFrames]): that many frames of silence,
     *   at once (the sound lost them: a gap where it was lost);
     * - more than [slackFrames] either way: one frame repeated (1) or
     *   left out (-1), too little to hear, at most once a chunk (1 ms a
     *   second, ten times a clock's usual error);
     * - else nothing (0).
     */
    fun correction(missing: Long, sampleRate: Int): Long = when {
        missing >= gapFrames(sampleRate) -> missing
        missing > slackFrames(sampleRate) -> 1
        missing < -slackFrames(sampleRate) -> -1
        else -> 0
    }

    /** Frames lost at once that are put back as silence: 50 ms. */
    fun gapFrames(sampleRate: Int): Long = sampleRate * GAP_MS / 1000

    /** How far out of step the sound may be before it's nudged: 1 ms. */
    fun slackFrames(sampleRate: Int): Long = sampleRate / 1000L

    const val GAP_MS = 50L

    /** A timestamp saying more than this was lost at once is wrong. */
    const val MAX_GAP_S = 10L

    /**
     * Whole AAC frames (1024 samples) of the encoder's priming to drop
     * when the encoder says how long its delay is: the decoder plays them
     * first, so the sound would come that much late. Unknown (0): none.
     */
    fun primingFrames(encoderDelaySamples: Int): Int =
        if (encoderDelaySamples > 0) encoderDelaySamples / AAC_FRAME else 0

    const val AAC_FRAME = 1024

    /**
     * Whether an AAC frame at [ptsUs] (on the take's time line, the
     * sound's first frame with the video's) goes in the take: not before
     * the video, nor after its end ([videoEndUs]; 0 or less: unknown, so
     * kept).
     */
    fun keepAudio(ptsUs: Long, videoEndUs: Long): Boolean =
        ptsUs >= 0 && (videoEndUs <= 0 || ptsUs < videoEndUs)
}
