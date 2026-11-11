import 'package:camera/camera.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:tabcam_app/capture/take_priority.dart';
import 'package:tabcam_app/capture/take_sound.dart';

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

  group('Android\'s take sound', () {
    final calls = <MethodCall>[];
    Object? Function(MethodCall call) reply = (_) => null;
    setUp(() {
      calls.clear();
      reply = (_) => null;
      TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
          .setMockMethodCallHandler(TakeSound.channel, (call) async {
            calls.add(call);
            return reply(call);
          });
    });
    tearDown(() {
      TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
          .setMockMethodCallHandler(TakeSound.channel, null);
      debugDefaultTargetPlatformOverride = null;
    });

    test('is the app\'s on Android only', () async {
      debugDefaultTargetPlatformOverride = TargetPlatform.iOS;
      expect(TakeSound.supported, isFalse);
      expect(await TakeSound.prepare(), TakeSoundReady.unavailable);
      await TakeSound.release();
      expect(calls, isEmpty);
      debugDefaultTargetPlatformOverride = TargetPlatform.android;
      expect(TakeSound.supported, isTrue);
    });

    test('prepared: whether the microphone opened; refused or failing, '
        'the camera records the sound', () async {
      debugDefaultTargetPlatformOverride = TargetPlatform.android;
      reply = (_) => {'ok': true, 'source': 'unprocessed'};
      expect(await TakeSound.prepare(), TakeSoundReady.ok);
      reply = (_) => {
        'ok': false,
        'reason': 'The microphone isn\'t allowed',
        'refused': true,
      };
      expect(await TakeSound.prepare(), TakeSoundReady.refused);
      // Asked again without asking the user.
      expect(await TakeSound.prepare(ask: false), TakeSoundReady.refused);
      reply = (_) => {'ok': false, 'reason': 'No microphone could be opened'};
      expect(await TakeSound.prepare(), TakeSoundReady.unavailable);
      reply = (_) => throw PlatformException(code: 'failed');
      expect(await TakeSound.prepare(), TakeSoundReady.unavailable);
      expect(
        [for (final c in calls) c.method],
        ['prepare', 'prepare', 'prepare', 'prepare', 'prepare'],
      );
      expect(
        [for (final c in calls) c.arguments],
        [
          {'ask': true},
          {'ask': true},
          {'ask': false},
          {'ask': true},
          {'ask': true},
        ],
      );
    });

    test(
      'stopped: the take with its sound, or the video and why not',
      () async {
        debugDefaultTargetPlatformOverride = TargetPlatform.android;
        final video = XFile('/cache/REC_1.mp4');
        reply = (_) => {'path': '/cache/take-1.mp4', 'leadMs': 300.0};
        var r = await TakeSound.stop(video);
        expect(calls.single.arguments, {'video': '/cache/REC_1.mp4'});
        expect(r.take.path, '/cache/take-1.mp4');
        expect(r.take.mimeType, 'video/mp4');
        expect(r.error, isNull);
        expect(r.warning, isNull);

        reply = (_) => {'path': '/cache/take-2.mp4', 'warning': 'silence'};
        r = await TakeSound.stop(video);
        expect(r.take.path, '/cache/take-2.mp4');
        expect(r.warning, 'silence');

        reply = (_) =>
            throw PlatformException(code: 'failed', message: 'No sound');
        r = await TakeSound.stop(video);
        expect(r.take, same(video));
        expect(r.error, 'No sound');
      },
    );

    test('start fails loudly; the rest only log', () async {
      debugDefaultTargetPlatformOverride = TargetPlatform.android;
      reply = (_) => throw PlatformException(code: 'failed');
      await expectLater(TakeSound.start(), throwsA(isA<PlatformException>()));
      await TakeSound.videoStarted();
      await TakeSound.videoStopping();
      await TakeSound.cancel();
      await TakeSound.release();
      expect(
        [for (final c in calls) c.method],
        ['start', 'videoStarted', 'videoStopping', 'cancel', 'release'],
      );
    });
  });
}
