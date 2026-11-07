package com.nu01.tabcam

import android.content.Context
import android.media.MediaMetadataRetriever
import android.net.Uri
import android.os.Handler
import android.os.Looper
import androidx.media3.common.MediaItem
import androidx.media3.common.MimeTypes
import androidx.media3.common.util.UnstableApi
import androidx.media3.transformer.Composition
import androidx.media3.transformer.EditedMediaItem
import androidx.media3.transformer.EditedMediaItemSequence
import androidx.media3.transformer.ExportException
import androidx.media3.transformer.ExportResult
import androidx.media3.transformer.Transformer
import io.flutter.plugin.common.BinaryMessenger
import io.flutter.plugin.common.MethodCall
import io.flutter.plugin.common.MethodChannel
import java.io.File

/**
 * Basic edits of a video, on the device, with Media3 Transformer: the part
 * kept, and its sound kept, removed or replaced by a track.
 *
 * Channel `tabcam/video_edit`, method `edit`, arguments:
 * - `input`: absolute path of the video;
 * - `output`: absolute path of the `.mp4` to write (its folder exists);
 * - `startMs`, `endMs`: the part kept;
 * - `sound`: `original` (kept), `none` (removed) or `track` (replaced);
 * - `track`: absolute path of the new sound track, for `track`;
 * - `trackMs`: where the track starts, from the kept part's start (negative:
 *   that much of the track's start is cut).
 *
 * Replies with the output path, or the error `failed`.
 *
 * The composition (Media3 1.9.2): the video, clipped, is the primary
 * sequence, its audio removed unless kept. A track is a second sequence:
 * silence (a gap) for as long as it starts after the video, then the part of
 * it that fits the kept part; the composition forces an audio track, since
 * the primary has none then. A secondary sequence longer than the primary is
 * cut to it; the output is H.264 and AAC in MP4.
 */
@UnstableApi
class VideoEdit(private val context: Context, messenger: BinaryMessenger) :
    MethodChannel.MethodCallHandler {

    private val channel = MethodChannel(messenger, CHANNEL).also {
        it.setMethodCallHandler(this)
    }
    private val mainHandler = Handler(Looper.getMainLooper())
    // Exports in progress, held so nothing collects them midway (main thread
    // only).
    private val running = mutableSetOf<Transformer>()

    override fun onMethodCall(call: MethodCall, result: MethodChannel.Result) {
        if (call.method != "edit") {
            result.notImplemented()
            return
        }
        val input = call.argument<String>("input")
        val output = call.argument<String>("output")
        val startMs = call.argument<Number>("startMs")?.toLong()
        val endMs = call.argument<Number>("endMs")?.toLong()
        val sound = call.argument<String>("sound") ?: "original"
        val track = call.argument<String>("track")
        val trackMs = call.argument<Number>("trackMs")?.toLong() ?: 0L
        if (input.isNullOrEmpty() || output.isNullOrEmpty() || startMs == null || endMs == null) {
            result.error("failed", "edit needs input, output, startMs and endMs", null)
            return
        }
        val inputFile = File(input)
        val outputFile = File(output)
        if (!inputFile.isFile) {
            result.error("failed", "No video at $input", null)
            return
        }
        if (inputFile.canonicalPath == outputFile.canonicalPath) {
            result.error("failed", "Output must differ from input", null)
            return
        }
        val trackFile = track?.let { File(it) }
        if (sound == "track" && trackFile?.isFile != true) {
            result.error("failed", "No track at $track", null)
            return
        }
        val composition = try {
            compose(inputFile, startMs, endMs, sound, trackFile, trackMs)
        } catch (e: Exception) {
            result.error("failed", e.message ?: e.toString(), null)
            return
        }
        // Transformer must be built and started on a Looper thread; the main
        // one is fine, the export itself runs on its own threads.
        mainHandler.post { start(composition, outputFile, result) }
    }

    private fun compose(
        input: File,
        startMs: Long,
        endMs: Long,
        sound: String,
        track: File?,
        trackMs: Long,
    ): Composition {
        val clipMs = endMs - startMs
        require(clipMs > 0) { "Nothing to keep" }
        val video = EditedMediaItem.Builder(clipped(input, startMs, endMs))
            .setRemoveAudio(sound != "original")
            .build()
        val sequences = mutableListOf(EditedMediaItemSequence.Builder(video).build())
        if (sound == "track") {
            requireNotNull(track) { "No track" }
            val span = trackSpan(clipMs, durationMs(track), trackMs)
            if (span != null) {
                val (gapMs, fromMs, toMs) = span
                val audio = EditedMediaItem.Builder(clipped(track, fromMs, toMs))
                    .setRemoveVideo(true)
                    .build()
                val sequence = EditedMediaItemSequence.Builder(emptyList<EditedMediaItem>())
                if (gapMs > 0) sequence.addGap(gapMs * 1000)
                sequence.addItem(audio)
                // A sequence that starts with a gap needs its audio forced.
                sequence.experimentalSetForceAudioTrack(true)
                sequences.add(sequence.build())
            }
        }
        return Composition.Builder(sequences)
            // The primary sequence has no audio of its own then: silence,
            // with the track mixed in.
            .experimentalSetForceAudioTrack(sound == "track")
            .build()
    }

    private fun clipped(file: File, startMs: Long, endMs: Long): MediaItem =
        MediaItem.Builder()
            .setUri(Uri.fromFile(file))
            .setClippingConfiguration(
                MediaItem.ClippingConfiguration.Builder()
                    .setStartPositionMs(startMs)
                    .setEndPositionMs(endMs)
                    .build(),
            )
            .build()

    private fun durationMs(file: File): Long {
        val retriever = MediaMetadataRetriever()
        try {
            retriever.setDataSource(file.path)
            return retriever.extractMetadata(MediaMetadataRetriever.METADATA_KEY_DURATION)
                ?.toLongOrNull() ?: throw IllegalArgumentException("${file.name} has no known length")
        } finally {
            retriever.release()
        }
    }

    private fun start(composition: Composition, output: File, result: MethodChannel.Result) {
        var transformer: Transformer? = null
        var replied = false
        fun finish(error: String?) {
            if (replied) return
            replied = true
            transformer?.let { running.remove(it) }
            if (error == null) {
                result.success(output.path)
            } else {
                output.delete()
                result.error("failed", error, null)
            }
        }
        try {
            // A leftover from an earlier attempt would otherwise be appended
            // to or fail the muxer.
            output.delete()
            val built = Transformer.Builder(context)
                .setVideoMimeType(MimeTypes.VIDEO_H264)
                .setAudioMimeType(MimeTypes.AUDIO_AAC)
                .addListener(object : Transformer.Listener {
                    override fun onCompleted(composition: Composition, exportResult: ExportResult) {
                        finish(null)
                    }

                    override fun onError(
                        composition: Composition,
                        exportResult: ExportResult,
                        exportException: ExportException,
                    ) {
                        finish(exportException.message ?: exportException.errorCodeName)
                    }
                })
                .build()
            transformer = built
            running.add(built)
            built.start(composition, output.path)
        } catch (e: Exception) {
            finish(e.message ?: e.toString())
        }
    }

    fun dispose() {
        channel.setMethodCallHandler(null)
    }

    companion object {
        const val CHANNEL = "tabcam/video_edit"

        /**
         * The part of a track [trackMs] long that goes into a clip [clipMs]
         * long, with the track starting [offsetMs] after the clip's start:
         * the silence before it, then the track's part, from and to; null
         * when none of it falls within the clip. The same as the app's
         * `trackSpan` (video_edit.dart).
         */
        fun trackSpan(clipMs: Long, trackMs: Long, offsetMs: Long): Triple<Long, Long, Long>? {
            if (clipMs <= 0 || trackMs <= 0) return null
            val gap = if (offsetMs > 0) offsetMs else 0L
            val from = if (offsetMs < 0) -offsetMs else 0L
            if (gap >= clipMs || from >= trackMs) return null
            val to = minOf(from + (clipMs - gap), trackMs)
            if (to <= from) return null
            return Triple(gap, from, to)
        }
    }
}
