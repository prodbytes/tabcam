import 'package:camera/camera.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:image/image.dart' as img;
import 'package:path_provider_platform_interface/path_provider_platform_interface.dart';
import 'package:plugin_platform_interface/plugin_platform_interface.dart';
import 'package:tabcam_app/capture/take_overlay.dart';

class _Paths extends PathProviderPlatform with MockPlatformInterfaceMixin {
  @override
  Future<String?> getTemporaryPath() async => '/tmp/tabcam-test';
}

Duration ms(int n) => Duration(milliseconds: n);

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  group('bandsOf', () {
    test('each neckline until the next', () {
      expect(bandsOf([(ms(0), 0), (ms(4000), 1), (ms(9000), 2)]), [
        TabBand(0, ms(0), ms(4000)),
        TabBand(1, ms(4000), ms(9000)),
        TabBand(2, ms(9000)),
      ]);
    });

    test('moved twice at once: only the last counts', () {
      expect(bandsOf([(ms(0), 0), (ms(3000), 1), (ms(3000), 2)]), [
        TabBand(0, ms(0), ms(3000)),
        TabBand(2, ms(3000)),
      ]);
    });

    test('back to the same neckline: one band', () {
      expect(bandsOf([(ms(0), 1), (ms(2000), 2), (ms(2000), 1)]), [
        TabBand(1, ms(0)),
      ]);
    });

    test('a take that never moved: one band', () {
      expect(bandsOf([(ms(0), 3)]), [TabBand(3, ms(0))]);
    });
  });

  testWidgets('a band is as wide as asked, a strip along the bottom', (
    tester,
  ) async {
    late img.Image band;
    await tester.runAsync(() async {
      band = img.decodePng(
        await renderBand('e|--0--3--|\nB|--1--1--|\nG|--2--0--|'),
      )!;
    });
    expect(band.width, bandWidth);
    expect(band.height, lessThan(band.width ~/ 2));
    expect(band.height, greaterThan(0));
  });

  test('burn hands the take and its bands to the platform', () async {
    PathProviderPlatform.instance = _Paths();
    const channel = MethodChannel('tabcam/take_overlay');
    MethodCall? call;
    final messenger =
        TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger;
    messenger.setMockMethodCallHandler(channel, (c) async {
      call = c;
      return (c.arguments as Map)['output'];
    });
    addTearDown(() => messenger.setMockMethodCallHandler(channel, null));

    final png = Uint8List.fromList([1, 2, 3]);
    final out = await TakeOverlay.burn(XFile('/tmp/take.mp4'), [
      (TabBand(0, ms(0), ms(1500)), png),
      (TabBand(1, ms(1500)), png),
    ]);
    expect(call!.method, 'burn');
    final args = call!.arguments as Map;
    expect(args['input'], '/tmp/take.mp4');
    expect(args['output'], startsWith('/tmp/tabcam-test/take-'));
    expect(args['bands'], [
      {'startMs': 0, 'endMs': 1500, 'png': png},
      {'startMs': 1500, 'endMs': null, 'png': png},
    ]);
    expect(out!.path, args['output']);

    // Failing, it gives nothing: the take is kept as it was.
    messenger.setMockMethodCallHandler(
      channel,
      (c) async => throw PlatformException(code: 'failed'),
    );
    expect(
      await TakeOverlay.burn(XFile('/tmp/take.mp4'), [
        (TabBand(0, ms(0)), png),
      ]),
      isNull,
    );
  });
}
