package com.nu01.tabcam

import android.media.MediaCodec
import android.media.MediaExtractor
import android.media.MediaFormat
import android.media.MediaMetadataRetriever
import android.media.MediaMuxer
import java.io.File
import java.nio.ByteBuffer

/**
 * Puts the take's sound ([TakeSound]) into the camera's video: both copied
 * as they are (no re-encoding) into a new MP4, the video's samples and the
 * sound's interleaved by time. The sound's first frame is already the
 * video's (the encoder dropped what came before), so its frames go in at
 * their own times; those after the video's end are left out, as are the
 * encoder's priming frames when it says how many. The camera's own sound,
 * should it have recorded one, is left out too.
 */
object TakeMux {
    /** What [mux] found. */
    class Report(val cameraSound: Boolean, val videoSamples: Long, val audioSamples: Long)

    /** The video's length in µs; 0 when it can't be told. */
    fun durationUs(video: File): Long {
        val extractor = MediaExtractor()
        try {
            extractor.setDataSource(video.path)
            val track = track(extractor, "video/")
            if (track >= 0) {
                val format = extractor.getTrackFormat(track)
                if (format.containsKey(MediaFormat.KEY_DURATION)) {
                    return format.getLong(MediaFormat.KEY_DURATION)
                }
            }
        } catch (_: Exception) {
        } finally {
            extractor.release()
        }
        val retriever = MediaMetadataRetriever()
        return try {
            retriever.setDataSource(video.path)
            (retriever.extractMetadata(MediaMetadataRetriever.METADATA_KEY_DURATION)?.toLongOrNull() ?: 0L) * 1000
        } catch (_: Exception) {
            0L
        } finally {
            try {
                retriever.release()
            } catch (_: Exception) {
            }
        }
    }

    /**
     * [video]'s video track and [sound]'s AAC track into [out] (an MP4,
     * replaced), [primingFrames] of the sound's first frames dropped.
     * Throws when it can't; [out] is then deleted.
     */
    fun mux(video: File, sound: File, out: File, primingFrames: Int): Report {
        val videoIn = MediaExtractor()
        val soundIn = MediaExtractor()
        var muxer: MediaMuxer? = null
        var started = false
        try {
            out.delete()
            videoIn.setDataSource(video.path)
            soundIn.setDataSource(sound.path)
            val videoTrack = track(videoIn, "video/")
            check(videoTrack >= 0) { "the camera's recording has no video" }
            val cameraSound = track(videoIn, "audio/") >= 0
            val soundTrack = track(soundIn, "audio/")
            check(soundTrack >= 0) { "the sound's file has no sound" }
            videoIn.selectTrack(videoTrack)
            soundIn.selectTrack(soundTrack)
            val videoFormat = videoIn.getTrackFormat(videoTrack)
            val soundFormat = soundIn.getTrackFormat(soundTrack)
            val videoEndUs = if (videoFormat.containsKey(MediaFormat.KEY_DURATION)) {
                videoFormat.getLong(MediaFormat.KEY_DURATION)
            } else {
                0L
            }

            val m = MediaMuxer(out.path, MediaMuxer.OutputFormat.MUXER_OUTPUT_MPEG_4)
            muxer = m
            val rotation = rotation(videoFormat, video)
            if (rotation in listOf(90, 180, 270)) m.setOrientationHint(rotation)
            val videoOut = m.addTrack(videoFormat)
            val soundOut = m.addTrack(soundFormat)
            m.start()
            started = true

            // The video's first time is the take's start (0 from CameraX).
            val videoStartUs = videoIn.sampleTime.coerceAtLeast(0)
            repeat(primingFrames) { soundIn.advance() }
            val soundShiftUs = soundIn.sampleTime.coerceAtLeast(0)

            var buffer = ByteBuffer.allocateDirect(
                maxOf(maxInput(videoFormat), maxInput(soundFormat), MIN_BUFFER),
            )
            val info = MediaCodec.BufferInfo()
            var videoSamples = 0L
            var audioSamples = 0L
            var soundDone = false
            while (true) {
                val v = videoIn.sampleTime
                val a = if (soundDone) -1L else soundIn.sampleTime
                if (v < 0 && a < 0) break
                // The next sample by time: the video's, or the sound's on
                // the take's time line.
                val soundAt = if (a < 0) Long.MAX_VALUE else a - soundShiftUs
                val takeVideo = v >= 0 && v - videoStartUs <= soundAt
                val extractor = if (takeVideo) videoIn else soundIn
                if (!takeVideo && !TakeSoundMath.keepAudio(soundAt, videoEndUs)) {
                    if (soundAt >= 0) {
                        soundDone = true // past the video's end
                    } else {
                        soundIn.advance()
                    }
                    continue
                }
                var size: Int
                while (true) {
                    buffer.clear()
                    size = try {
                        extractor.readSampleData(buffer, 0)
                    } catch (e: IllegalArgumentException) {
                        // Too small for this sample.
                        check(buffer.capacity() < MAX_BUFFER) { "a sample is too big" }
                        buffer = ByteBuffer.allocateDirect(buffer.capacity() * 2)
                        continue
                    }
                    break
                }
                if (size < 0) {
                    if (takeVideo) videoIn.advance() else soundDone = true
                    continue
                }
                val flags = if (extractor.sampleFlags and MediaExtractor.SAMPLE_FLAG_SYNC != 0) {
                    MediaCodec.BUFFER_FLAG_KEY_FRAME
                } else {
                    0
                }
                if (takeVideo) {
                    info.set(0, size, v, flags)
                    m.writeSampleData(videoOut, buffer, info)
                    videoSamples++
                    videoIn.advance()
                } else {
                    info.set(0, size, videoStartUs + soundAt, flags)
                    m.writeSampleData(soundOut, buffer, info)
                    audioSamples++
                    soundIn.advance()
                }
            }
            check(videoSamples > 0) { "the camera's recording has no frames" }
            started = false
            m.stop()
            return Report(cameraSound, videoSamples, audioSamples)
        } catch (e: Exception) {
            if (started) {
                try {
                    muxer?.stop()
                } catch (_: Exception) {
                }
            }
            muxer?.release()
            muxer = null
            out.delete()
            throw e
        } finally {
            muxer?.release()
            videoIn.release()
            soundIn.release()
        }
    }

    private fun track(extractor: MediaExtractor, prefix: String): Int {
        for (i in 0 until extractor.trackCount) {
            val mime = extractor.getTrackFormat(i).getString(MediaFormat.KEY_MIME)
            if (mime?.startsWith(prefix) == true) return i
        }
        return -1
    }

    private fun maxInput(format: MediaFormat): Int =
        if (format.containsKey(MediaFormat.KEY_MAX_INPUT_SIZE)) {
            format.getInteger(MediaFormat.KEY_MAX_INPUT_SIZE)
        } else {
            0
        }

    /** How the video is turned for display (the camera writes it in the MP4). */
    private fun rotation(format: MediaFormat, video: File): Int {
        if (format.containsKey(MediaFormat.KEY_ROTATION)) return format.getInteger(MediaFormat.KEY_ROTATION)
        val retriever = MediaMetadataRetriever()
        return try {
            retriever.setDataSource(video.path)
            retriever.extractMetadata(MediaMetadataRetriever.METADATA_KEY_VIDEO_ROTATION)?.toIntOrNull() ?: 0
        } catch (_: Exception) {
            0
        } finally {
            try {
                retriever.release()
            } catch (_: Exception) {
            }
        }
    }

    private const val MIN_BUFFER = 4 shl 20
    private const val MAX_BUFFER = 64 shl 20
}
