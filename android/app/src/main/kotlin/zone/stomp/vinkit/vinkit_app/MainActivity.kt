package zone.stomp.vinkit.vinkit_app

import android.media.AudioAttributes
import android.media.AudioFormat
import android.media.AudioManager
import android.media.AudioTrack
import android.media.ToneGenerator
import io.flutter.embedding.android.FlutterActivity
import io.flutter.embedding.engine.FlutterEngine
import io.flutter.plugin.common.MethodChannel
import java.util.concurrent.Executors
import kotlin.math.PI
import kotlin.math.sin

class MainActivity : FlutterActivity() {
    companion object {
        private const val FEEDBACK_CHANNEL = "zone.stomp.vinkit/scanner_feedback"
        private const val SAMPLE_RATE_HZ = 44100
        private const val BEEP_FREQUENCY_HZ = 2400.0
        private const val BEEP_DURATION_MS = 115
        private const val FADE_IN_MS = 5
        private const val FADE_OUT_MS = 12
    }

    private val audioLock = Any()
    private val audioExecutor = Executors.newSingleThreadExecutor()
    private var beepTrack: AudioTrack? = null
    private var fallbackToneGenerator: ToneGenerator? = null

    override fun configureFlutterEngine(flutterEngine: FlutterEngine) {
        super.configureFlutterEngine(flutterEngine)
        audioExecutor.execute { ensureBeepTrackReady() }

        MethodChannel(
            flutterEngine.dartExecutor.binaryMessenger,
            FEEDBACK_CHANNEL,
        ).setMethodCallHandler { call, result ->
            when (call.method) {
                "playScanBeep" -> {
                    audioExecutor.execute { playScanBeep() }
                    result.success(null)
                }

                else -> result.notImplemented()
            }
        }
    }

    private fun ensureBeepTrackReady(): AudioTrack? {
        synchronized(audioLock) {
            beepTrack?.let { existing ->
                if (existing.state == AudioTrack.STATE_INITIALIZED) {
                    return existing
                }
                existing.release()
                beepTrack = null
            }

            return try {
                val samples = buildBeepSamples()
                val bufferBytes = samples.size * 2
                val attributes = AudioAttributes.Builder()
                    .setUsage(AudioAttributes.USAGE_MEDIA)
                    .setContentType(AudioAttributes.CONTENT_TYPE_SONIFICATION)
                    .build()
                val format = AudioFormat.Builder()
                    .setSampleRate(SAMPLE_RATE_HZ)
                    .setEncoding(AudioFormat.ENCODING_PCM_16BIT)
                    .setChannelMask(AudioFormat.CHANNEL_OUT_MONO)
                    .build()

                val track = AudioTrack.Builder()
                    .setAudioAttributes(attributes)
                    .setAudioFormat(format)
                    .setTransferMode(AudioTrack.MODE_STATIC)
                    .setBufferSizeInBytes(bufferBytes)
                    .build()

                if (track.state != AudioTrack.STATE_INITIALIZED) {
                    track.release()
                    return null
                }

                track.write(samples, 0, samples.size)
                beepTrack = track
                track
            } catch (_: Throwable) {
                null
            }
        }
    }

    private fun playScanBeep() {
        synchronized(audioLock) {
            try {
                val track = ensureBeepTrackReady()
                if (track != null) {
                    if (track.playState == AudioTrack.PLAYSTATE_PLAYING) {
                        track.stop()
                    }
                    track.reloadStaticData()
                    track.play()
                    return
                }
            } catch (_: Throwable) {
                // Fall back to ToneGenerator below.
            }

            try {
                val generator = fallbackToneGenerator
                    ?: ToneGenerator(AudioManager.STREAM_MUSIC, ToneGenerator.MAX_VOLUME).also {
                        fallbackToneGenerator = it
                    }
                generator.startTone(ToneGenerator.TONE_PROP_BEEP, BEEP_DURATION_MS)
            } catch (_: Throwable) {
                // Ignore if device audio hardware is unavailable.
            }
        }
    }

    private fun buildBeepSamples(): ShortArray {
        val sampleCount = (SAMPLE_RATE_HZ * BEEP_DURATION_MS) / 1000
        val fadeInSamples = (SAMPLE_RATE_HZ * FADE_IN_MS) / 1000
        val fadeOutSamples = (SAMPLE_RATE_HZ * FADE_OUT_MS) / 1000
        val amplitude = Short.MAX_VALUE * 0.78
        val samples = ShortArray(sampleCount)

        for (i in 0 until sampleCount) {
            val phase = 2.0 * PI * BEEP_FREQUENCY_HZ * i / SAMPLE_RATE_HZ
            var envelope = 1.0
            if (i < fadeInSamples && fadeInSamples > 0) {
                envelope = i.toDouble() / fadeInSamples
            } else if (i >= sampleCount - fadeOutSamples && fadeOutSamples > 0) {
                envelope = (sampleCount - 1 - i).toDouble() / fadeOutSamples
            }
            samples[i] = (sin(phase) * amplitude * envelope).toInt().toShort()
        }
        return samples
    }

    override fun onDestroy() {
        audioExecutor.shutdownNow()
        synchronized(audioLock) {
            beepTrack?.release()
            beepTrack = null
            fallbackToneGenerator?.release()
            fallbackToneGenerator = null
        }
        super.onDestroy()
    }
}
