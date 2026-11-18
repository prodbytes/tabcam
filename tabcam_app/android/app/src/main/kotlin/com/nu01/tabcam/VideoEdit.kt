package com.nu01.tabcam

import android.content.Context
import android.graphics.Bitmap
import android.graphics.BitmapFactory
import android.net.Uri
import android.os.Handler
import android.os.Looper
import androidx.media3.common.C
import androidx.media3.common.Effect
import androidx.media3.common.MediaItem
import androidx.media3.common.MimeTypes
import androidx.media3.common.audio.AudioProcessor
import androidx.media3.common.audio.BaseAudioProcessor
import androidx.media3.common.audio.ChannelMixingAudioProcessor
import androidx.media3.common.audio.ChannelMixingMatrix
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
import java.nio.ByteBuffer
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
 * - `own`: the video's own sound, `{volume, mix}` (a gain from 0 to 2: its lane's
 *   level through the master's; `mix`, left out when it's as recorded, its
 *   channels and balance: each side of the output from the sound's two
 *   channels, `[ll, lr, rl, rr]`, a one-channel sound as both); left out,
 *   it's removed;
 * - `song`: the song lane, `{path, volume, mix, clips}` (volume and mix as
 *   `own`'s), each clip `{atMs, fromMs, toMs, speed}`: from `atMs` in the output (0 is the kept part's start),
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
 *
 * Method `samples` reads a part of a file's sound as samples ([SoundSamples]).
 */
@UnstableApi
class VideoEdit(context: Context, messenger: BinaryMessenger) :
    MethodChannel.MethodCallHandler {

    private val channel = MethodChannel(messenger, CHANNEL).also {
        it.setMethodCallHandler(this)
    }
    private val renderer = VideoRenderer(context)

    // A file's sound read as samples (`samples`), off the main thread.
    private val reader = Executors.newSingleThreadExecutor()
    private val main = Handler(Looper.getMainLooper())

    override fun onMethodCall(call: MethodCall, result: MethodChannel.Result) {
        if (call.method == "samples") {
            val path = call.argument<String>("path")
            val from = call.argument<Number>("fromMs")?.toLong()
            val length = call.argument<Number>("lengthMs")?.toLong()
            val rate = call.argument<Number>("rate")?.toInt()
            if (path == null || from == null || length == null || rate == null) {
                result.error("failed", "samples needs path, fromMs, lengthMs and rate", null)
                return
            }
            reader.execute {
                try {
                    val samples = SoundSamples.read(path, from, length, rate)
                    main.post { result.success(samples) }
                } catch (e: Exception) {
                    main.post { result.error("failed", e.message ?: e.toString(), null) }
                }
            }
            return
        }
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
        reader.shutdown()
    }

    companion object {
        const val CHANNEL = "tabcam/video_edit"
    }
}

/** A piece of the song lane: from [atMs] in the output, the song from [fromMs] to [toMs]. */
data class SongClip(val atMs: Long, val fromMs: Long, val toMs: Long, val speed: Double = 1.0)

/**
 * The song lane: [file], at [volume], its channels as [mix] says (null: as
 * recorded), heard in [clips] (in output order).
 */
@UnstableApi
data class SongLane(val file: File, val volume: Float, val clips: List<SongClip>, val mix: StereoMix? = null)

/**
 * A lane's channels and balance: each side of the output from the sound's
 * two channels, the left from the left ([ll]) and from the right ([lr]), the
 * right from the left ([rl]) and from the right ([rr]).
 */
@UnstableApi
data class StereoMix(val ll: Float, val lr: Float, val rl: Float, val rr: Float) {
    /**
     * Media3's matrices for it, into two channels: from a stereo sound, and
     * from a one-channel one (its channel as both of a stereo one's).
     * Coefficients are by input channel, then output channel.
     */
    fun matrices(): List<ChannelMixingMatrix> = listOf(
        ChannelMixingMatrix(2, 2, floatArrayOf(ll, rl, lr, rr)),
        ChannelMixingMatrix(1, 2, floatArrayOf(ll + lr, rl + rr)),
    )

    companion object {
        /** The channel's `mix`; null when left out. */
        fun fromArgs(value: Any?): StereoMix? {
            if (value == null) return null
            val list = (value as? List<*>)?.map { (it as? Number)?.toFloat() }
            require(list != null && list.size == 4 && list.all { it != null && !it.isNaN() }) {
                "Bad stereo mix"
            }
            val (ll, lr, rl, rr) = list.map { it!!.coerceIn(0f, 1f) }
            return StereoMix(ll, lr, rl, rr)
        }
    }
}

/** The loudest a lane can be: 200% (its level through the master's). */
const val MAX_VOLUME = 2f

/**
 * A constant [gain] above 1 on 16-bit or float PCM, each sample held within
 * its range (clipped, as the mixer does, rather than wrapped around).
 */
@UnstableApi
class ClippingGain(private val gain: Float) : BaseAudioProcessor() {
    override fun onConfigure(inputAudioFormat: AudioProcessor.AudioFormat): AudioProcessor.AudioFormat {
        if (inputAudioFormat.encoding != C.ENCODING_PCM_16BIT && inputAudioFormat.encoding != C.ENCODING_PCM_FLOAT) {
            throw AudioProcessor.UnhandledAudioFormatException(inputAudioFormat)
        }
        return inputAudioFormat
    }

    override fun queueInput(inputBuffer: ByteBuffer) {
        if (!inputBuffer.hasRemaining()) return
        val output = replaceOutputBuffer(inputBuffer.remaining())
        if (inputAudioFormat.encoding == C.ENCODING_PCM_16BIT) {
            while (inputBuffer.hasRemaining()) {
                val v = inputBuffer.getShort() * gain
                output.putShort(v.coerceIn(Short.MIN_VALUE.toFloat(), Short.MAX_VALUE.toFloat()).toInt().toShort())
            }
        } else {
            while (inputBuffer.hasRemaining()) {
                output.putFloat((inputBuffer.getFloat() * gain).coerceIn(-1f, 1f))
            }
        }
        output.flip()
    }
}

/** What `render` is asked: see [VideoEdit]. */
data class RenderPlan(
    val input: File,
    val output: File,
    val video: Boolean,
    val startMs: Long,
    val endMs: Long,
    /** The video's own sound's volume; null: removed. */
    val ownVolume: Float?,
    /** Its channels and balance; null: as recorded. */
    val ownMix: StereoMix? = null,
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
                ((map["volume"] as? Number)?.toFloat() ?: 1f).let { if (it.isNaN()) 1f else it.coerceIn(0f, MAX_VOLUME) }
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
                SongLane(File(path), volume(s), clips, StereoMix.fromArgs(s["mix"]))
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
                ownMix = own?.let { StereoMix.fromArgs(it["mix"]) },
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
 * its own sound (through a gain at its volume, unless 1: a `GainProcessor`,
 * or, louder than it is, a [ClippingGain]). The song
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
            val audioEffects = plan.ownVolume?.let { laneEffects(it, plan.ownMix) }?.audioProcessors.orEmpty()
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
            laneEffects(volume, plan.ownMix)?.let { own.setEffects(it) }
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
            laneEffects(song.volume, song.mix)?.let { item.setEffects(it) }
            builder.addItem(item.build())
            cursorMs = clip.atMs + (clip.toMs - clip.fromMs)
        }
        // A sequence that starts with a gap needs its audio forced.
        builder.experimentalSetForceAudioTrack(true)
        return builder.build()
    }

    /**
     * A lane's audio effects: its channels and balance ([mix], unless as
     * recorded: a `ChannelMixingAudioProcessor`, which makes it stereo),
     * then a gain at [volume], unless 1: louder than it is, a [ClippingGain]
     * (a `GainProcessor` wraps 16-bit samples it lifts past their range).
     * Null when it has none.
     */
    private fun laneEffects(volume: Float, mix: StereoMix?): Effects? {
        val processors = mutableListOf<AudioProcessor>()
        if (mix != null) {
            processors.add(ChannelMixingAudioProcessor().apply { mix.matrices().forEach { putChannelMixingMatrix(it) } })
        }
        when {
            volume == 1f -> {}
            volume > 1f -> processors.add(ClippingGain(volume))
            else -> processors.add(GainProcessor(DefaultGainProvider.Builder(volume).build()))
        }
        return if (processors.isEmpty()) null else Effects(processors, emptyList())
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
