package com.binnacleconnect.binnacle_connect

import android.content.ContentValues
import android.graphics.Bitmap
import android.media.MediaMetadataRetriever
import android.os.Build
import android.os.Handler
import android.os.Looper
import android.provider.MediaStore
import io.flutter.FlutterInjector
import io.flutter.embedding.android.FlutterActivity
import io.flutter.embedding.engine.FlutterEngine
import io.flutter.plugin.common.MethodChannel
import java.io.File
import java.io.FileOutputStream
import java.io.IOException

/**
 * Local media helpers for the recorded Demo feed (Snapshot).
 *
 * - `extractFrame`: decodes the real frame at a position of a bundled Flutter
 *   asset with the platform MediaMetadataRetriever and writes a JPEG. No
 *   FFmpeg, no screenshot of a video texture.
 * - `exportImage`: publishes an image to the gallery through MediaStore
 *   (scoped storage, API 29+). It needs no storage permission, and nothing
 *   here requests MANAGE_EXTERNAL_STORAGE.
 */
class MainActivity : FlutterActivity() {
    private val main = Handler(Looper.getMainLooper())

    override fun configureFlutterEngine(flutterEngine: FlutterEngine) {
        super.configureFlutterEngine(flutterEngine)
        MethodChannel(flutterEngine.dartExecutor.binaryMessenger, "binnacle/demo_media")
            .setMethodCallHandler { call, result ->
                when (call.method) {
                    "extractFrame" -> {
                        val assetPath = call.argument<String>("assetPath")
                        val positionMs = call.argument<Number>("positionMs")?.toLong()
                        val outputPath = call.argument<String>("outputPath")
                        if (assetPath == null || positionMs == null || outputPath == null) {
                            result.error("bad_args", "assetPath, positionMs and outputPath are required", null)
                            return@setMethodCallHandler
                        }
                        Thread {
                            try {
                                val size = extractFrame(assetPath, positionMs, outputPath)
                                main.post { result.success(mapOf("width" to size.first, "height" to size.second)) }
                            } catch (e: Exception) {
                                main.post { result.error("extract_failed", e.message ?: e.javaClass.simpleName, null) }
                            }
                        }.start()
                    }
                    "exportImage" -> {
                        val path = call.argument<String>("path")
                        val name = call.argument<String>("displayName")
                        if (path == null || name == null) {
                            result.error("bad_args", "path and displayName are required", null)
                            return@setMethodCallHandler
                        }
                        Thread {
                            try {
                                val uri = exportImage(path, name)
                                main.post { result.success(uri) }
                            } catch (e: Exception) {
                                main.post { result.error("export_failed", e.message ?: e.javaClass.simpleName, null) }
                            }
                        }.start()
                    }
                    else -> result.notImplemented()
                }
            }
    }

    /** Returns (width, height) of the JPEG written to [outputPath]. */
    private fun extractFrame(assetPath: String, positionMs: Long, outputPath: String): Pair<Int, Int> {
        val key = FlutterInjector.instance().flutterLoader().getLookupKeyForAsset(assetPath)
        val retriever = MediaMetadataRetriever()
        try {
            try {
                // mp4 assets are stored uncompressed, so they can be opened as a
                // file descriptor without copying the whole video.
                assets.openFd(key).use { afd ->
                    retriever.setDataSource(afd.fileDescriptor, afd.startOffset, afd.length)
                }
            } catch (e: IOException) {
                // Fallback for a compressed asset: copy once to the cache.
                val cached = File(cacheDir, "demo_src_" + assetPath.hashCode() + ".mp4")
                if (!cached.exists() || cached.length() == 0L) {
                    assets.open(key).use { input -> cached.outputStream().use { input.copyTo(it) } }
                }
                retriever.setDataSource(cached.absolutePath)
            }
            val bitmap: Bitmap = retriever.getFrameAtTime(
                positionMs * 1000L,
                MediaMetadataRetriever.OPTION_CLOSEST
            ) ?: throw IOException("No frame could be decoded at $positionMs ms")
            File(outputPath).parentFile?.mkdirs()
            FileOutputStream(outputPath).use { out ->
                if (!bitmap.compress(Bitmap.CompressFormat.JPEG, 92, out)) {
                    throw IOException("Could not encode the frame as JPEG")
                }
            }
            val size = Pair(bitmap.width, bitmap.height)
            bitmap.recycle()
            return size
        } finally {
            retriever.release()
        }
    }

    /** Returns the MediaStore URI, or null where scoped-storage export is unavailable (API < 29). */
    private fun exportImage(path: String, displayName: String): String? {
        if (Build.VERSION.SDK_INT < Build.VERSION_CODES.Q) return null
        val source = File(path)
        if (!source.exists() || source.length() == 0L) throw IOException("The image file is missing")
        val resolver = contentResolver
        val values = ContentValues().apply {
            put(MediaStore.Images.Media.DISPLAY_NAME, displayName)
            put(MediaStore.Images.Media.MIME_TYPE, "image/jpeg")
            put(MediaStore.Images.Media.RELATIVE_PATH, "Pictures/Binnacle")
            put(MediaStore.Images.Media.IS_PENDING, 1)
        }
        val uri = resolver.insert(MediaStore.Images.Media.EXTERNAL_CONTENT_URI, values)
            ?: throw IOException("MediaStore refused the insert")
        try {
            resolver.openOutputStream(uri)?.use { out -> source.inputStream().use { it.copyTo(out) } }
                ?: throw IOException("Could not open the MediaStore output stream")
            val done = ContentValues().apply { put(MediaStore.Images.Media.IS_PENDING, 0) }
            resolver.update(uri, done, null, null)
        } catch (e: Exception) {
            resolver.delete(uri, null, null)
            throw e
        }
        return uri.toString()
    }
}
