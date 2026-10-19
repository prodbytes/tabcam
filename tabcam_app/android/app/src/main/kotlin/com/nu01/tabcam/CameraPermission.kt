package com.nu01.tabcam

import android.Manifest
import android.app.Activity
import android.content.pm.PackageManager
import io.flutter.plugin.common.BinaryMessenger
import io.flutter.plugin.common.MethodChannel

/**
 * Asks for the camera permission for the scanner. Where ML Kit's scanner
 * isn't there (no Google Play services), the scanner falls back to the
 * system camera app, which Android won't open for an app that declares
 * CAMERA (Cam does) without it granted.
 *
 * Channel `tabcam/camera_permission`, method `request`: true when granted.
 */
class CameraPermission(private val activity: Activity, messenger: BinaryMessenger) {
    private val channel = MethodChannel(messenger, CHANNEL)
    private var pending: MethodChannel.Result? = null

    init {
        channel.setMethodCallHandler { call, result ->
            if (call.method != "request") {
                result.notImplemented()
            } else if (granted()) {
                result.success(true)
            } else if (pending != null) {
                result.error("busy", "Already asking for the camera", null)
            } else {
                pending = result
                activity.requestPermissions(arrayOf(Manifest.permission.CAMERA), REQUEST_CODE)
            }
        }
    }

    private fun granted() =
        activity.checkSelfPermission(Manifest.permission.CAMERA) == PackageManager.PERMISSION_GRANTED

    /** The activity's onRequestPermissionsResult; true when it was ours. */
    fun onResult(requestCode: Int, grantResults: IntArray): Boolean {
        if (requestCode != REQUEST_CODE) return false
        pending?.success(grantResults.firstOrNull() == PackageManager.PERMISSION_GRANTED)
        pending = null
        return true
    }

    fun dispose() {
        channel.setMethodCallHandler(null)
        pending?.success(false)
        pending = null
    }

    companion object {
        const val CHANNEL = "tabcam/camera_permission"
        const val REQUEST_CODE = 2012
    }
}
