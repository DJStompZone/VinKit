package zone.stomp.vinkit

import android.graphics.Bitmap
import android.graphics.BitmapFactory
import android.graphics.Matrix
import android.media.AudioAttributes
import android.media.AudioFormat
import android.media.AudioManager
import android.media.AudioTrack
import android.media.ExifInterface
import android.media.ToneGenerator
import android.os.Build
import android.os.Handler
import android.os.Looper
import io.flutter.embedding.android.FlutterActivity
import io.flutter.embedding.engine.FlutterEngine
import io.flutter.plugin.common.MethodChannel
import java.io.File
import java.io.FileOutputStream
import java.util.concurrent.Executors
import kotlin.math.abs
import kotlin.math.cos
import kotlin.math.max
import kotlin.math.pow
import kotlin.math.roundToInt
import kotlin.math.sin

class MainActivity : FlutterActivity() {
    companion object {
        private const val FEEDBACK_CHANNEL = "zone.stomp.vinkit/scanner_feedback"
        private const val OCR_PREP_CHANNEL = "zone.stomp.vinkit/ocr_image_prep"
        private const val SAMPLE_RATE_HZ = 44100
        private const val BEEP_FREQUENCY_HZ = 3400.0
        private const val BEEP_DURATION_MS = 260
        private const val FADE_IN_MS = 5
        private const val FADE_OUT_MS = 35
        private const val BEEP_AMPLITUDE = 0.38
        private const val DEFAULT_OCR_MAX_DIMENSION = 1600
        private const val DECODE_MAX_DIMENSION = 2400
    }

    private val audioLock = Any()
    private val audioExecutor = Executors.newSingleThreadExecutor()
    private val ocrPrepExecutor = Executors.newSingleThreadExecutor()
    private val mainHandler = Handler(Looper.getMainLooper())
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
                    // Play immediately on the preloaded static track to avoid
                    // executor hop latency; only fall back off-thread if cold.
                    if (playPreparedBeepTrackNow()) {
                        result.success(null)
                    } else {
                        audioExecutor.execute {
                            playScanBeep()
                            mainHandler.post { result.success(null) }
                        }
                    }
                }

                else -> result.notImplemented()
            }
        }

        MethodChannel(
            flutterEngine.dartExecutor.binaryMessenger,
            OCR_PREP_CHANNEL,
        ).setMethodCallHandler { call, result ->
            when (call.method) {
                "prepareOcrImage" -> {
                    val imagePath = call.argument<String>("imagePath")
                    if (imagePath.isNullOrBlank()) {
                        result.success(null)
                        return@setMethodCallHandler
                    }
                    val gamma = (call.argument<Double>("gamma") ?: 1.0).coerceIn(0.35, 2.5)
                    val hdr = call.argument<Boolean>("hdr") ?: false
                    val cropLeft = call.argument<Double>("cropLeft")
                    val cropTop = call.argument<Double>("cropTop")
                    val cropRight = call.argument<Double>("cropRight")
                    val cropBottom = call.argument<Double>("cropBottom")
                    val maxDimension =
                        (call.argument<Int>("maxDimension") ?: DEFAULT_OCR_MAX_DIMENSION)
                            .coerceIn(480, 2400)

                    ocrPrepExecutor.execute {
                        val preparedPath = prepareOcrImage(
                            imagePath = imagePath,
                            gamma = gamma,
                            hdr = hdr,
                            cropLeft = cropLeft,
                            cropTop = cropTop,
                            cropRight = cropRight,
                            cropBottom = cropBottom,
                            maxDimension = maxDimension,
                        )
                        mainHandler.post { result.success(preparedPath) }
                    }
                }

                "prepareStreamFrame" -> {
                    val lumaBytes = call.argument<ByteArray>("lumaBytes")
                    val width = call.argument<Int>("width") ?: 0
                    val height = call.argument<Int>("height") ?: 0
                    val rowStride = call.argument<Int>("rowStride") ?: width
                    val pixelStride = (call.argument<Int>("pixelStride") ?: 1).coerceAtLeast(1)
                    val rotationDegrees = call.argument<Int>("rotationDegrees") ?: 0
                    if (lumaBytes == null || width <= 0 || height <= 0) {
                        result.success(null)
                        return@setMethodCallHandler
                    }
                    val gamma = (call.argument<Double>("gamma") ?: 1.0).coerceIn(0.35, 2.5)
                    val hdr = call.argument<Boolean>("hdr") ?: false
                    val cropLeft = call.argument<Double>("cropLeft")
                    val cropTop = call.argument<Double>("cropTop")
                    val cropRight = call.argument<Double>("cropRight")
                    val cropBottom = call.argument<Double>("cropBottom")
                    val maxDimension =
                        (call.argument<Int>("maxDimension") ?: 1280).coerceIn(480, 1800)

                    ocrPrepExecutor.execute {
                        val preparedPath = prepareStreamLumaFrame(
                            lumaBytes = lumaBytes,
                            width = width,
                            height = height,
                            rowStride = rowStride,
                            pixelStride = pixelStride,
                            rotationDegrees = rotationDegrees,
                            gamma = gamma,
                            hdr = hdr,
                            cropLeft = cropLeft,
                            cropTop = cropTop,
                            cropRight = cropRight,
                            cropBottom = cropBottom,
                            maxDimension = maxDimension,
                        )
                        mainHandler.post { result.success(preparedPath) }
                    }
                }

                "clearTempCache" -> {
                    ocrPrepExecutor.execute {
                        val deletedCount = clearTempImageCache()
                        mainHandler.post { result.success(deletedCount) }
                    }
                }

                "clearOcrModelCache" -> {
                    ocrPrepExecutor.execute {
                        val cleared = clearOcrModelCache()
                        mainHandler.post { result.success(cleared) }
                    }
                }

                else -> result.notImplemented()
            }
        }
    }

    private fun clearTempImageCache(): Int {
        var deletedCount = 0
        runCatching {
            val prepDir = File(cacheDir, "ocr_prep")
            if (prepDir.exists()) {
                prepDir.listFiles()?.forEach { file ->
                    if (file.isFile && file.delete()) {
                        deletedCount++
                    }
                }
            }
            cacheDir.listFiles()?.forEach { file ->
                if (file.isFile) {
                    val lower = file.name.lowercase()
                    if (lower.endsWith(".jpg") || lower.endsWith(".jpeg") || lower.endsWith(".png")) {
                        if (file.delete()) {
                            deletedCount++
                        }
                    }
                }
            }
        }
        return deletedCount
    }

    private fun clearOcrModelCache(): Boolean {
        return runCatching {
            val modelDir = File(filesDir, "assets/mobile_ocr")
            if (!modelDir.exists()) {
                true
            } else {
                modelDir.deleteRecursively()
            }
        }.getOrDefault(false)
    }

    private fun prepareOcrImage(
        imagePath: String,
        gamma: Double,
        hdr: Boolean,
        cropLeft: Double?,
        cropTop: Double?,
        cropRight: Double?,
        cropBottom: Double?,
        maxDimension: Int,
    ): String? {
        var decoded: Bitmap? = null
        var oriented: Bitmap? = null
        var cropped: Bitmap? = null
        var scaled: Bitmap? = null
        var working: Bitmap? = null

        return try {
            val sourceFile = File(imagePath)
            if (!sourceFile.exists() || sourceFile.length() <= 0L) {
                return null
            }

            val bounds = BitmapFactory.Options().apply { inJustDecodeBounds = true }
            BitmapFactory.decodeFile(imagePath, bounds)
            if (bounds.outWidth <= 0 || bounds.outHeight <= 0) {
                return null
            }

            var inSampleSize = 1
            val longestSide = max(bounds.outWidth, bounds.outHeight)
            while (longestSide / (inSampleSize * 2) >= DECODE_MAX_DIMENSION) {
                inSampleSize *= 2
            }

            val decodeOptions = BitmapFactory.Options().apply {
                this.inSampleSize = inSampleSize
                inPreferredConfig = Bitmap.Config.ARGB_8888
            }
            decoded = BitmapFactory.decodeFile(imagePath, decodeOptions) ?: return null

            val orientation = runCatching {
                ExifInterface(imagePath).getAttributeInt(
                    ExifInterface.TAG_ORIENTATION,
                    ExifInterface.ORIENTATION_NORMAL,
                )
            }.getOrDefault(ExifInterface.ORIENTATION_NORMAL)

            oriented = applyExifOrientation(decoded, orientation)
            if (oriented !== decoded && !decoded.isRecycled) {
                decoded.recycle()
                decoded = null
            }

            val baseBitmap = oriented ?: return null

            cropped = if (
                cropLeft != null &&
                cropTop != null &&
                cropRight != null &&
                cropBottom != null
            ) {
                val left = (cropLeft.coerceIn(0.0, 0.95) * baseBitmap.width).roundToInt()
                val top = (cropTop.coerceIn(0.0, 0.95) * baseBitmap.height).roundToInt()
                val right = (cropRight.coerceIn(0.05, 1.0) * baseBitmap.width).roundToInt()
                val bottom = (cropBottom.coerceIn(0.05, 1.0) * baseBitmap.height).roundToInt()
                val width = (right - left).coerceAtLeast(1)
                val height = (bottom - top).coerceAtLeast(1)
                if (
                    width >= 64 &&
                    height >= 32 &&
                    left + width <= baseBitmap.width &&
                    top + height <= baseBitmap.height &&
                    (width < baseBitmap.width || height < baseBitmap.height)
                ) {
                    Bitmap.createBitmap(baseBitmap, left, top, width, height)
                } else {
                    baseBitmap
                }
            } else {
                baseBitmap
            }

            if (cropped !== oriented && oriented != null && !oriented.isRecycled) {
                oriented.recycle()
                oriented = null
            }

            val cropBitmap = cropped ?: return null
            val cropLongest = max(cropBitmap.width, cropBitmap.height)
            scaled = if (cropLongest > maxDimension) {
                val ratio = maxDimension.toFloat() / cropLongest.toFloat()
                val targetW = max(32, (cropBitmap.width * ratio).roundToInt())
                val targetH = max(32, (cropBitmap.height * ratio).roundToInt())
                Bitmap.createScaledBitmap(cropBitmap, targetW, targetH, true)
            } else {
                cropBitmap
            }

            if (scaled !== cropped && cropped != null && !cropped.isRecycled) {
                cropped.recycle()
                cropped = null
            }

            val targetBitmap = scaled ?: return null
            working = if (hdr || abs(gamma - 1.0) > 0.02) {
                applyToneAdjustments(targetBitmap, gamma = gamma, hdr = hdr)
            } else {
                targetBitmap
            }

            val outputDir = File(cacheDir, "ocr_prep").apply {
                if (!exists()) {
                    mkdirs()
                }
            }
            val outputFile = File(outputDir, "vin_ocr_${System.nanoTime()}.jpg")
            FileOutputStream(outputFile).use { stream ->
                val ok = working.compress(Bitmap.CompressFormat.JPEG, 94, stream)
                if (!ok) {
                    outputFile.delete()
                    return null
                }
            }
            outputFile.absolutePath
        } catch (t: Throwable) {
            android.util.Log.e("OcrImagePrep", "Failed preparing OCR image", t)
            null
        } finally {
            listOf(working, scaled, cropped, oriented, decoded)
                .distinct()
                .forEach { bmp ->
                    if (bmp != null && !bmp.isRecycled) {
                        bmp.recycle()
                    }
                }
        }
    }

    private fun prepareStreamLumaFrame(
        lumaBytes: ByteArray,
        width: Int,
        height: Int,
        rowStride: Int,
        pixelStride: Int,
        rotationDegrees: Int,
        gamma: Double,
        hdr: Boolean,
        cropLeft: Double?,
        cropTop: Double?,
        cropRight: Double?,
        cropBottom: Double?,
        maxDimension: Int,
    ): String? {
        var roiBitmap: Bitmap? = null
        var scaledBitmap: Bitmap? = null
        return try {
            val normalizedRot = ((rotationDegrees % 360) + 360) % 360
            val rotW = if (normalizedRot == 90 || normalizedRot == 270) height else width
            val rotH = if (normalizedRot == 90 || normalizedRot == 270) width else height

            val left = ((cropLeft ?: 0.0).coerceIn(0.0, 0.95) * rotW).roundToInt()
            val top = ((cropTop ?: 0.0).coerceIn(0.0, 0.95) * rotH).roundToInt()
            val right = ((cropRight ?: 1.0).coerceIn(0.05, 1.0) * rotW).roundToInt()
            val bottom = ((cropBottom ?: 1.0).coerceIn(0.05, 1.0) * rotH).roundToInt()
            val cropW = (right - left).coerceAtLeast(1)
            val cropH = (bottom - top).coerceAtLeast(1)
            if (cropW < 32 || cropH < 24 || left + cropW > rotW || top + cropH > rotH) {
                return null
            }

            val luma = IntArray(cropW * cropH)
            val bytesLen = lumaBytes.size
            for (y in 0 until cropH) {
                val uy = top + y
                val rowOffset = y * cropW
                for (x in 0 until cropW) {
                    val ux = left + x
                    val sx: Int
                    val sy: Int
                    when (normalizedRot) {
                        90 -> {
                            sx = uy
                            sy = height - 1 - ux
                        }
                        180 -> {
                            sx = width - 1 - ux
                            sy = height - 1 - uy
                        }
                        270 -> {
                            sx = width - 1 - uy
                            sy = ux
                        }
                        else -> {
                            sx = ux
                            sy = uy
                        }
                    }
                    val idx = sy * rowStride + sx * pixelStride
                    luma[rowOffset + x] =
                        if (idx in 0 until bytesLen) lumaBytes[idx].toInt() and 0xFF else 0
                }
            }

            if (hdr) {
                applyHdrToLumaInPlace(luma, cropW, cropH)
            }
            if (abs(gamma - 1.0) > 0.02) {
                val lut = buildGammaLut(gamma)
                for (i in luma.indices) {
                    luma[i] = lut[luma[i]]
                }
            }

            val pixels = IntArray(cropW * cropH) { i ->
                val v = luma[i]
                -0x1000000 or (v shl 16) or (v shl 8) or v
            }
            roiBitmap = Bitmap.createBitmap(pixels, cropW, cropH, Bitmap.Config.ARGB_8888)
            val longest = max(cropW, cropH)
            scaledBitmap = if (longest > maxDimension) {
                val ratio = maxDimension.toFloat() / longest.toFloat()
                val targetW = max(32, (cropW * ratio).roundToInt())
                val targetH = max(24, (cropH * ratio).roundToInt())
                Bitmap.createScaledBitmap(roiBitmap, targetW, targetH, true)
            } else {
                roiBitmap
            }

            val outputDir = File(cacheDir, "ocr_prep").apply {
                if (!exists()) {
                    mkdirs()
                }
            }
            val outputFile = File(outputDir, "vin_live_${System.nanoTime()}.jpg")
            FileOutputStream(outputFile).use { stream ->
                val ok = scaledBitmap.compress(Bitmap.CompressFormat.JPEG, 90, stream)
                if (!ok) {
                    outputFile.delete()
                    return null
                }
            }
            outputFile.absolutePath
        } catch (t: Throwable) {
            android.util.Log.e("OcrImagePrep", "Failed preparing live stream frame", t)
            null
        } finally {
            if (scaledBitmap != null && scaledBitmap !== roiBitmap && !scaledBitmap.isRecycled) {
                scaledBitmap.recycle()
            }
            if (roiBitmap != null && !roiBitmap.isRecycled) {
                roiBitmap.recycle()
            }
        }
    }

    private fun applyExifOrientation(source: Bitmap, orientation: Int): Bitmap {
        val matrix = Matrix()
        var transformed = true
        when (orientation) {
            ExifInterface.ORIENTATION_ROTATE_90 -> matrix.postRotate(90f)
            ExifInterface.ORIENTATION_ROTATE_180 -> matrix.postRotate(180f)
            ExifInterface.ORIENTATION_ROTATE_270 -> matrix.postRotate(270f)
            ExifInterface.ORIENTATION_FLIP_HORIZONTAL -> matrix.preScale(-1f, 1f)
            ExifInterface.ORIENTATION_FLIP_VERTICAL -> matrix.preScale(1f, -1f)
            ExifInterface.ORIENTATION_TRANSPOSE -> {
                matrix.postRotate(90f)
                matrix.preScale(-1f, 1f)
            }

            ExifInterface.ORIENTATION_TRANSVERSE -> {
                matrix.postRotate(270f)
                matrix.preScale(-1f, 1f)
            }

            else -> transformed = false
        }
        if (!transformed || matrix.isIdentity) {
            return source
        }
        return Bitmap.createBitmap(source, 0, 0, source.width, source.height, matrix, true)
    }

    private fun buildGammaLut(gamma: Double): IntArray {
        val invGamma = 1.0 / gamma
        return IntArray(256) { value ->
            ((value / 255.0).pow(invGamma) * 255.0).roundToInt().coerceIn(0, 255)
        }
    }

    private fun buildHdrStretchLut(histogram: IntArray, totalPixels: Int): IntArray {
        val lowTarget = (totalPixels * 0.02).toInt()
        val highTarget = (totalPixels * 0.98).toInt()
        var cumulative = 0
        var pLow = 0
        var pHigh = 255
        var foundLow = false
        for (bin in 0..255) {
            cumulative += histogram[bin]
            if (!foundLow && cumulative >= lowTarget) {
                pLow = bin
                foundLow = true
            }
            if (cumulative >= highTarget) {
                pHigh = bin
                break
            }
        }

        // Prevent amplifying flat sensor noise on blank frames.
        if (pHigh - pLow < 24) {
            val mid = (pLow + pHigh) / 2
            pLow = (mid - 12).coerceAtLeast(0)
            pHigh = (mid + 12).coerceAtMost(255)
        }
        val spread = max(1, pHigh - pLow).toDouble()

        return IntArray(256) { v ->
            val t = ((v - pLow) / spread).coerceIn(0.0, 1.0)
            // Monotonic shadow-lift & highlight-recovery tone curve.
            val lifted = (t + 0.46 * (1.0 - t) * (1.0 - t) * t).coerceIn(0.0, 1.0)
            (lifted * 255.0).roundToInt().coerceIn(0, 255)
        }
    }

    private fun applyHdrToLumaInPlace(luma: IntArray, width: Int, height: Int) {
        val histogram = IntArray(256)
        for (v in luma) {
            histogram[v]++
        }
        val hdrLut = buildHdrStretchLut(histogram, luma.size)
        for (i in luma.indices) {
            luma[i] = hdrLut[luma[i]]
        }

        // Subtle 3x3 unsharp mask to crisp up barcode edges & etched VIN characters.
        if (width < 3 || height < 3) {
            return
        }
        val copy = luma.copyOf()
        for (y in 1 until height - 1) {
            val row = y * width
            val prevRow = row - width
            val nextRow = row + width
            for (x in 1 until width - 1) {
                val sum = copy[prevRow + x - 1] + copy[prevRow + x] + copy[prevRow + x + 1] +
                    copy[row + x - 1] + copy[row + x] + copy[row + x + 1] +
                    copy[nextRow + x - 1] + copy[nextRow + x] + copy[nextRow + x + 1]
                val avg = sum / 9
                val center = copy[row + x]
                val sharpened = center + ((center - avg) * 42) / 100
                luma[row + x] = sharpened.coerceIn(0, 255)
            }
        }
    }

    private fun applyToneAdjustments(source: Bitmap, gamma: Double, hdr: Boolean): Bitmap {
        val width = source.width
        val height = source.height
        val mutable = if (source.isMutable && source.config == Bitmap.Config.ARGB_8888) {
            source
        } else {
            source.copy(Bitmap.Config.ARGB_8888, true)
        }
        val pixels = IntArray(width * height)
        mutable.getPixels(pixels, 0, width, 0, 0, width, height)

        if (hdr) {
            val luma = IntArray(pixels.size)
            for (i in pixels.indices) {
                val px = pixels[i]
                val r = (px shr 16) and 0xFF
                val g = (px shr 8) and 0xFF
                val b = px and 0xFF
                luma[i] = (77 * r + 150 * g + 29 * b) shr 8
            }
            val origLuma = luma.copyOf()
            applyHdrToLumaInPlace(luma, width, height)

            for (i in pixels.indices) {
                val px = pixels[i]
                val a = px and -0x1000000
                val oldY = origLuma[i]
                val newY = luma[i]
                if (oldY <= 2) {
                    pixels[i] = a or (newY shl 16) or (newY shl 8) or newY
                } else {
                    val scale = newY.toFloat() / oldY.toFloat()
                    val r = (((px shr 16) and 0xFF) * scale).roundToInt().coerceIn(0, 255)
                    val g = (((px shr 8) and 0xFF) * scale).roundToInt().coerceIn(0, 255)
                    val b = ((px and 0xFF) * scale).roundToInt().coerceIn(0, 255)
                    pixels[i] = a or (r shl 16) or (g shl 8) or b
                }
            }
        }

        if (abs(gamma - 1.0) > 0.02) {
            val lut = buildGammaLut(gamma)
            for (i in pixels.indices) {
                val px = pixels[i]
                val a = px and -0x1000000
                val r = lut[(px shr 16) and 0xFF]
                val g = lut[(px shr 8) and 0xFF]
                val b = lut[px and 0xFF]
                pixels[i] = a or (r shl 16) or (g shl 8) or b
            }
        }

        mutable.setPixels(pixels, 0, width, 0, 0, width, height)
        return mutable
    }

    private fun createStaticBeepTrack(
        samples: ShortArray,
        lowLatency: Boolean,
    ): AudioTrack? {
        val bufferBytes = samples.size * 2
        val attributes = AudioAttributes.Builder()
            .setUsage(AudioAttributes.USAGE_ASSISTANCE_SONIFICATION)
            .setContentType(AudioAttributes.CONTENT_TYPE_SONIFICATION)
            .build()
        val format = AudioFormat.Builder()
            .setSampleRate(SAMPLE_RATE_HZ)
            .setEncoding(AudioFormat.ENCODING_PCM_16BIT)
            .setChannelMask(AudioFormat.CHANNEL_OUT_MONO)
            .build()

        val builder = AudioTrack.Builder()
            .setAudioAttributes(attributes)
            .setAudioFormat(format)
            .setTransferMode(AudioTrack.MODE_STATIC)
            .setBufferSizeInBytes(bufferBytes)

        if (lowLatency && Build.VERSION.SDK_INT >= Build.VERSION_CODES.O) {
            builder.setPerformanceMode(AudioTrack.PERFORMANCE_MODE_LOW_LATENCY)
        }

        val track = builder.build()
        // MODE_STATIC tracks start in STATE_NO_STATIC_DATA (2) and
        // transition to STATE_INITIALIZED (1) only after write().
        if (track.state == AudioTrack.STATE_UNINITIALIZED) {
            track.release()
            return null
        }

        val written = track.write(samples, 0, samples.size)
        if (written < samples.size || track.state != AudioTrack.STATE_INITIALIZED) {
            track.release()
            return null
        }
        return track
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
                val track = runCatching {
                    createStaticBeepTrack(samples, lowLatency = true)
                }.getOrNull() ?: createStaticBeepTrack(samples, lowLatency = false)

                if (track == null) {
                    android.util.Log.e(
                        "ScannerFeedback",
                        "AudioTrack failed to initialize in both low-latency and default modes",
                    )
                    return null
                }

                beepTrack = track
                track
            } catch (e: Throwable) {
                android.util.Log.e("ScannerFeedback", "ensureBeepTrackReady error", e)
                null
            }
        }
    }

    private fun playPreparedBeepTrackNow(): Boolean {
        synchronized(audioLock) {
            val track = beepTrack ?: return false
            if (track.state != AudioTrack.STATE_INITIALIZED) {
                return false
            }
            return try {
                if (track.playState != AudioTrack.PLAYSTATE_STOPPED) {
                    track.stop()
                }
                track.reloadStaticData()
                track.play()
                true
            } catch (e: Throwable) {
                android.util.Log.e("ScannerFeedback", "playPreparedBeepTrackNow error", e)
                false
            }
        }
    }

    private fun playScanBeep() {
        synchronized(audioLock) {
            try {
                val track = ensureBeepTrackReady()
                if (track != null) {
                    if (track.playState != AudioTrack.PLAYSTATE_STOPPED) {
                        track.stop()
                    }
                    track.reloadStaticData()
                    track.play()
                    return
                }
            } catch (e: Throwable) {
                android.util.Log.e("ScannerFeedback", "playScanBeep error, falling back", e)
            }

            try {
                android.util.Log.w("ScannerFeedback", "Using ToneGenerator fallback!")
                val generator = fallbackToneGenerator
                    ?: ToneGenerator(AudioManager.STREAM_MUSIC, 45).also {
                        fallbackToneGenerator = it
                    }
                generator.startTone(ToneGenerator.TONE_PROP_BEEP, BEEP_DURATION_MS)
            } catch (_: Throwable) {
                // Ignore if device audio hardware is unavailable.
            }
        }
    }

    private fun buildBeepSamples(): ShortArray {
        val totalSamples = (SAMPLE_RATE_HZ * BEEP_DURATION_MS) / 1000
        val fadeInSamples = max(1, (SAMPLE_RATE_HZ * FADE_IN_MS) / 1000)
        val fadeOutSamples = max(1, (SAMPLE_RATE_HZ * FADE_OUT_MS) / 1000)
        val samples = ShortArray(totalSamples)
        val twoPiFreqOverRate = (2.0 * Math.PI * BEEP_FREQUENCY_HZ) / SAMPLE_RATE_HZ
        val maxAmplitude = Short.MAX_VALUE * BEEP_AMPLITUDE

        for (i in 0 until totalSamples) {
            val theta = i * twoPiFreqOverRate
            // Band-limited softened square wave (fundamental + gentle 3rd & 5th
            // harmonics, all below Nyquist so there is zero aliasing harshness).
            val rawWave = sin(theta) + 0.24 * sin(3.0 * theta) + 0.08 * sin(5.0 * theta)
            val envelope = when {
                i < fadeInSamples ->
                    0.5 * (1.0 - cos(Math.PI * i / fadeInSamples))
                i >= totalSamples - fadeOutSamples -> {
                    val remaining = totalSamples - 1 - i
                    0.5 * (1.0 - cos(Math.PI * remaining / fadeOutSamples))
                }
                else -> 1.0
            }
            samples[i] = (rawWave * envelope * maxAmplitude)
                .roundToInt()
                .coerceIn(Short.MIN_VALUE.toInt(), Short.MAX_VALUE.toInt())
                .toShort()
        }
        return samples
    }

    override fun onDestroy() {
        audioExecutor.shutdownNow()
        ocrPrepExecutor.shutdownNow()
        synchronized(audioLock) {
            beepTrack?.release()
            beepTrack = null
            fallbackToneGenerator?.release()
            fallbackToneGenerator = null
        }
        super.onDestroy()
    }
}
