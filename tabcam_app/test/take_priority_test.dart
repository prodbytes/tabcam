import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:tabcam_app/capture/take_priority.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  test('the web\'s microphone has none of the processing for voice calls', () {
    const mic = TakePriority.webMicConstraints;
    expect(mic['echoCancellation'], isFalse);
    expect(mic['noiseSuppression'], isFalse);
    expect(mic['autoGainControl'], isFalse);
    expect(mic['voiceIsolation'], isFalse);
    // Asked for, not required: a mono microphone still opens.
    expect(mic['channelCount'], {'ideal': 2});
    expect(mic['sampleRate'], {'ideal': 48000});
  });

  test('the web\'s take: a bitrate for music, VP8 before VP9', () {
    expect(TakePriority.webAudioBitrate, greaterThanOrEqualTo(128000));
    final types = TakePriority.webTypes;
    expect(
      types.indexOf('video/webm;codecs=vp8,opus'),
      lessThan(types.indexOf('video/webm;codecs=vp9,opus')),
    );
    // Safari records MP4 only.
    expect(types, contains('video/mp4'));
  });

  test('the tab is drawn into the web\'s take at the camera\'s rate, '
      'whatever the display\'s', () {
    int drawn(double hz) {
      num? last;
      var n = 0;
      for (var i = 0; i < hz; i++) {
        final now = i * 1000 / hz;
        if (TakePriority.frameDue(last, now)) {
          last = now;
          n++;
        }
      }
      return n; // in one second
    }

    expect(drawn(60), 30);
    expect(drawn(120), 30);
    expect(drawn(144), inInclusiveRange(28, 36));
    // A display slower than the camera: every frame.
    expect(drawn(30), 30);
    expect(drawn(24), 24);
  });

  test('head gestures look less often while a take records', () {
    expect(
      TakePriority.headIntervalRecording,
      greaterThan(TakePriority.headInterval),
    );
    // Still several looks in a nod (out and back within a second).
    expect(
      TakePriority.headIntervalRecording,
      lessThanOrEqualTo(const Duration(milliseconds: 200)),
    );
  });

  group('the iOS audio session', () {
    final calls = <String>[];
    setUp(() {
      calls.clear();
      TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
          .setMockMethodCallHandler(TakeAudio.channel, (call) async {
            calls.add(call.method);
            return null;
          });
    });
    tearDown(() {
      TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
          .setMockMethodCallHandler(TakeAudio.channel, null);
      debugDefaultTargetPlatformOverride = null;
    });

    test('is set on iOS', () async {
      debugDefaultTargetPlatformOverride = TargetPlatform.iOS;
      await TakeAudio.prepare();
      await TakeAudio.release();
      expect(calls, ['prepare', 'release']);
    });

    test('is left alone elsewhere', () async {
      debugDefaultTargetPlatformOverride = TargetPlatform.android;
      await TakeAudio.prepare();
      await TakeAudio.release();
      expect(calls, isEmpty);
    });

    test('failing, it only logs', () async {
      debugDefaultTargetPlatformOverride = TargetPlatform.iOS;
      TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
          .setMockMethodCallHandler(
            TakeAudio.channel,
            (call) async => throw PlatformException(code: 'failed'),
          );
      await TakeAudio.prepare();
    });
  });
}
