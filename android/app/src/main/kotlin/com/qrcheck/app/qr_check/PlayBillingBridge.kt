package com.qrcheck.app.qr_check

import android.app.Activity
import android.os.Handler
import android.os.Looper
import com.android.billingclient.api.AcknowledgePurchaseParams
import com.android.billingclient.api.BillingClient
import com.android.billingclient.api.BillingClientStateListener
import com.android.billingclient.api.BillingFlowParams
import com.android.billingclient.api.BillingResult
import com.android.billingclient.api.PendingPurchasesParams
import com.android.billingclient.api.ProductDetails
import com.android.billingclient.api.Purchase
import com.android.billingclient.api.PurchasesUpdatedListener
import com.android.billingclient.api.QueryProductDetailsParams
import com.android.billingclient.api.QueryPurchasesParams
import io.flutter.plugin.common.BinaryMessenger
import io.flutter.plugin.common.MethodCall
import io.flutter.plugin.common.MethodChannel

/**
 * Jembatan tipis Flutter <-> Google Play Billing Library (PBL 8.x).
 *
 * Prinsip:
 *  - Native HANYA menjalankan billing flow + membaca status pembelian.
 *  - Pemberian hak PRO (is_pro) TIDAK pernah dilakukan di client, melainkan
 *    diverifikasi server-side (Supabase Edge Function -> Play Developer API).
 *  - Acknowledge dilakukan server setelah verifikasi sukses (lihat edge function).
 */
class PlayBillingBridge(
    private val activity: Activity,
    messenger: BinaryMessenger,
) : MethodChannel.MethodCallHandler, PurchasesUpdatedListener {

    companion object {
        private const val CHANNEL = "com.qrcheck.app/billing"
        private const val PLAY_STORE_PACKAGE = "com.android.vending"
    }

    private val mainHandler = Handler(Looper.getMainLooper())
    private val channel = MethodChannel(messenger, CHANNEL)

    private val billingClient: BillingClient = BillingClient.newBuilder(activity.applicationContext)
        .setListener(this)
        .enablePendingPurchases(
            PendingPurchasesParams.newBuilder().enableOneTimeProducts().build()
        )
        .enableAutoServiceReconnection()
        .build()

    fun register() {
        channel.setMethodCallHandler(this)
    }

    // ─── Method channel ────────────────────────────────────────────────
    override fun onMethodCall(call: MethodCall, result: MethodChannel.Result) {
        when (call.method) {
            "isAvailable" -> result.success(isPlayStoreInstalled())

            "init" -> ensureConnected { billingResult ->
                result.success(
                    mapOf(
                        "connected" to (billingResult.responseCode == BillingClient.BillingResponseCode.OK),
                        "code" to billingResult.responseCode,
                        "message" to billingResult.debugMessage,
                    )
                )
            }

            "queryProduct" -> {
                val productId = call.argument<String>("productId")
                if (productId.isNullOrBlank()) {
                    result.error("bad_args", "productId wajib diisi", null)
                } else {
                    queryProduct(productId, result)
                }
            }

            "launchPurchase" -> {
                val productId = call.argument<String>("productId")
                val accountId = call.argument<String>("obfuscatedAccountId")
                if (productId.isNullOrBlank()) {
                    result.error("bad_args", "productId wajib diisi", null)
                } else {
                    launchPurchase(productId, accountId, result)
                }
            }

            "queryPurchases" -> queryPurchases(result)

            "acknowledge" -> {
                val token = call.argument<String>("purchaseToken")
                if (token.isNullOrBlank()) {
                    result.error("bad_args", "purchaseToken wajib diisi", null)
                } else {
                    acknowledge(token, result)
                }
            }

            "endConnection" -> {
                billingClient.endConnection()
                result.success(null)
            }

            else -> result.notImplemented()
        }
    }

    // ─── Connection ────────────────────────────────────────────────────
    private fun isPlayStoreInstalled(): Boolean = try {
        activity.packageManager.getPackageInfo(PLAY_STORE_PACKAGE, 0)
        true
    } catch (_: Exception) {
        false
    }

    private fun ensureConnected(onReady: (BillingResult) -> Unit) {
        if (billingClient.isReady) {
            onReady(
                BillingResult.newBuilder()
                    .setResponseCode(BillingClient.BillingResponseCode.OK)
                    .setDebugMessage("already_connected")
                    .build()
            )
            return
        }
        billingClient.startConnection(object : BillingClientStateListener {
            override fun onBillingSetupFinished(billingResult: BillingResult) {
                onReady(billingResult)
            }

            override fun onBillingServiceDisconnected() {
                // enableAutoServiceReconnection() akan menyambung ulang otomatis.
            }
        })
    }

    // ─── Query product ─────────────────────────────────────────────────
    private fun queryProduct(productId: String, result: MethodChannel.Result) {
        ensureConnected { setup ->
            if (setup.responseCode != BillingClient.BillingResponseCode.OK) {
                result.success(
                    mapOf(
                        "product" to null,
                        "code" to setup.responseCode,
                        "message" to setup.debugMessage,
                    )
                )
                return@ensureConnected
            }

            val params = QueryProductDetailsParams.newBuilder()
                .setProductList(
                    listOf(
                        QueryProductDetailsParams.Product.newBuilder()
                            .setProductId(productId)
                            .setProductType(BillingClient.ProductType.INAPP)
                            .build()
                    )
                )
                .build()

            billingClient.queryProductDetailsAsync(params) { billingResult, detailsResult ->
                if (billingResult.responseCode != BillingClient.BillingResponseCode.OK) {
                    result.success(
                        mapOf(
                            "product" to null,
                            "code" to billingResult.responseCode,
                            "message" to billingResult.debugMessage,
                        )
                    )
                    return@queryProductDetailsAsync
                }
                val details = detailsResult.productDetailsList.firstOrNull()
                result.success(
                    mapOf(
                        "product" to details?.let { productToMap(it) },
                        "code" to billingResult.responseCode,
                        "message" to billingResult.debugMessage,
                    )
                )
            }
        }
    }

    private fun productToMap(details: ProductDetails): Map<String, Any?> {
        val offer = details.oneTimePurchaseOfferDetailsList?.firstOrNull()
        return mapOf(
            "productId" to details.productId,
            "title" to details.title,
            "name" to details.name,
            "description" to details.description,
            "productType" to details.productType,
            "formattedPrice" to offer?.formattedPrice,
            "priceAmountMicros" to offer?.priceAmountMicros,
            "currencyCode" to offer?.priceCurrencyCode,
        )
    }

    // ─── Purchase flow ─────────────────────────────────────────────────
    private fun launchPurchase(
        productId: String,
        obfuscatedAccountId: String?,
        result: MethodChannel.Result,
    ) {
        ensureConnected { setup ->
            if (setup.responseCode != BillingClient.BillingResponseCode.OK) {
                result.success(
                    mapOf(
                        "launched" to false,
                        "code" to setup.responseCode,
                        "message" to setup.debugMessage,
                    )
                )
                return@ensureConnected
            }

            val params = QueryProductDetailsParams.newBuilder()
                .setProductList(
                    listOf(
                        QueryProductDetailsParams.Product.newBuilder()
                            .setProductId(productId)
                            .setProductType(BillingClient.ProductType.INAPP)
                            .build()
                    )
                )
                .build()

            billingClient.queryProductDetailsAsync(params) { billingResult, detailsResult ->
                if (billingResult.responseCode != BillingClient.BillingResponseCode.OK) {
                    result.success(
                        mapOf(
                            "launched" to false,
                            "code" to billingResult.responseCode,
                            "message" to billingResult.debugMessage,
                        )
                    )
                    return@queryProductDetailsAsync
                }
                val details = detailsResult.productDetailsList.firstOrNull()
                if (details == null) {
                    result.success(
                        mapOf(
                            "launched" to false,
                            "code" to BillingClient.BillingResponseCode.ITEM_UNAVAILABLE,
                            "message" to "product_not_found",
                        )
                    )
                    return@queryProductDetailsAsync
                }

                val flowParamsBuilder = BillingFlowParams.newBuilder()
                    .setProductDetailsParamsList(
                        listOf(
                            BillingFlowParams.ProductDetailsParams.newBuilder()
                                .setProductDetails(details)
                                .build()
                        )
                    )
                if (!obfuscatedAccountId.isNullOrBlank()) {
                    flowParamsBuilder.setObfuscatedAccountId(obfuscatedAccountId.take(64))
                }

                val launch = billingClient.launchBillingFlow(activity, flowParamsBuilder.build())
                result.success(
                    mapOf(
                        "launched" to (launch.responseCode == BillingClient.BillingResponseCode.OK),
                        "code" to launch.responseCode,
                        "message" to launch.debugMessage,
                    )
                )
            }
        }
    }

    // ─── Restore / owned purchases ─────────────────────────────────────
    private fun queryPurchases(result: MethodChannel.Result) {
        ensureConnected { setup ->
            if (setup.responseCode != BillingClient.BillingResponseCode.OK) {
                result.success(
                    mapOf(
                        "purchases" to emptyList<Map<String, Any?>>(),
                        "code" to setup.responseCode,
                        "message" to setup.debugMessage,
                    )
                )
                return@ensureConnected
            }
            val params = QueryPurchasesParams.newBuilder()
                .setProductType(BillingClient.ProductType.INAPP)
                .build()

            billingClient.queryPurchasesAsync(params) { billingResult, purchases ->
                result.success(
                    mapOf(
                        "purchases" to purchases.map { purchaseToMap(it) },
                        "code" to billingResult.responseCode,
                        "message" to billingResult.debugMessage,
                    )
                )
            }
        }
    }

    // ─── Acknowledge (fallback lokal) ──────────────────────────────────
    private fun acknowledge(purchaseToken: String, result: MethodChannel.Result) {
        val params = AcknowledgePurchaseParams.newBuilder()
            .setPurchaseToken(purchaseToken)
            .build()
        billingClient.acknowledgePurchase(params) { billingResult ->
            result.success(
                mapOf(
                    "ok" to (billingResult.responseCode == BillingClient.BillingResponseCode.OK),
                    "code" to billingResult.responseCode,
                    "message" to billingResult.debugMessage,
                )
            )
        }
    }

    // ─── Listener pembelian ────────────────────────────────────────────
    override fun onPurchasesUpdated(billingResult: BillingResult, purchases: MutableList<Purchase>?) {
        val payload = mapOf(
            "code" to billingResult.responseCode,
            "message" to billingResult.debugMessage,
            "purchases" to (purchases ?: emptyList()).map { purchaseToMap(it) },
        )
        mainHandler.post {
            channel.invokeMethod("onPurchasesUpdated", payload)
        }
    }

    private fun purchaseToMap(purchase: Purchase): Map<String, Any?> = mapOf(
        "purchaseToken" to purchase.purchaseToken,
        "orderId" to purchase.orderId,
        "productIds" to purchase.products,
        "purchaseState" to when (purchase.purchaseState) {
            Purchase.PurchaseState.PURCHASED -> "PURCHASED"
            Purchase.PurchaseState.PENDING -> "PENDING"
            else -> "UNSPECIFIED"
        },
        "acknowledged" to purchase.isAcknowledged,
        "autoRenewing" to purchase.isAutoRenewing,
        "quantity" to purchase.quantity,
        "purchaseTime" to purchase.purchaseTime,
    )
}
