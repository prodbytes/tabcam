package com.nu01.tabcam

import androidx.media3.common.util.UnstableApi
import io.flutter.embedding.android.FlutterActivity
import io.flutter.embedding.engine.FlutterEngine

@UnstableApi
class MainActivity : FlutterActivity() {
    private var takeOverlay: TakeOverlay? = null
    private var videoEdit: VideoEdit? = null
    private var cameraPermission: CameraPermission? = null
    private var sound: Sound? = null

    override fun configureFlutterEngine(flutterEngine: FlutterEngine) {
        super.configureFlutterEngine(flutterEngine)
        takeOverlay = TakeOverlay(applicationContext, flutterEngine.dartExecutor.binaryMessenger)
        videoEdit = VideoEdit(applicationContext, flutterEngine.dartExecutor.binaryMessenger)
        cameraPermission = CameraPermission(this, flutterEngine.dartExecutor.binaryMessenger)
        sound = Sound(applicationContext, flutterEngine.dartExecutor.binaryMessenger)
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
        super.cleanUpFlutterEngine(flutterEngine)
    }

    override fun onRequestPermissionsResult(
        requestCode: Int,
        permissions: Array<out String>,
        grantResults: IntArray,
    ) {
        if (cameraPermission?.onResult(requestCode, grantResults) != true) {
            super.onRequestPermissionsResult(requestCode, permissions, grantResults)
        }
    }
}
