package com.qrcheck.app.qr_check

import android.content.Intent
import io.flutter.embedding.android.FlutterActivity
import io.flutter.embedding.engine.FlutterEngine

class MainActivity : FlutterActivity() {
    private var billingBridge: PlayBillingBridge? = null
    private var shareBridge: ShareIntentBridge? = null
    private var updateBridge: InAppUpdateBridge? = null

    override fun configureFlutterEngine(flutterEngine: FlutterEngine) {
        super.configureFlutterEngine(flutterEngine)

        billingBridge = PlayBillingBridge(this, flutterEngine.dartExecutor.binaryMessenger).also {
            it.register()
        }

        // Terima gambar dari share sheet (WhatsApp, Telegram, Galeri, Files).
        shareBridge = ShareIntentBridge(this, flutterEngine.dartExecutor.binaryMessenger).also {
            it.register()
            // Cold start: aplikasi dibuka langsung dari share sheet.
            it.handleIntent(intent)
        }

        // Play In-App Updates (flexible / immediate).
        updateBridge = InAppUpdateBridge(this, flutterEngine.dartExecutor.binaryMessenger).also {
            it.register()
        }
    }

    override fun onResume() {
        super.onResume()
        // Selesaikan unduhan pembaruan yang tertunda saat aplikasi kembali aktif.
        updateBridge?.onResume()
    }

    override fun onDestroy() {
        updateBridge?.dispose()
        super.onDestroy()
    }

    override fun onNewIntent(intent: Intent) {
        super.onNewIntent(intent)
        setIntent(intent)
        // Warm start: aplikasi sudah berjalan di background.
        shareBridge?.handleIntent(intent)
    }
}
