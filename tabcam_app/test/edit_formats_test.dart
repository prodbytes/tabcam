import 'package:flutter_test/flutter_test.dart';
import 'package:tabcam_app/capture/edit_formats.dart';
import 'package:tabcam_app/capture/video_edit.dart';

void main() {
  group('the browser records a video as', () {
    test('MP4, H.264 and AAC, where it can (Chrome, Edge, Safari)', () {
      expect(
        videoRecorderType((_) => true),
        'video/mp4;codecs=avc1.42E01E,mp4a.40.2',
      );
    });

    test('MP4 with a simpler type, where only that one records', () {
      expect(
        videoRecorderType((t) => t == 'video/mp4;codecs=avc1,mp4a.40.2'),
        'video/mp4;codecs=avc1,mp4a.40.2',
      );
      expect(
        videoRecorderType(
          (t) => t == 'video/mp4' || t.startsWith('video/webm'),
        ),
        'video/mp4',
      );
    });

    test('WebM only where MP4 can\'t be recorded (Firefox)', () {
      expect(
        videoRecorderType((t) => t.startsWith('video/webm')),
        'video/webm;codecs=vp9,opus',
      );
      expect(videoRecorderType((t) => t == 'video/webm'), 'video/webm');
      expect(videoRecorderType((_) => false), isNull);
    });

    test('every MP4 type before any WebM', () {
      final firstWebm = videoRecorderTypes.indexWhere(
        (t) => t.startsWith('video/webm'),
      );
      expect(
        videoRecorderTypes.skip(firstWebm).any((t) => t.contains('mp4')),
        isFalse,
      );
      expect(firstWebm, greaterThan(0));
    });
  });

  test('a recorded file is named by its format', () {
    for (final (mime, format) in [
      ('video/mp4;codecs=avc1.420028,mp4a.40.2', EditFormat.mp4),
      ('video/mp4', EditFormat.mp4),
      ('Video/MP4', EditFormat.mp4),
      ('video/webm;codecs=vp9,opus', EditFormat.webm),
      ('video/x-matroska;codecs=avc1', EditFormat.webm),
      ('', EditFormat.webm),
    ]) {
      expect(EditFormat.recorded(mime), format, reason: mime);
    }
  });

  test('formats: their labels, extensions and MIME types', () {
    expect(
      [for (final f in EditFormat.values) (f.label, f.extension, f.mimeType)],
      [
        ('MP4', 'mp4', 'video/mp4'),
        ('WebM', 'webm', 'video/webm'),
        ('M4A', 'm4a', 'audio/mp4'),
        ('WAV', 'wav', 'audio/wav'),
      ],
    );
    expect(EditFormats.standard.video, EditFormat.mp4);
    expect(EditFormats.standard.sound, EditFormat.m4a);
  });

  test('the sound alone: AAC by the encoder, else by the recorder, else a '
      'WAV', () {
    expect(
      WebSoundWay.best(encoder: true, recorder: true),
      WebSoundWay.encoder,
    );
    expect(
      WebSoundWay.best(encoder: true, recorder: false),
      WebSoundWay.encoder,
    );
    expect(
      WebSoundWay.best(encoder: false, recorder: true),
      WebSoundWay.recorder,
    );
    expect(WebSoundWay.best(encoder: false, recorder: false), WebSoundWay.wav);
    expect(WebSoundWay.encoder.format, EditFormat.m4a);
    expect(WebSoundWay.recorder.format, EditFormat.m4a);
    expect(WebSoundWay.wav.format, EditFormat.wav);
    expect(soundRecorderType, 'audio/mp4;codecs=mp4a.40.2');
  });

  test('an unchanged video downloads as it is when it\'s MPEG-4 or in the '
      'format made here', () {
    const webm = EditFormats(video: EditFormat.webm, sound: EditFormat.wav);
    for (final (extension, standard, firefox) in [
      ('mp4', true, true),
      ('MP4', true, true),
      ('m4v', true, true),
      ('webm', false, true),
      ('mov', false, false),
      (null, false, false),
    ]) {
      expect(
        EditFormats.standard.keepsAsIs(extension),
        standard,
        reason: '$extension',
      );
      expect(webm.keepsAsIs(extension), firefox, reason: '$extension');
    }
  });

  test('the phones make MP4, and M4A for the sound alone', () async {
    expect(await const ChannelVideoEditor().formats(), EditFormats.standard);
  });
}
