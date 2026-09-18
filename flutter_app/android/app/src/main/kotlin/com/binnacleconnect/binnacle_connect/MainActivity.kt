package com.binnacleconnect.binnacle_connect

import android.media.MediaCodec
import android.media.MediaExtractor
import android.media.MediaFormat
import android.media.MediaMetadataRetriever
import android.media.MediaMuxer
import android.os.Handler
import android.os.Looper
import android.os.StatFs
import io.flutter.embedding.android.FlutterActivity
import io.flutter.embedding.engine.FlutterEngine
import io.flutter.plugin.common.MethodChannel
import java.io.File
import java.nio.ByteBuffer

class MainActivity : FlutterActivity() {
    @Volatile private var cancelTrim = false
    @Volatile private var trimRunning = false

    override fun configureFlutterEngine(flutterEngine: FlutterEngine) {
        super.configureFlutterEngine(flutterEngine)
        val channel = MethodChannel(flutterEngine.dartExecutor.binaryMessenger, "binnacle/video_trim")
        val main = Handler(Looper.getMainLooper())
        channel.setMethodCallHandler { call, result ->
            when (call.method) {
                "cancel" -> { cancelTrim = true; result.success(null) }
                "trim" -> {
                    if (trimRunning) { result.error("busy", "A trim is already running", null); return@setMethodCallHandler }
                    val src = call.argument<String>("source")!!
                    val dst = call.argument<String>("output")!!
                    val startUs = (call.argument<Number>("startUs")!!).toLong()
                    val endUs = (call.argument<Number>("endUs")!!).toLong()
                    cancelTrim = false
                    trimRunning = true
                    Thread {
                        try {
                            val outcome = trim(src, dst, startUs, endUs) { p ->
                                main.post { channel.invokeMethod("progress", p) }
                            }
                            main.post { trimRunning = false; result.success(outcome) }
                        } catch (e: TrimException) {
                            File(dst).delete()
                            main.post { trimRunning = false; result.error(e.code, e.message, null) }
                        } catch (e: Exception) {
                            File(dst).delete()
                            main.post { trimRunning = false; result.error("failed", e.message ?: e.javaClass.simpleName, null) }
                        }
                    }.start()
                }
                else -> result.notImplemented()
            }
        }
    }

    private class TrimException(val code: String, msg: String) : Exception(msg)

    /**
     * Lossless trim (no re-encode): copies compressed samples from the
     * keyframe at/before startUs up to endUs. Keeps audio and rotation.
     * Returns "ok" or "cancelled". Never touches the source file.
     */
    private fun trim(src: String, dst: String, startUs: Long, endUs: Long, onProgress: (Double) -> Unit): String {
        val srcFile = File(src)
        if (!srcFile.exists()) throw TrimException("missing_source", "Source video file is missing")
        val outDir = File(dst).parentFile!!
        outDir.mkdirs()
        val free = StatFs(outDir.path).availableBytes
        if (free < srcFile.length() + 8L * 1024 * 1024) {
            throw TrimException("insufficient_space", "Not enough free storage to save an edited copy")
        }
        val extractor = MediaExtractor()
        var muxerRef: MediaMuxer? = null
        try {
            extractor.setDataSource(src)
            val rotation = MediaMetadataRetriever().let { r ->
                try {
                    r.setDataSource(src)
                    r.extractMetadata(MediaMetadataRetriever.METADATA_KEY_VIDEO_ROTATION)?.toIntOrNull() ?: 0
                } finally { r.release() }
            }
            val muxer = MediaMuxer(dst, MediaMuxer.OutputFormat.MUXER_OUTPUT_MPEG_4)
            muxerRef = muxer
            muxer.setOrientationHint(rotation)
            val indexMap = HashMap<Int, Int>()
            var maxSize = 1 * 1024 * 1024
            for (i in 0 until extractor.trackCount) {
                val fmt = extractor.getTrackFormat(i)
                val mime = fmt.getString(MediaFormat.KEY_MIME) ?: continue
                if (!mime.startsWith("video/") && !mime.startsWith("audio/")) continue
                extractor.selectTrack(i)
                indexMap[i] = muxer.addTrack(fmt)
                if (fmt.containsKey(MediaFormat.KEY_MAX_INPUT_SIZE)) {
                    maxSize = maxOf(maxSize, fmt.getInteger(MediaFormat.KEY_MAX_INPUT_SIZE))
                }
            }
            if (indexMap.isEmpty()) throw TrimException("unsupported", "No audio/video tracks to export")
            muxer.start()
            extractor.seekTo(startUs, MediaExtractor.SEEK_TO_PREVIOUS_SYNC)
            val buf = ByteBuffer.allocate(maxSize)
            val info = MediaCodec.BufferInfo()
            var base = -1L
            val span = maxOf(1L, endUs - startUs).toDouble()
            var lastReport = 0L
            while (true) {
                if (cancelTrim) {
                    muxer.stop(); muxer.release(); muxerRef = null
                    File(dst).delete()
                    return "cancelled"
                }
                buf.clear()
                val size = extractor.readSampleData(buf, 0)
                if (size < 0) break
                val t = extractor.sampleTime
                if (t > endUs) break
                if (base < 0) base = t
                val flags = if ((extractor.sampleFlags and MediaExtractor.SAMPLE_FLAG_SYNC) != 0) MediaCodec.BUFFER_FLAG_KEY_FRAME else 0
                info.set(0, size, maxOf(0L, t - base), flags)
                val out = indexMap[extractor.sampleTrackIndex]
                if (out != null) muxer.writeSampleData(out, buf, info)
                val now = System.currentTimeMillis()
                if (now - lastReport > 100) {
                    lastReport = now
                    onProgress(((t - startUs) / span).coerceIn(0.0, 1.0))
                }
                extractor.advance()
            }
            muxer.stop()
            muxer.release()
            muxerRef = null
            onProgress(1.0)
            return "ok"
        } finally {
            try { muxerRef?.release() } catch (_: Exception) {}
            extractor.release()
        }
    }
}
