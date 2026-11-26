package com.qrcheck.app.qr_check

import android.app.Activity
import android.os.Build
import com.google.android.play.core.appupdate.AppUpdateManager
import com.google.android.play.core.appupdate.AppUpdateManagerFactory
import com.google.android.play.core.appupdate.AppUpdateOptions
import com.google.android.play.core.install.InstallStateUpdatedListener
import com.google.android.play.core.install.model.AppUpdateType
import com.google.android.play.core.install.model.InstallStatus
import io.flutter.plugin.common.BinaryMessenger
import io.flutter.plugin.common.MethodCall
import io.flutter.plugin.common.MethodChannel

/**
 * Play In-App Updates bridge (Play Core app-update 2.1.0).
 *
 * Menyediakan dua alur:
 *  - flexible: unduh di latar belakang, pasang saat aplikasi di-restart.
 *  - immediate: pengguna wajib memperbarui sebelum lanjut memakai aplikasi.
 */
class InAppUpdateBridge(
    private val activity: Activity,
    messenger: BinaryMessenger,
) : MethodChannel.MethodCallHandler {

    private val channel = MethodChannel(messenger, CHANNEL)
    private val manager: AppUpdateManager by lazy { AppUpdateManagerFactory.create(activity) }
    private var flexibleDownloaded = false
    private var updateInProgress = false

    private val listener = InstallStateUpdatedListener { state ->
        when (state.installStatus()) {
            InstallStatus.DOWNLOADING -> channel.invokeMethod(
                "onDownloading",
                mapOf(
                    "bytesDownloaded" to state.bytesDownloaded(),
                    "totalBytes" to state.totalBytesToDownload(),
                ),
            )
            InstallStatus.DOWNLOADED -> {
                flexibleDownloaded = true
                channel.invokeMethod("onDownloaded", null)
            }
            InstallStatus.INSTALLED -> {
                flexibleDownloaded = false
                channel.invokeMethod("onInstalled", null)
            }
            InstallStatus.FAILED -> {
                updateInProgress = false
                channel.invokeMethod("onFailed", state.installErrorCode())
            }
            else -> Unit
        }
    }

    fun register() {
        channel.setMethodCallHandler(this)
        manager.registerListener(listener)
    }

    fun dispose() {
        manager.unregisterListener(listener)
        channel.setMethodCallHandler(null)
    }

    /** Dipanggil MainActivity.onResume: selesaikan unduhan yang tertunda. */
    fun onResume() {
        if (!updateInProgress) return
        manager.appUpdateInfo.addOnCompleteListener { task ->
            if (!task.isSuccessful) return@addOnCompleteListener
            val info = task.result ?: return@addOnCompleteListener
            when {
                info.installStatus() == InstallStatus.DOWNLOADED -> {
                    flexibleDownloaded = true
                    channel.invokeMethod("onDownloaded", null)
                }
                // Alur immediate terputus (pengguna keluar dari Play) → lanjutkan.
                info.updateAvailability() ==
                    com.google.android.play.core.install.model.UpdateAvailability.DEVELOPER_TRIGGERED_UPDATE_IN_PROGRESS -> {
                    runCatching {
                        manager.startUpdateFlow(
                            info,
                            activity,
                            AppUpdateOptions.newBuilder(AppUpdateType.IMMEDIATE).build(),
                        )
                    }
                }
            }
        }
    }

    override fun onMethodCall(call: MethodCall, result: MethodChannel.Result) {
        when (call.method) {
            "checkUpdate" -> checkUpdate(result)
            "startFlexible" -> startUpdate(result, AppUpdateType.FLEXIBLE)
            "startImmediate" -> startUpdate(result, AppUpdateType.IMMEDIATE)
            "completeUpdate" -> completeUpdate(result)
            "isDownloaded" -> result.success(flexibleDownloaded)
            else -> result.notImplemented()
        }
    }

    private fun checkUpdate(result: MethodChannel.Result) {
        manager.appUpdateInfo.addOnCompleteListener { task ->
            if (!task.isSuccessful || task.result == null) {
                result.error(
                    "update_info_failed",
                    task.exception?.message ?: "info pembaruan tidak tersedia",
                    null,
                )
                return@addOnCompleteListener
            }
            val info = task.result
            result.success(
                mapOf(
                    "available" to (info.updateAvailability() ==
                        com.google.android.play.core.install.model.UpdateAvailability.UPDATE_AVAILABLE),
                    "immediateAllowed" to info.isUpdateTypeAllowed(AppUpdateType.IMMEDIATE),
                    "flexibleAllowed" to info.isUpdateTypeAllowed(AppUpdateType.FLEXIBLE),
                    "priority" to info.updatePriority(),
                    "stalenessDays" to info.clientVersionStalenessDays(),
                    "availableVersionCode" to info.availableVersionCode(),
                    "installStatus" to info.installStatus(),
                    "fromPlayStore" to isFromPlayStore(),
                    "inProgress" to (info.updateAvailability() ==
                        com.google.android.play.core.install.model.UpdateAvailability.DEVELOPER_TRIGGERED_UPDATE_IN_PROGRESS),
                ),
            )
        }
    }

    private fun startUpdate(result: MethodChannel.Result, type: Int) {
        manager.appUpdateInfo.addOnCompleteListener { task ->
            if (!task.isSuccessful || task.result == null) {
                result.error("update_info_failed", task.exception?.message, null)
                return@addOnCompleteListener
            }
            val info = task.result
            if (!info.isUpdateTypeAllowed(type)) {
                result.success(false)
                return@addOnCompleteListener
            }
            updateInProgress = true
            runCatching {
                manager.startUpdateFlow(
                    info,
                    activity,
                    AppUpdateOptions.newBuilder(type).build(),
                )
            }.onSuccess { flow ->
                flow.addOnCompleteListener { flowTask ->
                    val status = if (flowTask.isSuccessful) flowTask.result else -1
                    // RESULT_OK (0) = diterima, RESULT_CANCELED (1) = dibatalkan pengguna.
                    result.success(status == Activity.RESULT_OK)
                }
            }.onFailure { error ->
                updateInProgress = false
                result.error("start_update_failed", error.message, null)
            }
        }
    }

    private fun completeUpdate(result: MethodChannel.Result) {
        manager.completeUpdate().addOnCompleteListener { task ->
            if (task.isSuccessful) {
                result.success(true)
            } else {
                result.error("complete_update_failed", task.exception?.message, null)
            }
        }
    }

    private fun isFromPlayStore(): Boolean {
        val pm = activity.packageManager
        val installer = if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.R) {
            runCatching {
                pm.getInstallSourceInfo(activity.packageName).installingPackageName
            }.getOrNull()
        } else {
            @Suppress("DEPRECATION")
            pm.getInstallerPackageName(activity.packageName)
        }
        return installer == "com.android.vending"
    }

    companion object {
        const val CHANNEL = "com.qrcheck.app/in_app_update"
    }
}
