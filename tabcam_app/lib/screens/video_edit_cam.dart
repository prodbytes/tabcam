part of 'video_edit_screen.dart';

/// What a [StudioView] opened as Cam needs for its camera, its takes and
/// its play-along, as Cam's screen is given them: the cameras there
/// are, head gestures, the takes' recorder, a link's frame and a PDF's
/// view (tests pass their own of each), and, for a user without Premium,
/// the preview's [gate].
class CamSetup {
  const CamSetup({
    this.cameras = listCameras,
    this.headTracking = HeadTracking.start,
    this.takeRecorder = TakeRecorder.forPlatform,
    this.linkFrame = linkFrameFor,
    this.pdfView = pdfViewFor,
    this.gate,
  });

  /// The cameras there are.
  final Future<List<CameraDescription>> Function() cameras;

  /// Watches for head gestures; null where it can't.
  final HeadTracking? Function(
    CameraController camera,
    void Function(HeadGesture) onGesture,
  )
  headTracking;

  /// Records takes where the camera plugin doesn't (the web); null where
  /// it does.
  final TakeRecorder? Function() takeRecorder;

  /// Shows a link in the backing track's frame.
  final Widget Function(LinkFrameController controller) linkFrame;

  /// Shows the PDF followed beside the camera.
  final Widget Function(Library library, CaptureEvent event, EventPage page)
  pdfView;

  /// Set for a user without Premium: Cam is a preview, greyed out under
  /// the Premium card ([PremiumGate]), and no camera opens.
  final ({CloudOcr ocr, String? email})? gate;
}
