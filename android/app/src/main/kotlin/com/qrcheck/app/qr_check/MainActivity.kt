package com.qrcheck.app.qr_check

import io.flutter.embedding.android.FlutterActivity
import io.flutter.embedding.engine.FlutterEngine

class MainActivity : FlutterActivity() {
    private var billingBridge: PlayBillingBridge? = null

    override fun configureFlutterEngine(flutterEngine: FlutterEngine) {
        super.configureFlutterEngine(flutterEngine)
        billingBridge = PlayBillingBridge(this, flutterEngine.dartExecutor.binaryMessenger).also {
            it.register()
        }
    }
}
