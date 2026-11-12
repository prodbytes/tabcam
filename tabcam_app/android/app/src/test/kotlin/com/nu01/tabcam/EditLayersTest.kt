package com.nu01.tabcam

import org.junit.Assert.assertEquals
import org.junit.Assert.assertNull
import org.junit.Assert.assertThrows
import org.junit.Test

/** The layers' layout and timing ([LayerLayout], [PlanLayer]), on the JVM. */
class EditLayersTest {
    private fun assertPlaced(expected: Placement, actual: Placement) {
        assertEquals(expected.scale, actual.scale, 1e-5f)
        assertEquals(expected.overlayX, actual.overlayX, 1e-5f)
        assertEquals(expected.overlayY, actual.overlayY, 1e-5f)
        assertEquals(expected.frameX, actual.frameX, 1e-5f)
        assertEquals(expected.frameY, actual.frameY, 1e-5f)
    }

    @Test
    fun aBandIsAsWideAsTheFrameAlongItsBottom() {
        val band = PlanLayer("tab", 0, LayerAnchor.BOTTOM_FULL)
        // Landscape and portrait: scaled to the frame's width.
        assertPlaced(Placement(1.5f, 0f, -1f, 0f, -1f), LayerLayout.place(band, 1920, 1080, 1280, 240))
        assertPlaced(Placement(0.84375f, 0f, -1f, 0f, -1f), LayerLayout.place(band, 1080, 1920, 1280, 240))
    }

    @Test
    fun cornersBySizeAndMarginOfTheShortSide() {
        // 10% of the short side (1080) high, 5% in: 108 px high from a 200 px
        // image, 54 px in from the top left of 1920 x 1080.
        val title = PlanLayer("title", 0, LayerAnchor.TOP_LEFT, heightU = 0.1f, marginU = 0.05f)
        assertPlaced(
            Placement(0.54f, -1f, 1f, -1f + 2 * 54f / 1920, 1f - 2 * 54f / 1080),
            LayerLayout.place(title, 1920, 1080, 400, 200),
        )
        // The same in portrait: the short side is the width.
        assertPlaced(
            Placement(0.54f, -1f, 1f, -1f + 2 * 54f / 1080, 1f - 2 * 54f / 1920),
            LayerLayout.place(title, 1080, 1920, 400, 200),
        )
        // Bottom right, lifted 20% of the short side more.
        val mark = PlanLayer("mark", 0, LayerAnchor.BOTTOM_RIGHT, heightU = 0.1f, marginU = 0.05f, liftU = 0.2f)
        assertPlaced(
            Placement(0.54f, 1f, -1f, 1f - 2 * 54f / 1920, -1f + 2 * (54f + 216f) / 1080),
            LayerLayout.place(mark, 1920, 1080, 400, 200),
        )
        // The watermark over the tab: lifted by its tallest band, a tenth of
        // the frame's width (192 px of 1920), above its margin.
        val lifted = PlanLayer("mark", 0, LayerAnchor.BOTTOM_RIGHT, heightU = 0.1f, marginU = 0.05f, liftW = 0.1f)
        assertPlaced(
            Placement(0.54f, 1f, -1f, 1f - 2 * 54f / 1920, -1f + 2 * (54f + 192f) / 1080),
            LayerLayout.place(lifted, 1920, 1080, 400, 200),
        )
        // Portrait: a tenth of its width is 108 px.
        assertPlaced(
            Placement(0.54f, 1f, -1f, 1f - 2 * 54f / 1080, -1f + 2 * (54f + 108f) / 1920),
            LayerLayout.place(lifted, 1080, 1920, 400, 200),
        )
    }

    @Test
    fun opaqueOnlyWhileItShowsFadingIn() {
        val band = PlanLayer("tab", 0, LayerAnchor.BOTTOM_FULL, fromMs = 1000, toMs = 2000)
        assertEquals(0f, band.alphaAt(999_999), 0f)
        assertEquals(1f, band.alphaAt(1_000_000), 0f)
        assertEquals(1f, band.alphaAt(1_999_999), 0f)
        assertEquals(0f, band.alphaAt(2_000_000), 0f)
        val title = PlanLayer("title", 0, LayerAnchor.TOP_LEFT, fromMs = 0, fadeInMs = 3000, opacity = 0.8f)
        assertEquals(0f, title.alphaAt(0), 0f)
        assertEquals(0.4f, title.alphaAt(1_500_000), 1e-5f)
        assertEquals(0.8f, title.alphaAt(3_000_000), 0f)
        assertEquals(0.8f, title.alphaAt(600_000_000), 0f)
    }

    @Test
    fun theBandShowingThen() {
        val bands = listOf(
            PlanLayer("tab", 0, LayerAnchor.BOTTOM_FULL, fromMs = 0, toMs = 1210),
            PlanLayer("tab", 1, LayerAnchor.BOTTOM_FULL, fromMs = 1210, toMs = 5380),
            PlanLayer("tab", 0, LayerAnchor.BOTTOM_FULL, fromMs = 6000, toMs = 9000),
        )
        assertEquals(0, LayerLayout.showing(bands, 0))
        assertEquals(1, LayerLayout.showing(bands, 1_210_000))
        assertEquals(1, LayerLayout.showing(bands, 5_379_999))
        assertNull(LayerLayout.showing(bands, 5_500_000))
        assertEquals(2, LayerLayout.showing(bands, 8_000_000))
        assertNull(LayerLayout.showing(bands, 9_000_000))
        assertNull(LayerLayout.showing(emptyList(), 0))
    }

    @Test
    fun readsTheChannelsLayers() {
        val png = byteArrayOf(1, 2, 3)
        val plan = RenderPlan.fromArgs(
            mapOf(
                "input" to "/tmp/in.mp4", "output" to "/tmp/out.mp4", "startMs" to 0, "endMs" to 1000,
                "images" to listOf(png),
                "layers" to listOf(
                    mapOf(
                        "id" to "tab", "image" to 0, "anchor" to "bottomFull", "heightU" to 0,
                        "marginU" to 0, "liftU" to 0, "fromMs" to 0, "toMs" to 500, "fadeInMs" to 0,
                        "opacity" to 1.0,
                    ),
                    mapOf(
                        "id" to "mark", "image" to 0, "anchor" to "bottomRight", "heightU" to 0.03,
                        "marginU" to 0.03, "liftU" to 0, "liftW" to 0.25, "fromMs" to 0, "toMs" to null,
                        "fadeInMs" to 0, "opacity" to 1.0,
                    ),
                ),
            ),
        )
        assertEquals(
            listOf(
                PlanLayer("tab", 0, LayerAnchor.BOTTOM_FULL, toMs = 500),
                PlanLayer("mark", 0, LayerAnchor.BOTTOM_RIGHT, heightU = 0.03f, marginU = 0.03f, liftW = 0.25f),
            ),
            plan.layers,
        )
        assertEquals(1, plan.images.size)
        // A layer naming an image that isn't there, or a bad anchor: refused.
        for (bad in listOf(mapOf("image" to 1, "anchor" to "topLeft"), mapOf("image" to 0, "anchor" to "middle"))) {
            assertThrows(IllegalArgumentException::class.java) {
                RenderPlan.fromArgs(
                    mapOf(
                        "input" to "/tmp/in.mp4", "output" to "/tmp/out.mp4", "startMs" to 0,
                        "endMs" to 1000, "images" to listOf(png), "layers" to listOf(bad),
                    ),
                )
            }
        }
    }

    @Test
    fun fadesFromAndToBlackInStraightLines() {
        // 3 s in and 2 s out over 10 s.
        val fades = Fades(fadeInMs = 3000, fadeOutMs = 2000, lengthMs = 10_000)
        assertEquals(0f, fades.levelAt(0), 0f)
        assertEquals(0.5f, fades.levelAt(1_500_000), 1e-5f)
        assertEquals(1f, fades.levelAt(3_000_000), 0f)
        assertEquals(1f, fades.levelAt(8_000_000), 0f)
        assertEquals(0.5f, fades.levelAt(9_000_000), 1e-5f)
        assertEquals(0f, fades.levelAt(10_000_000), 0f)
        assertEquals(8000L, fades.fadeOutStartMs)
        // The black over the frame, in 64ths: all black at the start, none
        // in the middle, half way at 1.5 s.
        assertEquals(64, fades.darknessAt(0))
        assertEquals(32, fades.darknessAt(1_500_000))
        assertEquals(0, fades.darknessAt(5_000_000))
        // None: never dark; each kept at most half the output.
        assertEquals(1f, Fades().levelAt(0), 0f)
        assertEquals(false, Fades(lengthMs = 1000).any)
        val short = Fades(fadeInMs = 3000, fadeOutMs = 3000, lengthMs = 2000)
        assertEquals(0.5f, short.levelAt(500_000), 1e-5f)
        assertEquals(1f, short.levelAt(1_000_000), 0f)
        assertEquals(1000L, short.fadeOutStartMs)
        // Outside the output, as at its nearest end: black only on a side
        // that fades.
        assertEquals(0f, fades.levelAt(-1_000_000), 0f)
        assertEquals(0f, fades.levelAt(11_000_000), 0f)
        val onlyIn = Fades(fadeInMs = 3000, lengthMs = 10_000)
        assertEquals(0f, onlyIn.levelAt(-1_000_000), 0f)
        assertEquals(1f, onlyIn.levelAt(10_500_000), 0f)
        val onlyOut = Fades(fadeOutMs = 3000, lengthMs = 10_000)
        assertEquals(1f, onlyOut.levelAt(-1_000_000), 0f)
        assertEquals(0f, onlyOut.levelAt(10_500_000), 0f)
    }

    @Test
    fun readsTheChannelsFades() {
        val args = mapOf<String, Any?>("input" to "/tmp/in.mp4", "output" to "/tmp/out.mp4", "startMs" to 500, "endMs" to 10_500)
        val plan = RenderPlan.fromArgs(args + mapOf("fadeInMs" to 3000, "fadeOutMs" to 2000))
        assertEquals(Fades(3000, 2000, 10_000), plan.fades)
        // Left out: none.
        assertEquals(false, RenderPlan.fromArgs(args).fades.any)
    }
}
