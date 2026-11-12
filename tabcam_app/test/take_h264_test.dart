import 'package:cross_file/cross_file.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:path_provider_platform_interface/path_provider_platform_interface.dart';
import 'package:plugin_platform_interface/plugin_platform_interface.dart';
import 'package:tabcam_app/capture/take_h264.dart';

class _Paths extends PathProviderPlatform with MockPlatformInterfaceMixin {
  @override
  Future<String?> getTemporaryPath() async => '/tmp/tabcam-test';
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  final messenger =
      TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger;
  late List<MethodCall> calls;
  late Object? Function(MethodCall) reply;

  setUp(() {
    calls = [];
    reply = (_) => null;
    messenger.setMockMethodCallHandler(TakeH264.channel, (call) async {
      calls.add(call);
      return switch (reply(call)) {
        final Exception e => throw e,
        final value => value,
      };
    });
  });
  tearDown(() {
    messenger.setMockMethodCallHandler(TakeH264.channel, null);
    debugDefaultTargetPlatformOverride = null;
  });

  final take = XFile('/tmp/take.mp4');

  test(
    'only on iOS: elsewhere nothing is asked, and nothing is to do',
    () async {
      debugDefaultTargetPlatformOverride = TargetPlatform.android;
      reply = (_) => 'hvc1';
      expect(await TakeH264.needed(take), isFalse);
      expect(calls, isEmpty);
    },
  );

  test('on iOS, only a take in another codec than H.264 is to be made '
      'H.264; one whose codec can\'t be told is kept as it is', () async {
    debugDefaultTargetPlatformOverride = TargetPlatform.iOS;
    reply = (_) => 'avc1';
    expect(await TakeH264.needed(take), isFalse);
    expect(calls.single.method, 'codec');
    expect(calls.single.arguments, {'input': '/tmp/take.mp4'});
    reply = (_) => 'hvc1';
    expect(await TakeH264.needed(take), isTrue);
    reply = (_) => null;
    expect(await TakeH264.needed(take), isFalse);
    reply = (_) => PlatformException(code: 'failed');
    expect(await TakeH264.needed(take), isFalse);
  });

  test('convert hands the take and a new MP4 to the platform', () async {
    PathProviderPlatform.instance = _Paths();
    reply = (call) => (call.arguments as Map)['output'];
    final made = await TakeH264.convert(take);
    expect(calls.single.method, 'h264');
    final args = calls.single.arguments as Map;
    expect(args['input'], '/tmp/take.mp4');
    expect(args['output'], startsWith('/tmp/tabcam-test/take-h264-'));
    expect(args['output'], endsWith('.mp4'));
    expect(made.path, args['output']);
    expect(made.mimeType, 'video/mp4');

    reply = (_) => PlatformException(code: 'failed', message: 'no export');
    await expectLater(
      TakeH264.convert(take),
      throwsA(isA<PlatformException>()),
    );
  });
}
