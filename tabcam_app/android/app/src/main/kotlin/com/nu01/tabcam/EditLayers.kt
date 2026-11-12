package com.nu01.tabcam

import android.graphics.Bitmap
import androidx.media3.common.OverlaySettings
import androidx.media3.common.util.Size
import androidx.media3.common.util.UnstableApi
import androidx.media3.effect.BitmapOverlay
import androidx.media3.effect.StaticOverlaySettings
import kotlin.math.min
import kotlin.math.roundToInt

/**
 * The fades of an output [lengthMs] long (lib/capture/render_plan.dart,
 * `Fades`): in from black and silence over [fadeInMs] from its start, out to
 * them over [fadeOutMs] to its end, straight lines. Each is at most half the
 * output (the app keeps them so; here too, so they never overlap).
 */
data class Fades(val fadeInMs: Long = 0, val fadeOutMs: Long = 0, val lengthMs: Long = 0) {
    private val inMs = fadeInMs.coerceIn(0L, (lengthMs / 2).coerceAtLeast(0L))
    private val outMs = fadeOutMs.coerceIn(0L, (lengthMs / 2).coerceAtLeast(0L))

    /** Whether there's any. */
    val any: Boolean get() = inMs > 0 || outMs > 0

    /** Where the fade out starts in the output. */
    val fadeOutStartMs: Long get() = lengthMs - outMs

    /**
     * How much of the picture and the sound comes through [us] into the
     * output, 0 to 1 (as `Fades.levelAt` in Dart); 0 outside it.
     */
    fun levelAt(us: Long): Float {
        if (!any) return 1f
        if (us < 0 || us > lengthMs * 1000) return 0f
        var level = 1f
        if (inMs > 0 && us < inMs * 1000) level = us.toFloat() / (inMs * 1000)
        val left = lengthMs * 1000 - us
        if (outMs > 0 && left < outMs * 1000) level = min(level, left.toFloat() / (outMs * 1000))
        return level.coerceIn(0f, 1f)
    }

    /** How dark the fades leave the frame [us] into the output, in 64ths. */
    fun darknessAt(us: Long): Int = ((1f - levelAt(us)) * 64).roundToInt().coerceIn(0, 64)
}

/** Where a layer sits on the frame (lib/capture/render_plan.dart, `LayerAnchor`). */
enum class LayerAnchor {
    TOP_LEFT,
    BOTTOM_RIGHT,
    BOTTOM_FULL;

    companion object {
        fun of(name: Any?): LayerAnchor = when (name) {
            "topLeft" -> TOP_LEFT
            "bottomRight" -> BOTTOM_RIGHT
            "bottomFull" -> BOTTOM_FULL
            else -> throw IllegalArgumentException("Bad layer anchor $name")
        }
    }
}

/**
 * A layer drawn over the video (the plan's `layers`, see
 * lib/capture/render_plan.dart, `PlanLayer`): the plan's [image]th image,
 * placed by [anchor] ([heightU] high, [marginU] in from the corner and
 * [liftU] higher, as fractions of the frame's short side, and [liftW] higher
 * still, as a fraction of its width: above the tab's tallest band, which is
 * as wide as the frame; a bottom band as wide as the frame), shown from [fromMs] to [toMs] (null: the end) in the
 * output, fading in over [fadeInMs] to [opacity].
 */
data class PlanLayer(
    val id: String,
    val image: Int,
    val anchor: LayerAnchor,
    val heightU: Float = 0f,
    val marginU: Float = 0f,
    val liftU: Float = 0f,
    val liftW: Float = 0f,
    val fromMs: Long = 0,
    val toMs: Long? = null,
    val fadeInMs: Long = 0,
    val opacity: Float = 1f,
) {
    /** How opaque it is [us] into the output: 0 outside it. */
    fun alphaAt(us: Long): Float {
        if (us < fromMs * 1000 || (toMs != null && us >= toMs * 1000)) return 0f
        if (fadeInMs <= 0) return opacity
        return opacity * min(1f, (us - fromMs * 1000).toFloat() / (fadeInMs * 1000))
    }

    companion object {
        fun fromArgs(map: Map<*, *>, images: Int): PlanLayer {
            fun float(key: String, default: Float): Float =
                (map[key] as? Number)?.toFloat()?.takeIf { it.isFinite() } ?: default
            val image = (map["image"] as? Number)?.toInt()
            require(image != null && image in 0 until images) { "Bad layer image" }
            val fromMs = (map["fromMs"] as? Number)?.toLong() ?: 0L
            return PlanLayer(
                id = map["id"] as? String ?: "",
                image = image,
                anchor = LayerAnchor.of(map["anchor"]),
                heightU = float("heightU", 0f),
                marginU = float("marginU", 0f),
                liftU = float("liftU", 0f),
                liftW = float("liftW", 0f),
                fromMs = fromMs,
                toMs = (map["toMs"] as? Number)?.toLong(),
                fadeInMs = (map["fadeInMs"] as? Number)?.toLong() ?: 0L,
                opacity = float("opacity", 1f).coerceIn(0f, 1f),
            )
        }
    }
}

/**
 * Where Media3 draws an overlay (`StaticOverlaySettings`): [scale] times the
 * image's own pixel size (`OverlayMatrixProvider` first scales the overlay
 * quad by overlaySize / frameSize, so scale 1 draws it at its own size), its
 * point ([overlayX], [overlayY]) on the frame's ([frameX], [frameY]), both
 * in normalized device coordinates, y up.
 */
data class Placement(
    val scale: Float,
    val overlayX: Float,
    val overlayY: Float,
    val frameX: Float,
    val frameY: Float,
)

/** The layers' layout, free of Media3 (the JVM tests check it). */
object LayerLayout {
    /**
     * [layer]'s placement on a frame [frameW] × [frameH] (upright, as shown),
     * its image [imageW] × [imageH]: as `PlanLayer.rectIn` places it in Dart.
     */
    fun place(layer: PlanLayer, frameW: Int, frameH: Int, imageW: Int, imageH: Int): Placement {
        val w = frameW.toFloat()
        val h = frameH.toFloat()
        val short = min(w, h)
        val margin = layer.marginU * short
        return when (layer.anchor) {
            LayerAnchor.BOTTOM_FULL -> Placement(w / imageW.coerceAtLeast(1), 0f, -1f, 0f, -1f)
            LayerAnchor.TOP_LEFT -> Placement(
                layer.heightU * short / imageH.coerceAtLeast(1),
                -1f, 1f,
                -1f + 2 * margin / w, 1f - 2 * margin / h,
            )
            LayerAnchor.BOTTOM_RIGHT -> Placement(
                layer.heightU * short / imageH.coerceAtLeast(1),
                1f, -1f,
                1f - 2 * margin / w,
                -1f + 2 * (margin + layer.liftU * short + layer.liftW * w) / h,
            )
        }
    }

    /**
     * Of [layers] (in time order, none overlapping another), the one
     * showing [us] into the output (its alpha above 0); null for none.
     */
    fun showing(layers: List<PlanLayer>, us: Long): Int? {
        // The last that starts at or before it.
        var low = 0
        var high = layers.size - 1
        var found = -1
        while (low <= high) {
            val mid = (low + high) ushr 1
            if (layers[mid].fromMs * 1000 <= us) {
                found = mid
                low = mid + 1
            } else {
                high = mid - 1
            }
        }
        return found.takeIf { it >= 0 && layers[it].alphaAt(us) > 0f }
    }
}

/**
 * The fades' black over the whole frame: a small black bitmap scaled to it,
 * as opaque as [Fades.levelAt] leaves it dark (in 64 steps), hidden where
 * there's no fade. Its time base is [LayersOverlay]'s: the first frame's is
 * the output's 0.
 */
@UnstableApi
class FadeOverlay(private val fades: Fades) : BitmapOverlay() {
    private val black: Bitmap = Bitmap.createBitmap(SIDE, SIDE, Bitmap.Config.ARGB_8888).apply {
        eraseColor(android.graphics.Color.BLACK)
    }
    private val hidden: OverlaySettings = StaticOverlaySettings.Builder().setAlphaScale(0f).build()

    // All on Media3's GL thread.
    private var scaleX = 1f
    private var scaleY = 1f
    private var baseUs = Long.MIN_VALUE
    private val settings = HashMap<Int, OverlaySettings>()

    override fun configure(videoSize: Size) {
        super.configure(videoSize)
        scaleX = videoSize.width.toFloat() / SIDE
        scaleY = videoSize.height.toFloat() / SIDE
        settings.clear()
    }

    override fun getBitmap(presentationTimeUs: Long): Bitmap = black

    override fun getOverlaySettings(presentationTimeUs: Long): OverlaySettings {
        if (baseUs == Long.MIN_VALUE) baseUs = presentationTimeUs
        val step = fades.darknessAt(presentationTimeUs - baseUs)
        if (step == 0) return hidden
        return settings.getOrPut(step) {
            StaticOverlaySettings.Builder()
                .setScale(scaleX, scaleY)
                .setAlphaScale(step / 64f)
                .build()
        }
    }

    override fun release() {
        super.release()
        black.recycle()
    }

    companion object {
        private const val SIDE = 16
    }
}

/**
 * One kind of layer (the tab's bands, the title, the watermark), as one
 * Media3 overlay: at each frame, the layer showing then (its bitmap, where
 * its anchor puts it, as opaque as it is then), or a transparent pixel.
 *
 * The time base: the first frame's `presentationTimeUs` is taken as the
 * output's 0, so it's right whether Media3 counts a clipped item's frames
 * from its clip's start or from the file's (check on a device: the
 * `TABCAM_TAB_OVER_BURNED` build draws the bands over a take's burned ones).
 *
 * Rotation and layout (checked against the Media3 1.9.2 sources):
 * Transformer's `DefaultDecoderFactory` configures the decoder with the
 * input's `KEY_ROTATION` and decodes to a surface, so the frames the effects
 * see are already rotated for display, and `configure` gets the size of the
 * frames the overlay is drawn on (`OverlayShaderProgram.configure`): the
 * frame as shown, whatever the rotation, so a portrait video's layers sit on
 * it upright. The encoder may still write it landscape with a rotation in
 * the MP4's metadata, which players apply. `BitmapOverlay` flips the bitmap
 * for GL, so its top row ends up on top.
 */
@UnstableApi
class LayersOverlay(
    private val layers: List<PlanLayer>,
    private val bitmaps: List<Bitmap>,
) : BitmapOverlay() {
    private val empty: Bitmap = Bitmap.createBitmap(1, 1, Bitmap.Config.ARGB_8888)
    private val hidden: OverlaySettings = StaticOverlaySettings.Builder().setAlphaScale(0f).build()

    // All on Media3's GL thread.
    private var placements: List<Placement> = emptyList()
    private var baseUs = Long.MIN_VALUE
    private val settings = HashMap<Long, OverlaySettings>()

    override fun configure(videoSize: Size) {
        super.configure(videoSize)
        placements = layers.map { layer ->
            val bitmap = bitmaps[layer.image]
            LayerLayout.place(layer, videoSize.width, videoSize.height, bitmap.width, bitmap.height)
        }
        settings.clear()
    }

    /** [presentationTimeUs] in the output: from the first frame's. */
    private fun outputUs(presentationTimeUs: Long): Long {
        if (baseUs == Long.MIN_VALUE) baseUs = presentationTimeUs
        return presentationTimeUs - baseUs
    }

    override fun getBitmap(presentationTimeUs: Long): Bitmap {
        val showing = LayerLayout.showing(layers, outputUs(presentationTimeUs)) ?: return empty
        return bitmaps[layers[showing].image]
    }

    override fun getOverlaySettings(presentationTimeUs: Long): OverlaySettings {
        val us = outputUs(presentationTimeUs)
        val showing = LayerLayout.showing(layers, us) ?: return hidden
        val place = placements.getOrNull(showing) ?: return hidden
        // Alpha in 64 steps: one settings object per layer and step.
        val step = (layers[showing].alphaAt(us) * 64).toInt().coerceIn(1, 64)
        return settings.getOrPut(showing.toLong() * 65 + step) {
            StaticOverlaySettings.Builder()
                .setScale(place.scale, place.scale)
                .setOverlayFrameAnchor(place.overlayX, place.overlayY)
                .setBackgroundFrameAnchor(place.frameX, place.frameY)
                .setAlphaScale(step / 64f)
                .build()
        }
    }

    override fun release() {
        super.release()
        empty.recycle()
    }
}
