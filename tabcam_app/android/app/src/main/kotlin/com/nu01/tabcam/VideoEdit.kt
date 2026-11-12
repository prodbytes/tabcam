package com.nu01.tabcam

import android.content.Context
import android.graphics.Bitmap
import android.graphics.BitmapFactory
import android.net.Uri
import android.os.Handler
import android.os.Looper
import androidx.media3.common.Effect
import androidx.media3.common.MediaItem
import androidx.media3.common.MimeTypes
import androidx.media3.common.audio.DefaultGainProvider
import androidx.media3.common.audio.GainProcessor
import androidx.media3.common.util.UnstableApi
import androidx.media3.effect.OverlayEffect
import androidx.media3.effect.TextureOverlay
import androidx.media3.transformer.Composition
import androidx.media3.transformer.EditedMediaItem
import androidx.media3.transformer.EditedMediaItemSequence
import androidx.media3.transformer.Effects
import androidx.media3.transformer.ExportException
import androidx.media3.transformer.ExportResult
import androidx.media3.transformer.ProgressHolder
import androidx.media3.transformer.Transformer
import io.flutter.plugin.common.BinaryMessenger
import io.flutter.plugin.common.MethodCall
import io.flutter.plugin.common.MethodChannel
import java.io.File
import java.util.concurrent.Executors

/**
 * Renders an edit's plan (lib/capture/render_plan.dart) on the device, with
 * Media3 Transformer.
 *
 * Channel `tabcam/video_edit`, method `render`, arguments (the plan's
 * `toChannel`):
 * - `input`: absolute path of the video;
 * - `output`: absolute path of the file to write (its folder exists);
 * - `video`: false for the sound alone (AAC in MP4, an `.m4a`), true (the
 *   default) for the video (H.264 and AAC in MP4);
 * - `startMs`, `endMs`: the part of the video kept;
 * - `own`: the video's own sound, `{volume}` (a gain from 0 to 1); left out,
 *   it's removed;
 * - `song`: the song lane, `{path, volume, clips}`, each clip `{atMs, fromMs,
 *   toMs, speed}`: from `atMs` in the output (0 is the kept part's start),
 *   the song from `fromMs` to `toMs` (the app works the times out and cuts
 *   them to the output; only speed 1 for now);
 * - `images`: the layers' PNGs (each look once), and `layers`: what's drawn
 *   over the picture, each `{id, image (its index in images), anchor
 *   (topLeft, bottomRight or bottomFull), heightU, marginU, liftU (fractions
 *   of the frame's short side), liftW (a fraction of its width), fromMs, toMs
 *   (null: the end), fadeInMs, opacity}`, in the output's times; ignored for the sound alone;
 * - `fadeInMs`, `fadeOutMs` (left out: none): the output fades in from black
 *   (the picture, with its layers) and silence over its first `fadeInMs`, and
 *   out to them over its last `fadeOutMs`, straight lines (the app keeps each
 *   at most half the kept part);
 * - `job`: when given, `progress` calls back to the app with `{job, done}`
 *   (0 to 1) every quarter of a second while it renders.
 *
 * Replies with the output path, or the error `failed`.
 */
@UnstableApi
class VideoEdit(context: Context, messenger: BinaryMessenger) :
    MethodChannel.MethodCallHandler {

    private val channel = MethodChannel(messenger, CHANNEL).also {
        it.setMethodCallHandler(this)
    }
    private val renderer = VideoRenderer(context)

    override fun onMethodCall(call: MethodCall, result: MethodChannel.Result) {
        if (call.method != "render") {
            result.notImplemented()
            return
        }
        val plan = try {
            RenderPlan.fromArgs(call.arguments as? Map<*, *> ?: emptyMap<String, Any>())
        } catch (e: Exception) {
            result.error("failed", e.message ?: e.toString(), null)
            return
        }
        val job = (call.argument<Number>("job"))?.toInt()
        renderer.render(
            plan,
            progress = job?.let { id ->
                { done: Double -> channel.invokeMethod("progress", mapOf("job" to id, "done" to done)) }
            },
        ) { error ->
            if (error == null) result.success(plan.output.path) else result.error("failed", error, null)
        }
    }

    fun dispose() {
        channel.setMethodCallHandler(null)
        renderer.dispose()
    }

    companion object {
        const val CHANNEL = "tabcam/video_edit"
    }
}

/** A piece of the song lane: from [atMs] in the output, the song from [fromMs] to [toMs]. */
data class SongClip(val atMs: Long, val fromMs: Long, val toMs: Long, val speed: Double = 1.0)

/** The song lane: [file], at [volume], heard in [clips] (in output order). */
data class SongLane(val file: File, val volume: Float, val clips: List<SongClip>)

/** What `render` is asked: see [VideoEdit]. */
data class RenderPlan(
    val input: File,
    val output: File,
    val video: Boolean,
    val startMs: Long,
    val endMs: Long,
    /** The video's own sound's volume; null: removed. */
    val ownVolume: Float?,
    val song: SongLane?,
    /** What's drawn over the picture, each naming one of [images] (PNGs). */
    val layers: List<PlanLayer> = emptyList(),
    val images: List<ByteArray> = emptyList(),
    /** The fades in and out, over the kept part. */
    val fades: Fades = Fades(),
) {
    companion object {
        fun fromArgs(args: Map<*, *>): RenderPlan {
            fun long(map: Map<*, *>, key: String): Long? = (map[key] as? Number)?.toLong()
            fun volume(map: Map<*, *>): Float =
                ((map["volume"] as? Number)?.toFloat() ?: 1f).let { if (it.isNaN()) 1f else it.coerceIn(0f, 1f) }
            val input = args["input"] as? String
            val output = args["output"] as? String
            val startMs = long(args, "startMs")
            val endMs = long(args, "endMs")
            require(!input.isNullOrEmpty() && !output.isNullOrEmpty() && startMs != null && endMs != null) {
                "render needs input, output, startMs and endMs"
            }
            val own = args["own"] as? Map<*, *>
            val song = (args["song"] as? Map<*, *>)?.let { s ->
                val path = s["path"] as? String
                require(!path.isNullOrEmpty()) { "A song lane needs a file" }
                val clips = (s["clips"] as? List<*>).orEmpty().map { c ->
                    val clip = c as? Map<*, *> ?: throw IllegalArgumentException("Bad song clip")
                    SongClip(
                        atMs = long(clip, "atMs") ?: throw IllegalArgumentException("Bad song clip"),
                        fromMs = long(clip, "fromMs") ?: throw IllegalArgumentException("Bad song clip"),
                        toMs = long(clip, "toMs") ?: throw IllegalArgumentException("Bad song clip"),
                        speed = (clip["speed"] as? Number)?.toDouble() ?: 1.0,
                    )
                }
                SongLane(File(path), volume(s), clips)
            }
            val images = (args["images"] as? List<*>).orEmpty().map {
                it as? ByteArray ?: throw IllegalArgumentException("Bad layer image")
            }
            val layers = (args["layers"] as? List<*>).orEmpty().map {
                PlanLayer.fromArgs(it as? Map<*, *> ?: throw IllegalArgumentException("Bad layer"), images.size)
            }
            return RenderPlan(
                input = File(input),
                output = File(output),
                video = args["video"] as? Boolean ?: true,
                startMs = startMs,
                endMs = endMs,
                ownVolume = own?.let { volume(it) },
                song = song,
                layers = layers,
                images = images,
                fades = Fades(
                    fadeInMs = (long(args, "fadeInMs") ?: 0L).coerceAtLeast(0L),
                    fadeOutMs = (long(args, "fadeOutMs") ?: 0L).coerceAtLeast(0L),
                    lengthMs = endMs - startMs,
                ),
            )
        }
    }
}

/**
 * The Media3 side of `render`, free of the method channel (the instrumented
 * test calls it directly).
 *
 * The composition (Media3 1.9.2): with the video, the primary sequence is
 * the video clipped to the kept part, its audio removed unless the plan keeps
 * its own sound (through a `GainProcessor` at its volume, unless 1). The song
 * lane is a second sequence: for each clip, silence (a gap) up to where it
 * starts, then the song clipped to its part, at the lane's volume; the
 * composition forces an audio track when the primary has none. A secondary
 * sequence longer than the primary is cut to it. The sound alone has no
 * picture: the video's own sound clipped (when kept) and the song's
 * sequence, so it ends where the sound does.
 *
 * The layers (with the picture only) are an `OverlayEffect` on the video:
 * one [LayersOverlay] per kind of layer (`id`: the tab's bands, the title,
 * the watermark), its PNGs decoded off the main thread and let go once it's
 * done; then, over them all, the fades' black ([FadeOverlay]). The fades'
 * sound is one `GainProcessor` on the composition, after the lanes are mixed
 * (Transformer's `AudioGraph` runs the composition's audio effects on the
 * mix), its gain ramped in and out on the output's samples.
 */
@UnstableApi
class VideoRenderer(private val context: Context) {
    private val mainHandler = Handler(Looper.getMainLooper())

    // Exports in progress, held so nothing collects them midway (main thread
    // only).
    private val running = mutableSetOf<Transformer>()

    // PNG decoding and the composition, off the main thread; one at a time.
    private val worker = Executors.newSingleThreadExecutor()

    /**
     * Renders [plan]; [progress] (on the main thread) gets how much is done,
     * 0 to 1, every quarter of a second; [done] (on the main thread, once)
     * null on success or an error message.
     */
    fun render(plan: RenderPlan, progress: ((Double) -> Unit)? = null, done: (String?) -> Unit) {
        if (!plan.input.isFile) {
            mainHandler.post { done("No video at ${plan.input.path}") }
            return
        }
        if (plan.input.canonicalPath == plan.output.canonicalPath) {
            mainHandler.post { done("Output must differ from input") }
            return
        }
        worker.execute {
            val bitmaps = mutableListOf<Bitmap>()
            fun free() = bitmaps.forEach { it.recycle() }
            val composition = try {
                if (plan.video) bitmaps.addAll(decode(plan.images))
                compose(plan, bitmaps)
            } catch (e: Exception) {
                free()
                val message = e.message ?: e.toString()
                mainHandler.post { done(message) }
                return@execute
            }
            // Transformer must be built and started on a Looper thread; the
            // main one is fine, the export itself runs on its own threads.
            mainHandler.post {
                start(composition, plan.output, progress) { error ->
                    free()
                    done(error)
                }
            }
        }
    }

    /** Lets the worker thread go (a render under way finishes first). */
    fun dispose() = worker.shutdown()

    private fun decode(images: List<ByteArray>): List<Bitmap> {
        val bitmaps = mutableListOf<Bitmap>()
        try {
            for (png in images) {
                bitmaps.add(
                    BitmapFactory.decodeByteArray(png, 0, png.size)
                        ?: throw IllegalArgumentException("A layer's image isn't a PNG"),
                )
            }
        } catch (e: Exception) {
            bitmaps.forEach { it.recycle() }
            throw e
        }
        return bitmaps
    }

    /**
     * The overlays of [layers] (their images [bitmaps]): one per kind; then,
     * with [fades], their black over them all.
     */
    private fun overlays(layers: List<PlanLayer>, bitmaps: List<Bitmap>, fades: Fades): List<TextureOverlay> =
        layers.groupBy { it.id }.values.map { group ->
            LayersOverlay(group.sortedBy { it.fromMs }, bitmaps) as TextureOverlay
        } + listOfNotNull(if (fades.any) FadeOverlay(fades) else null)

    private fun compose(plan: RenderPlan, bitmaps: List<Bitmap>): Composition {
        require(plan.endMs > plan.startMs) { "Nothing to keep" }
        val song = plan.song
        if (song != null) {
            require(song.file.isFile) { "No song at ${song.file.path}" }
            require(song.clips.all { it.speed == 1.0 }) { "A song at another speed can't be rendered yet" }
        }
        val songSequence = song?.takeIf { it.clips.isNotEmpty() }?.let { songSequence(it) }
        val sequences = mutableListOf<EditedMediaItemSequence>()
        if (plan.video) {
            val video = EditedMediaItem.Builder(clipped(plan.input, plan.startMs, plan.endMs))
                .setRemoveAudio(plan.ownVolume == null)
            val audioEffects = plan.ownVolume?.let { gain(it) }?.audioProcessors.orEmpty()
            val videoEffects = if (plan.layers.isEmpty() && !plan.fades.any) {
                emptyList<Effect>()
            } else {
                listOf<Effect>(OverlayEffect(overlays(plan.layers, bitmaps, plan.fades)))
            }
            if (audioEffects.isNotEmpty() || videoEffects.isNotEmpty()) {
                video.setEffects(Effects(audioEffects, videoEffects))
            }
            sequences.add(EditedMediaItemSequence.Builder(video.build()).build())
            songSequence?.let { sequences.add(it) }
            return Composition.Builder(sequences)
                // The primary sequence has no audio of its own then:
                // silence, with the song mixed in.
                .experimentalSetForceAudioTrack(plan.ownVolume == null && song != null)
                .faded(plan.fades)
                .build()
        }
        plan.ownVolume?.let { volume ->
            val own = EditedMediaItem.Builder(clipped(plan.input, plan.startMs, plan.endMs))
                .setRemoveVideo(true)
            gain(volume)?.let { own.setEffects(it) }
            sequences.add(EditedMediaItemSequence.Builder(own.build()).build())
        }
        songSequence?.let { sequences.add(it) }
        require(sequences.isNotEmpty()) { "There is no sound to keep" }
        return Composition.Builder(sequences).faded(plan.fades).build()
    }

    /** The mix of the composition fading in and out as [fades] say. */
    private fun Composition.Builder.faded(fades: Fades): Composition.Builder {
        if (!fades.any) return this
        val gain = DefaultGainProvider.Builder(1f)
        if (fades.fadeInMs > 0) {
            gain.addFadeAt(0, fades.fadeInMs * 1000, DefaultGainProvider.FADE_IN_LINEAR)
        }
        if (fades.fadeOutMs > 0) {
            gain.addFadeAt(fades.fadeOutStartMs * 1000, fades.fadeOutMs * 1000, DefaultGainProvider.FADE_OUT_LINEAR)
        }
        return setEffects(Effects(listOf(GainProcessor(gain.build())), emptyList()))
    }

    /** The song lane as a sequence: gaps of silence, and its clips. */
    private fun songSequence(song: SongLane): EditedMediaItemSequence {
        val builder = EditedMediaItemSequence.Builder(emptyList<EditedMediaItem>())
        var cursorMs = 0L
        for (clip in song.clips) {
            require(clip.toMs > clip.fromMs && clip.fromMs >= 0 && clip.atMs >= cursorMs) {
                "Bad song clip"
            }
            if (clip.atMs > cursorMs) builder.addGap((clip.atMs - cursorMs) * 1000)
            val item = EditedMediaItem.Builder(clipped(song.file, clip.fromMs, clip.toMs))
                .setRemoveVideo(true)
            gain(song.volume)?.let { item.setEffects(it) }
            builder.addItem(item.build())
            cursorMs = clip.atMs + (clip.toMs - clip.fromMs)
        }
        // A sequence that starts with a gap needs its audio forced.
        builder.experimentalSetForceAudioTrack(true)
        return builder.build()
    }

    /** A gain at [volume], unless 1. */
    private fun gain(volume: Float): Effects? =
        if (volume == 1f) {
            null
        } else {
            Effects(listOf(GainProcessor(DefaultGainProvider.Builder(volume).build())), emptyList())
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

    private fun start(
        composition: Composition,
        output: File,
        progress: ((Double) -> Unit)?,
        done: (String?) -> Unit,
    ) {
        var transformer: Transformer? = null
        var replied = false
        val holder = ProgressHolder()
        val poll = object : Runnable {
            override fun run() {
                val t = transformer ?: return
                if (replied) return
                if (t.getProgress(holder) == Transformer.PROGRESS_STATE_AVAILABLE) {
                    progress?.invoke(holder.progress / 100.0)
                }
                mainHandler.postDelayed(this, PROGRESS_EVERY_MS)
            }
        }
        fun finish(error: String?) {
            if (replied) return
            replied = true
            mainHandler.removeCallbacks(poll)
            transformer?.let { running.remove(it) }
            if (error != null) output.delete()
            done(error)
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
                        progress?.invoke(1.0)
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
            if (progress != null) mainHandler.postDelayed(poll, PROGRESS_EVERY_MS)
        } catch (e: Exception) {
            finish(e.message ?: e.toString())
        }
    }

    companion object {
        private const val PROGRESS_EVERY_MS = 250L
    }
}
