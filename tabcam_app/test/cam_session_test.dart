import 'package:flutter_test/flutter_test.dart';
import 'package:tabcam_app/capture/cam_session.dart';
import 'package:tabcam_app/library/event_store_memory.dart';
import 'package:tabcam_app/library/library.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  /// A session on a new capture, in a preview (no camera, no sound), with
  /// what its play-along opens on.
  Future<CamSession> session({
    String? startId,
    bool opensByItself = true,
  }) async {
    final library = Library(PlatformEventStore(), null, (_) async => null);
    await library.load();
    final event = await library.create(const []);
    return CamSession(
      library: library,
      eventId: event.id,
      cameras: () async => const [],
      headTracking: (_, _) => null,
      takeRecorder: () => null,
      now: DateTime.now,
      takeName: (started) => 'Take',
      onNote: (_, [_]) {},
      gated: true,
      startId: startId,
      opensByItself: opensByItself,
    );
  }

  test('the play-along opens by itself on the first file to play, '
      'unless told otherwise', () async {
    final cam = await session();
    expect(cam.along.startId, isNull);
    expect(cam.along.opensByItself, isTrue);
    cam.dispose();
  });

  test('the play-along opens on the file it is handed, and stays '
      'closed when told to', () async {
    final cam = await session(startId: 'riff', opensByItself: false);
    expect(cam.along.startId, 'riff');
    expect(cam.along.opensByItself, isFalse);
    cam.dispose();
  });
}
