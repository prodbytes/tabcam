package com.nu01.tabcam

import android.content.Context
import android.media.AudioAttributes
import android.media.MediaPlayer
import io.flutter.plugin.common.BinaryMessenger
import io.flutter.plugin.common.MethodCall
import io.flutter.plugin.common.MethodChannel
import java.io.File

/**
 * Short sounds the app makes (Rescan's ding, see `lib/sound/ding.dart`).
 *
 * Channel `tabcam/sound`, method `ding`, argument: the sound's WAV file, as
 * bytes (the app makes it). It's written to the app's cache and played as a
 * notification sound, so it follows the notification volume and stays quiet
 * when the phone is on silent or vibrate (or Do Not Disturb). It takes no
 * audio focus: a video playing in the app, or music in another, goes on.
 * Replies once the sound has started loading, or with the error `failed`.
 */
class Sound(private val context: Context, messenger: BinaryMessenger) :
    MethodChannel.MethodCallHandler {

    private val channel = MethodChannel(messenger, CHANNEL).also {
        it.setMethodCallHandler(this)
    }

    // The sound playing, held until it ends (main thread only).
    private var player: MediaPlayer? = null

    override fun onMethodCall(call: MethodCall, result: MethodChannel.Result) {
        if (call.method != "ding") {
            result.notImplemented()
            return
        }
        val wav = call.arguments as? ByteArray
        if (wav == null) {
            result.error("failed", "ding takes the WAV's bytes", null)
            return
        }
        try {
            play(wav)
            result.success(null)
        } catch (e: Exception) {
            result.error("failed", e.message, null)
        }
    }

    private fun play(wav: ByteArray) {
        stop()
        val file = File(context.cacheDir, "ding.wav")
        file.writeBytes(wav)
        val sound = MediaPlayer()
        player = sound
        try {
            sound.setAudioAttributes(
                AudioAttributes.Builder()
                    .setUsage(AudioAttributes.USAGE_NOTIFICATION_EVENT)
                    .setContentType(AudioAttributes.CONTENT_TYPE_SONIFICATION)
                    .build()
            )
            sound.setDataSource(file.path)
            sound.setOnPreparedListener { it.start() }
            sound.setOnCompletionListener { done(it) }
            sound.setOnErrorListener { p, _, _ ->
                done(p)
                true
            }
            sound.prepareAsync()
        } catch (e: Exception) {
            done(sound)
            throw e
        }
    }

    private fun done(sound: MediaPlayer) {
        sound.release()
        if (player === sound) player = null
    }

    private fun stop() {
        player?.release()
        player = null
    }

    fun dispose() {
        channel.setMethodCallHandler(null)
        stop()
    }

    companion object {
        const val CHANNEL = "tabcam/sound"
    }
}
