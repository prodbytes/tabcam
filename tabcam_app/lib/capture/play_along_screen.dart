import 'package:camera/camera.dart';
import 'package:flutter/material.dart';

import '../l10n/language.dart';
import '../library/capture_event.dart';
import '../cloud/cloud_ocr.dart';
import '../cloud/cloud_sync.dart';
import '../library/library.dart';
import '../screens/premium_card.dart';
import '../screens/video_edit_screen.dart';
import 'camera_list.dart';
import 'head_gestures.dart';
import 'link_frame.dart';
import 'play_along_sidebar.dart';
import 'take_recorder.dart';

export 'cam_session.dart' show takePlaysHere;

/// Cam: the guitarist records themselves playing along with the capture's
/// tab. The camera (the front one first: it faces the player) fills the
/// screen, with the tab under it one neckline at a time ([necklines]).
/// Any key moves to the next neckline (a page-turner pedal, a keyboard);
/// Backspace, ← , ↑ and Page Up to the one before; a tap on the neckline
/// or its arrows too; on Android, iOS and the web, a strong nod up or turn
/// to the right too, a nod down or turn to the left to the one before
/// ([HeadTracking]). **Rec** (or the 1 key) records (video and sound)
/// until it's tapped again, and adds the take to the capture as a video
/// ("Take 1", "Take 2"…), saved as the camera recorded it, with no tab in
/// its picture; the / key saves the take and starts the next, the . key
/// throws the take away and starts the next (only the last is kept), the
/// song in the sidebar from its start either way. Each take keeps a log of what Cam noted
/// while it recorded ([TakeLog]: the tab's turns, the necklines shown,
/// how far the file started before the take's clock), from which the
/// video editor draws the tab over it. **Play**
/// plays the capture's last take back, the necklines turning where they
/// turned while it was recorded (as its log says).
/// **Tab** hides the tab from the screen, and shows it again.
///
/// **Phrase passes**: while recording along with a song playing in the
/// sidebar's frame, with Auto-pass on, each turn of the tab is noted at
/// the song's position ([BackingTrack.recordPass]), merged with one the
/// same way within two seconds of it, and kept with the capture
/// ([PhraseTimes]); the take keeps its own. **Auto-pass** (beside Tab, on
/// by default, kept on the device) then turns the tab by itself where it
/// turned before, each time through the song ([AutoPass]). Off, no pass
/// is noted, for the song or the take.
///
/// **Play along** (the app bar's, when the capture has recordings, videos,
/// links or PDFs) shows and hides a sidebar of them, open from the first
/// time there's one (when Cam opens, or when one arrives later): the
/// one tapped plays in a compact frame at the sidebar's top, above the
/// list ([BackingTrack]), while the user plays and records; the space bar
/// pauses and plays it. A PDF tapped there shows on the screen's other
/// side, to follow the tab on it ([PlayAlong.followed]).
///
/// **Recording comes first** ([TakePriority]): the take's sound is
/// recorded as a musician wants it (on Android, by the app itself, from
/// the microphone's unprocessed source, and put into the take after
/// ([TakeSound]); on iOS, the audio session set for recording music and
/// mixed with the song; on the web, the microphone without voice-call
/// processing, at a high bitrate), set up when Cam opens rather than as
/// the take starts; while it records, head gestures
/// look less often, and cloud sync starts no pass.
/// A take's name: "Take" and the time it started, [started], as hours and
/// minutes ("Take 14:32", 24-hour). The day isn't in the name: the
/// sidebar lists the takes under their day. Takes started in the same
/// minute share the name (until 2026-11-17 the seconds, then a number,
/// told them apart).
String takeName(AppLocalizations l10n, DateTime started) {
  String two(int n) => n.toString().padLeft(2, '0');
  return l10n.camTake('${two(started.hour)}:${two(started.minute)}');
}

/// Cam's screen: a [StudioView] with the camera in its main row's place
/// ([CamSetup]), as the capture's Cam opens it.
class PlayAlongScreen extends StatelessWidget {
  const PlayAlongScreen({
    super.key,
    required this.library,
    required this.eventId,
    this.cameras = listCameras,
    this.headTracking = HeadTracking.start,
    this.takeRecorder = TakeRecorder.forPlatform,
    this.linkFrame = linkFrameFor,
    this.pdfView = pdfViewFor,
    this.gate,
    this.ocr,
    this.sync,
  });

  final Library library;
  final String eventId;

  /// The time now, which names the takes ("Take 14:32"); tests set their
  /// own.
  @visibleForTesting
  static DateTime Function() now = DateTime.now;

  /// Set for a user without Premium: the screen is a preview, greyed out
  /// under the Premium card ([PremiumGate]). No camera opens, no key or
  /// tap does anything, and the tab along the bottom is the capture's, or
  /// a sample where it has none.
  final ({CloudOcr ocr, String? email})? gate;

  /// tabs.cam Premium, where the build has it, for a take edited in Cam
  /// (its watermark, as from the file screen).
  final CloudOcr? ocr;

  /// Cloud sync, for the editor's Share (a take's edit view's link).
  final CloudSync? sync;

  /// The cameras there are; tests pass their own.
  final Future<List<CameraDescription>> Function() cameras;

  /// Watches for head gestures; null where it can't. Tests pass their own.
  final HeadTracking? Function(
    CameraController camera,
    void Function(HeadGesture) onGesture,
  )
  headTracking;

  /// Records takes where the camera plugin doesn't (the web); null where
  /// it does. Tests pass their own.
  final TakeRecorder? Function() takeRecorder;

  /// Shows a link in the backing track's frame; tests pass their own.
  final Widget Function(LinkFrameController controller) linkFrame;

  /// Shows the PDF followed beside the camera; tests pass their own.
  final Widget Function(Library library, CaptureEvent event, EventPage page)
  pdfView;

  @override
  Widget build(BuildContext context) => StudioView(
    library: library,
    eventId: eventId,
    ocr: ocr,
    sync: sync,
    cam: CamSetup(
      cameras: cameras,
      headTracking: headTracking,
      takeRecorder: takeRecorder,
      linkFrame: linkFrame,
      pdfView: pdfView,
      // Read as each take is named: tests set their own as they go.
      now: () => now(),
      takeName: takeName,
      gate: gate,
    ),
  );
}
