package com.nu01.tabcam

import android.Manifest
import android.annotation.SuppressLint
import android.app.Activity
import android.content.Context
import android.content.pm.PackageManager
import android.media.AudioFormat
import android.media.AudioManager
import android.media.AudioRecord
import android.media.AudioTimestamp
import android.media.MediaCodec
import android.media.MediaCodecInfo
import android.media.MediaFormat
import android.media.MediaMuxer
import android.os.Build
import android.os.Handler
import android.os.Looper
import android.os.Process
import android.os.SystemClock
import android.util.Log
import io.flutter.plugin.common.BinaryMessenger
import io.flutter.plugin.common.MethodCall
import io.flutter.plugin.common.MethodChannel
import java.io.File
import java.util.concurrent.ArrayBlockingQueue
import java.util.concurrent.CountDownLatch
import java.util.concurrent.Executors
import java.util.concurrent.LinkedBlockingQueue
import java.util.concurrent.RejectedExecutionException
import kotlin.math.max
import kotlin.math.min

/**
 * Cam's take sound on Android, recorded by the app rather than by the
 * camera: the camera plugin (CameraX) records the camcorder source, with
 * the phone maker's gain control, noise suppression and limiter, and takes
 * no other source or bitrate. Here the microphone is opened with
 * `AudioRecord` as a musician wants it ([TakeSoundMath.sources]: the
 * unprocessed source where the phone has one), read on a thread of its own
 * at the urgent-audio priority, encoded to AAC on another thread, and put
 * into the take, in step with its video, when the take stops ([TakeMux]).
 * See specs/cam.md, "Recording comes first".
 *
 * Channel `tabcam/take_sound`:
 * - `prepare` (Cam opens): asks for the microphone if it isn't allowed yet,
 *   then opens it and tries it (a short start, read and stop), keeping it
 *   open for the takes. Replies `{ok, reason, source, sampleRate,
 *   channels}`; `ok` false (refused, or no source works) means the camera
 *   should record the take's sound itself, as before.
 * - `start` (Rec, before the camera starts): the microphone records; the
 *   camera is kept from opening it too until `videoStarted`.
 * - `videoStarted` (right after the camera's recording started) and
 *   `videoStopping` (right before it's stopped): when, to put the sound in
 *   step.
 * - `stop` (`video`: the camera's take, without sound): the take with its
 *   sound, a new MP4 in the cache, the camera's file deleted. Replies
 *   `{path, leadMs, warning}`, or the error `failed` (the take then has no
 *   sound: the app says so).
 * - `cancel`: stops a take's sound and drops it (the camera didn't start).
 * - `release` (Cam closes): closes the microphone.
 *
 * Threads: calls arrive on the main thread; the microphone is opened,
 * started and stopped, and the sound put into the take, on [control], one
 * at a time. A take's sound has two threads of its own ([Session]).
 */
class TakeSound(private val activity: Activity, messenger: BinaryMessenger) :
    MethodChannel.MethodCallHandler {

    private val context: Context = activity.applicationContext
    private val channel = MethodChannel(messenger, CHANNEL).also {
        it.setMethodCallHandler(this)
    }
    private val main = Handler(Looper.getMainLooper())
    private val control = Executors.newSingleThreadExecutor { Thread(it, "TakeSound control") }

    // The microphone, opened when Cam opens and kept between takes
    // (control thread only).
    private var mic: Mic? = null

    // The take's sound recording now (set on the control thread, read on
    // the main one too).
    @Volatile
    private var session: Session? = null

    // When the camera's recording was about to be stopped (main thread
    // writes, control thread reads).
    @Volatile
    private var videoStopNs = 0L

    // The prepare call waiting for the user's answer (main thread only).
    private var pendingPermission: MethodChannel.Result? = null

    override fun onMethodCall(call: MethodCall, result: MethodChannel.Result) {
        when (call.method) {
            "prepare" -> prepare(result)
            "start" -> onControl(result) {
                start()
                null
            }
            "videoStarted" -> {
                val now = SystemClock.elapsedRealtimeNanos()
                hidesMicrophone = false
                session?.videoStarted(now)
                result.success(null)
            }
            "videoStopping" -> {
                videoStopNs = SystemClock.elapsedRealtimeNanos()
                result.success(null)
            }
            "stop" -> {
                val video = call.argument<String>("video")
                if (video.isNullOrEmpty()) {
                    result.error("failed", "stop needs the camera's video", null)
                } else {
                    onControl(result) { stop(File(video)) }
                }
            }
            "cancel" -> onControl(result) {
                cancel()
                null
            }
            "release" -> onControl(result) {
                release()
                null
            }
            else -> result.notImplemented()
        }
    }

    /** Runs [work] on [control] and replies with what it gives, on the main thread. */
    private fun onControl(result: MethodChannel.Result, work: () -> Any?) {
        try {
            control.execute {
                val reply = try {
                    Result.success(work())
                } catch (e: Exception) {
                    Log.w(TAG, "take sound: ${e.message}", e)
                    Result.failure(e)
                }
                main.post {
                    reply.fold(
                        { result.success(it) },
                        { result.error("failed", it.message ?: it.toString(), null) },
                    )
                }
            }
        } catch (e: RejectedExecutionException) {
            result.error("failed", "Closed", null)
        }
    }

    private fun granted() =
        context.checkSelfPermission(Manifest.permission.RECORD_AUDIO) ==
            PackageManager.PERMISSION_GRANTED

    private fun prepare(result: MethodChannel.Result) {
        if (granted()) return onControl(result) { open() }
        if (pendingPermission != null) {
            result.success(notOk("Already asking for the microphone"))
            return
        }
        pendingPermission = result
        activity.requestPermissions(arrayOf(Manifest.permission.RECORD_AUDIO), REQUEST_CODE)
    }

    /** The activity's onRequestPermissionsResult; true when it was ours. */
    fun onResult(requestCode: Int, grantResults: IntArray): Boolean {
        if (requestCode != REQUEST_CODE) return false
        val result = pendingPermission ?: return true
        pendingPermission = null
        if (grantResults.firstOrNull() == PackageManager.PERMISSION_GRANTED) {
            onControl(result) { open() }
        } else {
            result.success(notOk("The microphone isn't allowed"))
        }
        return true
    }

    private fun notOk(reason: String) = mapOf("ok" to false, "reason" to reason)

    /** Opens the microphone (control thread); never throws. */
    private fun open(): Map<String, Any?> = try {
        val m = mic ?: Mic.open(context).also { mic = it }
        mapOf(
            "ok" to true,
            "source" to TakeSoundMath.sourceName(m.source),
            "sampleRate" to m.format.sampleRate,
            "channels" to m.format.channels,
        )
    } catch (e: Exception) {
        notOk(e.message ?: e.toString())
    }

    private fun start() {
        check(session == null) { "The take's sound is recording already" }
        check(granted()) { "The microphone isn't allowed" }
        val m = mic ?: Mic.open(context).also { mic = it }
        val file = File(context.cacheDir, "take-sound-${System.currentTimeMillis()}.m4a")
        val s = Session(m, file)
        try {
            s.start()
        } catch (e: Exception) {
            // Maybe gone for good (the audio server restarted, say): opened
            // again at the next take.
            m.release()
            mic = null
            file.delete()
            throw e
        }
        videoStopNs = 0
        session = s
        // The camera plugin opens the microphone itself (muted, but with the
        // camcorder source, whose processing would then reach this sound
        // too) unless the microphone looks refused as its recording starts:
        // see MainActivity.checkPermission.
        hidesMicrophone = true
    }

    private fun stop(video: File): Map<String, Any?> {
        hidesMicrophone = false
        val s = session ?: throw IllegalStateException("No take's sound is recording")
        session = null
        var byStop = 0L
        val outcome = try {
            val durationUs = TakeMux.durationUs(video)
            val stopNs = videoStopNs
            if (stopNs > 0 && durationUs > 0) {
                byStop = TakeSoundMath.videoStartFromStopNs(stopNs, durationUs)
            }
            // Rec's time is the one used; Stop's only stands in without it.
            if (s.videoStarted(byStop)) {
                Log.i(TAG, "take sound: the video's start told from Stop")
            }
            s.finish()
        } catch (e: Exception) {
            // Whatever failed, the microphone and the threads stop.
            s.cancel()
            dropMic(s.finish())
            s.file.delete()
            throw e
        }
        dropMic(outcome)
        Log.i(
            TAG,
            "take sound: ${TakeSoundMath.sourceName(s.source)}, ${s.format.sampleRate} Hz, " +
                "${s.format.channels} ch; audio start by ${outcome.audioStartBy}; " +
                "lead ${outcome.leadFrames} frames; video start by Rec - by Stop: " +
                (if (byStop > 0 && outcome.videoStartNs > 0) "${(outcome.videoStartNs - byStop) / 1_000_000} ms" else "?") +
                "; encoder delay ${outcome.encoderDelay}; ${outcome.aacFrames} AAC frames",
        )
        if (outcome.aacFrames == 0L) {
            s.file.delete()
            throw IllegalStateException(outcome.problem ?: "No sound was recorded")
        }
        val out = File(context.cacheDir, "take-${System.currentTimeMillis()}.mp4")
        val report = try {
            TakeMux.mux(video, s.file, out, TakeSoundMath.primingFrames(outcome.encoderDelay))
        } catch (e: Exception) {
            out.delete()
            throw IllegalStateException("The sound couldn't be put into the take: ${e.message}", e)
        } finally {
            s.file.delete()
        }
        if (report.cameraSound) {
            Log.w(TAG, "take sound: the camera recorded sound too (left out)")
        }
        video.delete()
        val warning = when {
            outcome.problem != null -> outcome.problem
            !outcome.heard -> "the microphone gave only silence (is another app using it?)"
            else -> null
        }
        return mapOf(
            "path" to out.path,
            "leadMs" to outcome.leadFrames * 1000.0 / s.format.sampleRate,
            "warning" to warning,
        )
    }

    /**
     * A microphone that failed is opened again at the next take; one a
     * thread may still be reading isn't released under it (left to the
     * collector instead).
     */
    private fun dropMic(outcome: Outcome) {
        if (!outcome.micBroken) return
        if (!outcome.readerStuck) mic?.release()
        mic = null
    }

    private fun cancel() {
        hidesMicrophone = false
        val s = session ?: return
        session = null
        s.cancel()
        val outcome = s.finish()
        s.file.delete()
        dropMic(outcome)
    }

    private fun release() {
        cancel()
        mic?.release()
        mic = null
    }

    fun dispose() {
        channel.setMethodCallHandler(null)
        hidesMicrophone = false
        pendingPermission?.success(notOk("Closed"))
        pendingPermission = null
        try {
            control.execute { release() }
        } catch (_: RejectedExecutionException) {
        }
        control.shutdown()
    }

    /** The microphone, opened and tried. */
    private class Mic(val record: AudioRecord, val source: Int, val format: TakeSoundMath.Format) {
        fun release() = record.release()

        companion object {
            /**
             * The first source and format ([TakeSoundMath]) that opens and
             * gives sound when tried; else throws, saying what was tried.
             */
            @SuppressLint("MissingPermission") // checked by the callers
            fun open(context: Context): Mic {
                val audio = context.getSystemService(AudioManager::class.java)
                val unprocessed = audio?.getProperty(
                    AudioManager.PROPERTY_SUPPORT_AUDIO_SOURCE_UNPROCESSED,
                ) == "true"
                val failures = mutableListOf<String>()
                for (source in TakeSoundMath.sources(unprocessed, Build.VERSION.SDK_INT)) {
                    for (format in TakeSoundMath.formats) {
                        val name = "${TakeSoundMath.sourceName(source)} ${format.sampleRate}/${format.channels}"
                        val mask = if (format.channels == 2) {
                            AudioFormat.CHANNEL_IN_STEREO
                        } else {
                            AudioFormat.CHANNEL_IN_MONO
                        }
                        val min = AudioRecord.getMinBufferSize(
                            format.sampleRate,
                            mask,
                            AudioFormat.ENCODING_PCM_16BIT,
                        )
                        if (min <= 0) {
                            failures += "$name: unsupported"
                            continue
                        }
                        val record = try {
                            AudioRecord(
                                source,
                                format.sampleRate,
                                mask,
                                AudioFormat.ENCODING_PCM_16BIT,
                                TakeSoundMath.bufferBytes(min, format),
                            )
                        } catch (e: Exception) {
                            failures += "$name: ${e.message}"
                            continue
                        }
                        val problem = if (record.state != AudioRecord.STATE_INITIALIZED) {
                            "not initialized"
                        } else {
                            tryOut(record, format)
                        }
                        if (problem == null) {
                            Log.i(TAG, "take sound: $name (unprocessed supported: $unprocessed)")
                            return Mic(record, source, format)
                        }
                        failures += "$name: $problem"
                        record.release()
                    }
                }
                throw IllegalStateException("No microphone could be opened (${failures.joinToString("; ")})")
            }

            /** Starts [record], reads a little and stops it: null when it gave sound. */
            private fun tryOut(record: AudioRecord, format: TakeSoundMath.Format): String? {
                try {
                    record.startRecording()
                    if (record.recordingState != AudioRecord.RECORDSTATE_RECORDING) {
                        return "in use"
                    }
                    val buffer = ByteArray(TakeSoundMath.chunkBytes(format))
                    val until = SystemClock.elapsedRealtime() + 500
                    while (SystemClock.elapsedRealtime() < until) {
                        val n = record.read(buffer, 0, buffer.size, AudioRecord.READ_NON_BLOCKING)
                        if (n > 0) return null
                        if (n < 0) return "read failed ($n)"
                        Thread.sleep(10)
                    }
                    return "no sound came"
                } catch (e: Exception) {
                    return e.message ?: e.toString()
                } finally {
                    try {
                        record.stop()
                    } catch (_: Exception) {
                    }
                }
            }
        }
    }

    /** What a take's sound came to, once [Session.finish]ed. */
    private class Outcome(
        val aacFrames: Long,
        val leadFrames: Long,
        val videoStartNs: Long,
        val audioStartBy: String,
        val encoderDelay: Int,
        val heard: Boolean,
        val problem: String?,
        val micBroken: Boolean,
        val readerStuck: Boolean,
    )

    /** PCM read from the microphone, passed from the reading thread to the encoding one. */
    private class Chunk(val bytes: ByteArray) {
        var length = 0
    }

    /**
     * One take's sound: [mic] read on [reader] (urgent-audio priority,
     * nothing but reading and queueing), encoded to AAC in [file] on
     * [encoder] (normal priority; a backlog just waits in [filled]).
     *
     * The encoder waits for the video's start ([videoStarted]), then drops
     * the sound read before it ([TakeSoundMath.leadFrames]), so the
     * sound's first frame is the video's.
     */
    private class Session(private val mic: Mic, val file: File) {
        val source = mic.source
        val format = mic.format
        private val record = mic.record
        private val frameBytes = format.channels * 2
        private val chunkBytes = TakeSoundMath.chunkBytes(format)

        // Chunks to read into (handed back by the encoder) and read ones.
        private val pool = ArrayBlockingQueue<Chunk>(POOL_MAX)
        private val filled = LinkedBlockingQueue<Chunk>()

        @Volatile private var running = true
        @Volatile private var readError: String? = null
        @Volatile private var timestampStartNs = 0L
        @Volatile private var firstReadStartNs = 0L

        private val videoKnown = CountDownLatch(1)
        @Volatile private var videoStartNs = 0L
        @Volatile private var cancelled = false

        // Written by the encoding thread, read once it's joined.
        @Volatile private var encodeError: String? = null
        @Volatile private var aacFrames = 0L
        @Volatile private var heard = false
        @Volatile private var encoderDelay = 0
        @Volatile private var leadFrames = 0L
        @Volatile private var audioStartBy = "?"

        private lateinit var codec: MediaCodec
        private lateinit var muxer: MediaMuxer
        private var reader: Thread? = null
        private var encoder: Thread? = null

        /** Sets the encoder up and starts the microphone; throws when either fails. */
        fun start() {
            val aac = MediaFormat.createAudioFormat(
                MediaFormat.MIMETYPE_AUDIO_AAC,
                format.sampleRate,
                format.channels,
            ).apply {
                setInteger(MediaFormat.KEY_AAC_PROFILE, MediaCodecInfo.CodecProfileLevel.AACObjectLC)
                setInteger(MediaFormat.KEY_BIT_RATE, TakeSoundMath.bitrate(format.channels))
                setInteger(MediaFormat.KEY_MAX_INPUT_SIZE, chunkBytes)
            }
            codec = MediaCodec.createEncoderByType(MediaFormat.MIMETYPE_AUDIO_AAC)
            try {
                codec.configure(aac, null, null, MediaCodec.CONFIGURE_FLAG_ENCODE)
                codec.start()
                muxer = MediaMuxer(file.path, MediaMuxer.OutputFormat.MUXER_OUTPUT_MPEG_4)
            } catch (e: Exception) {
                codec.release()
                throw e
            }
            try {
                record.startRecording()
                check(record.recordingState == AudioRecord.RECORDSTATE_RECORDING) {
                    "The microphone is in use"
                }
            } catch (e: Exception) {
                try {
                    record.stop()
                } catch (_: Exception) {
                }
                codec.release()
                muxer.release()
                throw e
            }
            repeat(POOL_START) { pool.offer(Chunk(ByteArray(chunkBytes))) }
            reader = Thread(::read, "TakeSound read").also { it.start() }
            encoder = Thread(::encode, "TakeSound encode").also { it.start() }
        }

        /**
         * The video started at [ns] (0: unknown). Only the first time
         * counts: false when it was known already.
         */
        @Synchronized
        fun videoStarted(ns: Long): Boolean {
            if (videoKnown.count == 0L) return false
            videoStartNs = ns
            videoKnown.countDown()
            return true
        }

        /** No take: what's recorded is dropped. */
        fun cancel() {
            cancelled = true
            videoStarted(0)
        }

        /** Stops the microphone and finishes the sound's file (control thread). */
        fun finish(): Outcome {
            running = false
            try {
                record.stop()
            } catch (_: Exception) {
            }
            val readerThread = reader
            readerThread?.join(READER_JOIN_MS)
            val readerStuck = readerThread?.isAlive == true
            // Should the reader be stuck, the encoder still gets its end.
            if (readerStuck) filled.add(END)
            encoder?.join(ENCODER_JOIN_MS)
            val encoderStuck = encoder?.isAlive == true
            val problem = when {
                encoderStuck -> "the sound took too long to finish"
                readError != null -> "the sound stopped early: $readError"
                encodeError != null -> "the sound couldn't all be encoded: $encodeError"
                else -> null
            }
            return Outcome(
                aacFrames = if (encoderStuck) 0 else aacFrames,
                leadFrames = leadFrames,
                videoStartNs = videoStartNs,
                audioStartBy = audioStartBy,
                encoderDelay = encoderDelay,
                heard = heard,
                problem = problem,
                micBroken = readerStuck || readError != null,
                readerStuck = readerStuck,
            )
        }

        private fun read() {
            Process.setThreadPriority(Process.THREAD_PRIORITY_URGENT_AUDIO)
            val timestamp = AudioTimestamp()
            var reads = 0
            try {
                while (running) {
                    val chunk = pool.poll() ?: Chunk(ByteArray(chunkBytes))
                    val n = record.read(chunk.bytes, 0, chunkBytes)
                    if (n <= 0) {
                        pool.offer(chunk)
                        if (n < 0) {
                            readError = "the microphone gave the error $n"
                            break
                        }
                        continue
                    }
                    chunk.length = n
                    filled.add(chunk)
                    // When the first frame was captured: the system's
                    // timestamps over the first second (the latest kept),
                    // else when the first read came back.
                    if (reads == 0) {
                        firstReadStartNs = TakeSoundMath.firstFrameFromReadNs(
                            SystemClock.elapsedRealtimeNanos(),
                            (n / frameBytes).toLong(),
                            format.sampleRate,
                        )
                    }
                    if (reads < TIMESTAMP_READS &&
                        record.getTimestamp(timestamp, AudioTimestamp.TIMEBASE_BOOTTIME) ==
                        AudioRecord.SUCCESS &&
                        timestamp.nanoTime > 0 &&
                        timestamp.framePosition >= 0
                    ) {
                        timestampStartNs = TakeSoundMath.firstFrameNs(
                            timestamp.nanoTime,
                            timestamp.framePosition,
                            format.sampleRate,
                        )
                    }
                    reads++
                }
            } catch (e: Exception) {
                readError = e.message ?: e.toString()
            } finally {
                filled.add(END)
            }
        }

        private fun encode() {
            val info = MediaCodec.BufferInfo()
            var track = -1
            var muxing = false
            var fedFrames = 0L

            fun drain(untilEnd: Boolean) {
                var waits = 0
                while (true) {
                    val index = codec.dequeueOutputBuffer(info, if (untilEnd) WAIT_US else 0)
                    when {
                        index == MediaCodec.INFO_TRY_AGAIN_LATER -> {
                            if (!untilEnd) return
                            check(++waits < MAX_WAITS) { "the encoder stalled" }
                        }
                        index == MediaCodec.INFO_OUTPUT_FORMAT_CHANGED -> {
                            val out = codec.outputFormat
                            if (out.containsKey(ENCODER_DELAY)) encoderDelay = out.getInteger(ENCODER_DELAY)
                            track = muxer.addTrack(out)
                            muxer.start()
                            muxing = true
                        }
                        index >= 0 -> {
                            val buffer = codec.getOutputBuffer(index)
                            if (info.flags and MediaCodec.BUFFER_FLAG_CODEC_CONFIG != 0) info.size = 0
                            if (info.size > 0 && muxing && buffer != null) {
                                buffer.position(info.offset)
                                buffer.limit(info.offset + info.size)
                                muxer.writeSampleData(track, buffer, info)
                                aacFrames++
                            }
                            codec.releaseOutputBuffer(index, false)
                            if (info.flags and MediaCodec.BUFFER_FLAG_END_OF_STREAM != 0) return
                        }
                    }
                }
            }

            fun feed(bytes: ByteArray, offset: Int, length: Int) {
                var at = offset
                var left = length
                var waits = 0
                while (left > 0) {
                    val index = codec.dequeueInputBuffer(WAIT_US)
                    if (index < 0) {
                        check(++waits < MAX_WAITS) { "the encoder stalled" }
                        drain(false)
                        continue
                    }
                    waits = 0
                    val buffer = codec.getInputBuffer(index)!!
                    buffer.clear()
                    val n = min(left, buffer.capacity() / frameBytes * frameBytes)
                    check(n > 0) { "the encoder's buffers are too small" }
                    buffer.put(bytes, at, n)
                    codec.queueInputBuffer(
                        index,
                        0,
                        n,
                        TakeSoundMath.framesToUs(fedFrames, format.sampleRate),
                        0,
                    )
                    fedFrames += n / frameBytes
                    at += n
                    left -= n
                    drain(false)
                }
            }

            try {
                videoKnown.await()
                if (cancelled) {
                    while (filled.take() !== END) {
                        // Dropped.
                    }
                    return
                }
                val byTimestamp = timestampStartNs
                val audioStartNs = if (byTimestamp != 0L) byTimestamp else firstReadStartNs
                audioStartBy = if (byTimestamp != 0L) "timestamp" else "first read"
                val videoNs = videoStartNs
                leadFrames = if (videoNs > 0 && audioStartNs != 0L) {
                    TakeSoundMath.leadFrames(audioStartNs, videoNs, format.sampleRate)
                } else {
                    0L
                }
                var skipBytes = max(leadFrames, 0L) * frameBytes
                if (leadFrames < 0) {
                    val silence = ByteArray(chunkBytes)
                    var left = -leadFrames * frameBytes
                    while (left > 0) {
                        val n = min(left, silence.size.toLong()).toInt()
                        feed(silence, 0, n)
                        left -= n
                    }
                }
                while (true) {
                    val chunk = filled.take()
                    if (chunk === END) break
                    var offset = 0
                    var length = chunk.length
                    if (skipBytes > 0) {
                        val skip = min(skipBytes, length.toLong()).toInt()
                        offset += skip
                        length -= skip
                        skipBytes -= skip
                    }
                    if (!heard) {
                        for (i in offset until offset + length) {
                            if (chunk.bytes[i].toInt() != 0) {
                                heard = true
                                break
                            }
                        }
                    }
                    if (length > 0 && encodeError == null) {
                        try {
                            feed(chunk.bytes, offset, length)
                        } catch (e: Exception) {
                            // The rest is still taken off the queue (and
                            // dropped), so it doesn't grow.
                            encodeError = e.message ?: e.toString()
                        }
                    }
                    chunk.length = 0
                    pool.offer(chunk)
                }
                if (encodeError == null) {
                    var waits = 0
                    var index = codec.dequeueInputBuffer(WAIT_US)
                    while (index < 0) {
                        check(++waits < MAX_WAITS) { "the encoder stalled" }
                        drain(false)
                        index = codec.dequeueInputBuffer(WAIT_US)
                    }
                    codec.queueInputBuffer(
                        index,
                        0,
                        0,
                        TakeSoundMath.framesToUs(fedFrames, format.sampleRate),
                        MediaCodec.BUFFER_FLAG_END_OF_STREAM,
                    )
                    drain(true)
                }
            } catch (e: Exception) {
                if (encodeError == null) encodeError = e.message ?: e.toString()
            } finally {
                try {
                    codec.stop()
                } catch (_: Exception) {
                }
                codec.release()
                if (muxing) {
                    try {
                        muxer.stop()
                    } catch (e: Exception) {
                        // Nothing written, or the file is broken: no sound.
                        aacFrames = 0
                        if (encodeError == null) encodeError = e.message ?: e.toString()
                    }
                }
                try {
                    muxer.release()
                } catch (_: Exception) {
                }
                if (!muxing) aacFrames = 0
            }
        }

        companion object {
            private val END = Chunk(ByteArray(0))

            // 1 s of chunks to start with; up to 10 s kept for reuse.
            const val POOL_START = 50
            const val POOL_MAX = 500

            const val TIMESTAMP_READS = 50
            const val WAIT_US = 10_000L
            const val MAX_WAITS = 500
            const val READER_JOIN_MS = 2_000L
            const val ENCODER_JOIN_MS = 30_000L

            // How MediaFormat names an AAC encoder's priming delay, in
            // samples, when it says.
            const val ENCODER_DELAY = "encoder-delay"
        }
    }

    companion object {
        const val CHANNEL = "tabcam/take_sound"
        const val REQUEST_CODE = 2013
        private const val TAG = "TabCam"

        /**
         * While a take's camera recording starts with the sound recorded
         * here: the microphone permission reads as refused to the camera
         * plugin ([MainActivity.checkPermission]), so it records no sound
         * of its own (it would open the microphone with the camcorder
         * source, muted, and that source's processing would reach this
         * sound as well).
         */
        @Volatile
        var hidesMicrophone = false
    }
}
