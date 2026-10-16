package com.nu01.tabcam

import android.content.Context
import android.graphics.Bitmap
import android.graphics.BitmapFactory
import android.os.Handler
import android.os.Looper
import androidx.media3.common.Effect
import androidx.media3.common.MediaItem
import androidx.media3.common.MimeTypes
import androidx.media3.common.OverlaySettings
import androidx.media3.common.util.Size
import androidx.media3.common.util.UnstableApi
import androidx.media3.effect.BitmapOverlay
import androidx.media3.effect.OverlayEffect
import androidx.media3.effect.StaticOverlaySettings
import androidx.media3.effect.TextureOverlay
import androidx.media3.transformer.Composition
import androidx.media3.transformer.EditedMediaItem
import androidx.media3.transformer.Effects
import androidx.media3.transformer.ExportException
import androidx.media3.transformer.ExportResult
import androidx.media3.transformer.Transformer
import com.google.common.collect.ImmutableList
import io.flutter.plugin.common.BinaryMessenger
import io.flutter.plugin.common.MethodCall
import io.flutter.plugin.common.MethodChannel
import java.io.File
import java.util.concurrent.Executors

/**
 * Burns the tab overlay into a recorded take, on the device, with Media3
 * Transformer.
 *
 * Channel `tabcam/take_overlay`, method `burn`, arguments:
 * - `input`: absolute path of the recorded video;
 * - `output`: absolute path of the `.mp4` to write (its folder exists);
 * - `bands`: `[{startMs, endMs (null = to the end), png}]`, ordered by start,
 *   not overlapping. Each PNG is one neckline band; all are the same size.
 *
 * Replies with the output path, or the error `failed`.
 *
 * Rotation and layout (checked against the Media3 1.9.2 sources):
 * - Transformer's `DefaultDecoderFactory` configures the decoder with the
 *   input's `KEY_ROTATION` and decodes to a surface, so the frames the effects
 *   see are already rotated for display (`VideoSampleExporter`: "The decoder
 *   rotates encoded frames for display by format.rotationDegrees", and it
 *   swaps width and height of the format it hands the video graph). So no
 *   `ScaleAndRotateTransformation` is needed: the overlay is laid out on the
 *   upright, displayed frame, and a portrait take stays portrait. The encoder
 *   may still encode it landscape with a rotation in the MP4 metadata
 *   (`VideoSampleExporter.getSurfaceInfo`), which players apply.
 * - `OverlayMatrixProvider` first scales the overlay quad by
 *   overlaySize / frameSize, so scale (1, 1) draws the bitmap at its own pixel
 *   size; `getScale()` multiplies that. A band as wide as the frame thus
 *   needs scale = frameWidth / bandWidth on both axes (keeping its aspect).
 *   The frame size comes from `TextureOverlay.configure(videoSize)`, which
 *   `OverlayShaderProgram.configure` calls with the size of the frames the
 *   overlay is drawn on, so it's exact whatever the rotation.
 * - Anchors are in normalized device coordinates, y up: the band's bottom
 *   center (0, -1) on the frame's bottom center (0, -1). `BitmapOverlay`
 *   flips the bitmap vertically for GL, so its top row ends up on top.
 */
@UnstableApi
class TakeOverlay(private val context: Context, messenger: BinaryMessenger) :
    MethodChannel.MethodCallHandler {

    private val channel = MethodChannel(messenger, CHANNEL).also {
        it.setMethodCallHandler(this)
    }
    private val mainHandler = Handler(Looper.getMainLooper())
    // PNG decoding off the main thread; one at a time is enough.
    private val decoder = Executors.newSingleThreadExecutor()
    // Exports in progress, held so nothing collects them midway (main thread
    // only).
    private val running = mutableSetOf<Transformer>()

    override fun onMethodCall(call: MethodCall, result: MethodChannel.Result) {
        if (call.method != "burn") {
            result.notImplemented()
            return
        }
        val input = call.argument<String>("input")
        val output = call.argument<String>("output")
        val rawBands = call.argument<List<Map<String, Any?>>>("bands")
        if (input.isNullOrEmpty() || output.isNullOrEmpty() || rawBands == null) {
            result.error("failed", "burn needs input, output and bands", null)
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
        decoder.execute {
            val bands = try {
                decodeBands(rawBands)
            } catch (e: Exception) {
                mainHandler.post { result.error("failed", "Bad bands: ${e.message}", null) }
                return@execute
            }
            // Transformer must be built and started on a Looper thread; the
            // main one is fine, the export itself runs on its own threads.
            mainHandler.post { start(inputFile, outputFile, bands, result) }
        }
    }

    private fun start(
        input: File,
        output: File,
        bands: List<Band>,
        result: MethodChannel.Result,
    ) {
        val overlay = BandOverlay(bands)
        var transformer: Transformer? = null
        var replied = false
        fun finish(error: String?) {
            if (replied) return
            replied = true
            transformer?.let { running.remove(it) }
            bands.forEach { it.bitmap.recycle() }
            overlay.freeEmpty()
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
            val item = EditedMediaItem.Builder(MediaItem.fromUri(input.toURI().toString()))
                .setEffects(
                    Effects(
                        /* audioProcessors= */ ImmutableList.of(),
                        /* videoEffects= */ ImmutableList.of<Effect>(
                            OverlayEffect(ImmutableList.of<TextureOverlay>(overlay)),
                        ),
                    ),
                )
                .build()
            val built = Transformer.Builder(context)
                // H.264 + AAC in MP4. With no audio processors and AAC input,
                // the audio is copied as is, not re-encoded.
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
            built.start(item, output.path)
        } catch (e: Exception) {
            finish(e.message ?: e.toString())
        }
    }

    fun dispose() {
        channel.setMethodCallHandler(null)
        decoder.shutdown()
    }

    /** One neckline band: shown from [startUs] until [endUs] (exclusive). */
    private class Band(val startUs: Long, val endUs: Long, val bitmap: Bitmap)

    private fun decodeBands(raw: List<Map<String, Any?>>): List<Band> {
        val bands = ArrayList<Band>(raw.size)
        try {
            for (entry in raw) {
                val startMs = (entry["startMs"] as? Number)?.toLong()
                    ?: throw IllegalArgumentException("startMs missing")
                val endMs = (entry["endMs"] as? Number)?.toLong()
                val png = entry["png"] as? ByteArray
                    ?: throw IllegalArgumentException("png missing")
                val bitmap = BitmapFactory.decodeByteArray(png, 0, png.size)
                    ?: throw IllegalArgumentException("png not decodable")
                bands.add(
                    Band(
                        startUs = startMs * 1000,
                        endUs = if (endMs == null) Long.MAX_VALUE else endMs * 1000,
                        bitmap = bitmap,
                    ),
                )
            }
        } catch (e: Exception) {
            bands.forEach { it.bitmap.recycle() }
            throw e
        }
        return bands
    }

    /**
     * The band shown at each frame's time, or a 1x1 transparent bitmap in the
     * gaps. Its settings put it at the bottom, as wide as the frame.
     */
    private class BandOverlay(private val bands: List<Band>) : BitmapOverlay() {
        private val empty: Bitmap = Bitmap.createBitmap(1, 1, Bitmap.Config.ARGB_8888)
        // Written by configure and read by getOverlaySettings, both on
        // Media3's GL thread.
        private var settings: OverlaySettings = StaticOverlaySettings.Builder().build()

        override fun configure(videoSize: Size) {
            super.configure(videoSize)
            // All bands are the same width; the empty bitmap is transparent,
            // so its scale doesn't matter.
            val bandWidth = bands.firstOrNull()?.bitmap?.width ?: 1
            val scale = videoSize.width.toFloat() / bandWidth
            settings = StaticOverlaySettings.Builder()
                .setScale(scale, scale)
                .setBackgroundFrameAnchor(0f, -1f)
                .setOverlayFrameAnchor(0f, -1f)
                .build()
        }

        override fun getOverlaySettings(presentationTimeUs: Long): OverlaySettings = settings

        override fun getBitmap(presentationTimeUs: Long): Bitmap {
            for (band in bands) {
                if (presentationTimeUs < band.startUs) break
                if (presentationTimeUs < band.endUs) return band.bitmap
            }
            return empty
        }

        fun freeEmpty() = empty.recycle()
    }

    companion object {
        const val CHANNEL = "tabcam/take_overlay"
    }
}
