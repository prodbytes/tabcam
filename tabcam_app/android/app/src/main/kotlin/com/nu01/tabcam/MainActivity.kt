package com.nu01.tabcam

import android.Manifest
import android.content.pm.PackageManager
import android.os.Process
import androidx.media3.common.util.UnstableApi
import io.flutter.embedding.android.FlutterActivity
import io.flutter.embedding.engine.FlutterEngine

@UnstableApi
class MainActivity : FlutterActivity() {
    private var takeOverlay: TakeOverlay? = null
    private var videoEdit: VideoEdit? = null
    private var cameraPermission: CameraPermission? = null
    private var sound: Sound? = null
    private var takeSound: TakeSound? = null

    override fun configureFlutterEngine(flutterEngine: FlutterEngine) {
        super.configureFlutterEngine(flutterEngine)
        takeOverlay = TakeOverlay(applicationContext, flutterEngine.dartExecutor.binaryMessenger)
        videoEdit = VideoEdit(applicationContext, flutterEngine.dartExecutor.binaryMessenger)
        cameraPermission = CameraPermission(this, flutterEngine.dartExecutor.binaryMessenger)
        sound = Sound(applicationContext, flutterEngine.dartExecutor.binaryMessenger)
        takeSound = TakeSound(this, flutterEngine.dartExecutor.binaryMessenger)
    }

    override fun cleanUpFlutterEngine(flutterEngine: FlutterEngine) {
        takeOverlay?.dispose()
        takeOverlay = null
        videoEdit?.dispose()
        videoEdit = null
        cameraPermission?.dispose()
        cameraPermission = null
        sound?.dispose()
        sound = null
        takeSound?.dispose()
        takeSound = null
        super.cleanUpFlutterEngine(flutterEngine)
    }

    override fun onRequestPermissionsResult(
        requestCode: Int,
        permissions: Array<out String>,
        grantResults: IntArray,
    ) {
        if (cameraPermission?.onResult(requestCode, grantResults) != true &&
            takeSound?.onResult(requestCode, grantResults) != true
        ) {
            super.onRequestPermissionsResult(requestCode, permissions, grantResults)
        }
    }

    /**
     * While a take's camera recording starts with its sound recorded by
     * the app ([TakeSound.hidesMicrophone]), the microphone reads as
     * refused here, to this app only. The camera plugin asks this activity
     * just before it starts recording (`ContextCompat.checkSelfPermission`)
     * and, refused, records no sound; allowed, it would open the
     * microphone with the camcorder source even with its sound off, and
     * that source's processing would reach the take's own sound too. The
     * app's own checks go through the application's context, which this
     * doesn't change, and nothing else asks during that moment.
     */
    override fun checkPermission(permission: String, pid: Int, uid: Int): Int {
        if (TakeSound.hidesMicrophone &&
            permission == Manifest.permission.RECORD_AUDIO &&
            pid == Process.myPid() &&
            uid == Process.myUid()
        ) {
            return PackageManager.PERMISSION_DENIED
        }
        return super.checkPermission(permission, pid, uid)
    }
}
