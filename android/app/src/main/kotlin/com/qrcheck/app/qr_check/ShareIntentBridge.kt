package com.qrcheck.app.qr_check

import android.app.Activity
import android.content.Intent
import android.net.Uri
import android.os.Handler
import android.os.Looper
import io.flutter.plugin.common.BinaryMessenger
import io.flutter.plugin.common.MethodChannel
import java.io.File
import java.util.UUID

/**
 * Menerima gambar yang dibagikan dari aplikasi lain (WhatsApp, Telegram,
 * Galeri, Files) lewat Android share sheet.
 *
 * Gambar langsung disalin ke cache aplikasi supaya URI sementara dari aplikasi
 * pengirim tidak kedaluwarsa saat Flutter memprosesnya.
 *
 * Channel: `com.qrcheck.app/share`
 *  - Flutter → native: `getPendingFiles` (ambil file dari cold start), `clearPending`
 *  - native → Flutter: `sharedFiles` (List<String> path)
 */
class ShareIntentBridge(
    private val activity: Activity,
    messenger: BinaryMessenger,
) {
    companion object {
        const val CHANNEL = "com.qrcheck.app/share"

        /** Path file yang belum diambil Flutter (mis. saat cold start). */
        private val pending = mutableListOf<String>()
    }

    private val channel = MethodChannel(messenger, CHANNEL)
    private var ready = false

    fun register() {
        channel.setMethodCallHandler { call, result ->
            when (call.method) {
                "getPendingFiles" -> {
                    ready = true
                    result.success(drain())
                }
                "clearPending" -> {
                    synchronized(pending) { pending.clear() }
                    result.success(true)
                }
                else -> result.notImplemented()
            }
        }
    }

    /**
     * Proses intent share. Mengembalikan true bila ada gambar yang diterima.
     */
    @Suppress("DEPRECATION")
    fun handleIntent(intent: Intent?): Boolean {
        if (intent == null) return false
        val action = intent.action ?: return false
        if (action != Intent.ACTION_SEND && action != Intent.ACTION_SEND_MULTIPLE) return false

        val uris = extractUris(intent)
        if (uris.isEmpty()) return false

        val copied = uris.mapNotNull { copyToCache(it) }
        if (copied.isEmpty()) return false

        synchronized(pending) { pending.addAll(copied) }
        if (ready) {
            Handler(Looper.getMainLooper()).post {
                channel.invokeMethod("sharedFiles", copied)
            }
        }
        return true
    }

    /**
     * Ambil URI dari EXTRA_STREAM. Pengirim yang berbeda bisa mengirim `Uri`,
     * `String`, atau `ArrayList` berisi keduanya — semuanya ditangani.
     */
    private fun extractUris(intent: Intent): List<Uri> {
        val extra = intent.extras?.get(Intent.EXTRA_STREAM) ?: return emptyList()
        return when (extra) {
            is Uri -> listOf(extra)
            is String -> listOfNotNull(runCatching { Uri.parse(extra) }.getOrNull())
            is ArrayList<*> -> extra.mapNotNull { item ->
                when (item) {
                    is Uri -> item
                    is String -> runCatching { Uri.parse(item) }.getOrNull()
                    else -> null
                }
            }
            else -> emptyList()
        }
    }

    private fun drain(): List<String> = synchronized(pending) {
        val out = pending.toList()
        pending.clear()
        out
    }

    private fun copyToCache(uri: Uri): String? {
        return try {
            val dir = File(activity.cacheDir, "shared_in")
            if (!dir.exists() && !dir.mkdirs()) return null

            val mime = activity.contentResolver.getType(uri) ?: "image/jpeg"
            val ext = when {
                mime.contains("png") -> "png"
                mime.contains("webp") -> "webp"
                mime.contains("gif") -> "gif"
                mime.contains("heic") -> "heic"
                mime.contains("bmp") -> "bmp"
                else -> "jpg"
            }

            val stamp = System.currentTimeMillis()
            val suffix = UUID.randomUUID().toString().take(6)
            val target = File(dir, "share_${stamp}_$suffix.$ext")

            activity.contentResolver.openInputStream(uri)?.use { input ->
                target.outputStream().use { output -> input.copyTo(output) }
            } ?: return null

            if (target.length() <= 0L) {
                target.delete()
                return null
            }
            target.absolutePath
        } catch (e: Exception) {
            null
        }
    }
}
