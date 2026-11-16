import 'package:camera/camera.dart';

/// The camera plugin's list, as it is (the apps).
Future<List<CameraDescription>> listCameras() => availableCameras();
