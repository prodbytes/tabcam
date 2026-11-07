import 'dart:typed_data';

import 'package:cross_file/cross_file.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:tabcam_app/capture/video_edit.dart';
import 'package:tabcam_app/l10n/app_localizations.dart';
import 'package:tabcam_app/library/capture_event.dart';
import 'package:tabcam_app/library/event_store_memory.dart';
import 'package:tabcam_app/library/library.dart';
import 'package:tabcam_app/screens/file_screen.dart';
import 'package:tabcam_app/screens/video_edit_screen.dart';
import 'package:video_player_platform_interface/video_player_platform_interface.dart';

import 'mini_player_test.dart' show FakeVideoPlatform;

/// An editor that records what it's asked and hands back a small WebM.
class FakeEditor implements VideoEditing {
  final applied = <(XFile, VideoEdit)>[];

  @override
  Future<Duration?> length(XFile file) async => null;

  @override
  Future<XFile> apply(
    XFile video,
    VideoEdit edit, {
    void Function(double done)? onProgress,
  }) async {
    applied.add((video, edit));
    onProgress?.call(0.5);
    return XFile.fromData(
      Uint8List.fromList([9, 9, 9]),
      name: 'edit.webm',
      mimeType: 'video/webm',
    );
  }
}

Duration s(double seconds) => Duration(milliseconds: (seconds * 1000).round());

Future<void> _frames(WidgetTester tester) async {
  for (var i = 0; i < 20; i++) {
    await tester.pump(const Duration(milliseconds: 50));
  }
}

/// Lets the screens' players open (they do, off the test clock).
Future<void> _settle(WidgetTester tester) async {
  await tester.runAsync(
    () => Future<void>.delayed(const Duration(milliseconds: 100)),
  );
  await _frames(tester);
}

void main() {
  group('trackSpan', () {
    test('a track starting with the clip, cut to the clip', () {
      expect(trackSpan(s(10), s(4), Duration.zero), (
        gap: Duration.zero,
        from: Duration.zero,
        to: s(4),
      ));
      expect(trackSpan(s(10), s(20), Duration.zero), (
        gap: Duration.zero,
        from: Duration.zero,
        to: s(10),
      ));
    });

    test('a track starting later: silence first, then what fits', () {
      expect(trackSpan(s(10), s(4), s(3)), (
        gap: s(3),
        from: Duration.zero,
        to: s(4),
      ));
      expect(trackSpan(s(10), s(4), s(8)), (
        gap: s(8),
        from: Duration.zero,
        to: s(2),
      ));
    });

    test('a track starting earlier: its start is cut', () {
      expect(trackSpan(s(10), s(4), s(-1)), (
        gap: Duration.zero,
        from: s(1),
        to: s(4),
      ));
      expect(trackSpan(s(2), s(4), s(-1)), (
        gap: Duration.zero,
        from: s(1),
        to: s(3),
      ));
    });

    test('a track outside the clip is nothing', () {
      expect(trackSpan(s(10), s(4), s(10)), isNull);
      expect(trackSpan(s(10), s(4), s(-4)), isNull);
      expect(trackSpan(Duration.zero, s(4), Duration.zero), isNull);
    });
  });

  late FakeVideoPlatform platform;
  late FakeEditor editor;
  setUp(() {
    VideoPlayerPlatform.instance = platform = FakeVideoPlatform();
    VideoEditor.instance = editor = FakeEditor();
  });
  tearDown(() => VideoEditor.instance = null);

  /// A capture with a video (k0), a recording (k1) and an image (k2).
  Future<(Library, String)> capture(WidgetTester tester) async {
    final library = Library(PlatformEventStore(), null, (_) async => null);
    late String id;
    await tester.runAsync(() async {
      await library.load();
      var event = await library.create(const []);
      for (final (i, (kind, ext)) in [
        (PageKind.video, 'mp4'),
        (PageKind.audio, 'm4a'),
        (PageKind.image, 'jpg'),
      ].indexed) {
        final page = EventPage(
          id: 'k$i',
          kind: kind,
          extension: ext,
          title: i == 0 ? 'Made-up riff' : null,
        );
        await library.putPageStream(
          event.id,
          page,
          Stream.value(Uint8List.fromList([1, 2, 3])),
        );
        event = event.copyWith(pages: [...event.pages, page]);
      }
      await library.update(event);
      id = event.id;
    });
    return (library, id);
  }

  /// A tall phone, so the edit screen's controls are all on it.
  void tall(WidgetTester tester) {
    tester.view.physicalSize = const Size(900, 1600);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);
  }

  Widget host(Widget home) => MaterialApp(
    localizationsDelegates: AppLocalizations.localizationsDelegates,
    supportedLocales: AppLocalizations.supportedLocales,
    home: home,
  );

  testWidgets('Edit is a video\'s tool, not an image\'s; it opens the '
      'editor with the whole video kept and nothing to save', (tester) async {
    tall(tester);
    final (library, id) = await capture(tester);
    await tester.pumpWidget(
      host(
        FileScreen(
          key: const Key('k2'),
          library: library,
          eventId: id,
          pageId: 'k2',
        ),
      ),
    );
    await _settle(tester);
    expect(find.byKey(const Key('edit-video')), findsNothing);

    await tester.pumpWidget(
      host(
        FileScreen(
          key: const Key('k0'),
          library: library,
          eventId: id,
          pageId: 'k0',
        ),
      ),
    );
    await _settle(tester);
    expect(find.byKey(const Key('edit-video')), findsOneWidget);
    await tester.tap(find.byKey(const Key('edit-video')));
    await _settle(tester);
    expect(find.byType(VideoEditScreen), findsOneWidget);
    expect(find.text('Made-up riff'), findsOneWidget);
    expect(find.text('Keep 0:00.0–3:00.0'), findsOneWidget);
    expect(
      tester
          .widget<FilledButton>(find.byKey(const Key('video-edit-save')))
          .enabled,
      isFalse,
    );
    // Nothing plays until asked.
    expect(platform.playing, isEmpty);

    // Cancel goes back to the file, as it was.
    await tester.tap(find.byKey(const Key('video-edit-cancel')));
    await _settle(tester);
    expect(find.byType(VideoEditScreen), findsNothing);
    expect(find.byType(FileScreen), findsOneWidget);
    expect(library.byId(id)!.pages.first.id, 'k0');
  });

  testWidgets('End here trims to where the preview is; Save applies the '
      'edit on the device and puts the result in the video\'s place, with '
      'its name', (tester) async {
    tall(tester);
    final (library, id) = await capture(tester);
    await tester.pumpWidget(
      host(FileScreen(library: library, eventId: id, pageId: 'k0')),
    );
    await _settle(tester);
    await tester.tap(find.byKey(const Key('edit-video')));
    await _settle(tester);

    // The preview is 12 s in (the fake's position).
    await tester.tap(find.byKey(const Key('video-edit-end-here')));
    await _settle(tester);
    expect(find.text('Keep 0:00.0–0:12.0'), findsOneWidget);
    final save = find.byKey(const Key('video-edit-save'));
    expect(tester.widget<FilledButton>(save).enabled, isTrue);

    await tester.tap(save);
    await _settle(tester);
    final (input, edit) = editor.applied.single;
    expect(await tester.runAsync(input.readAsBytes), [1, 2, 3]);
    expect(edit.start, Duration.zero);
    expect(edit.end, s(12));
    expect(edit.sound, EditSound.original);

    // A new page in its place: the same name, the editor's format; the old
    // file gone; the file screen shows the new one.
    final event = library.byId(id)!;
    final replaced = event.pages.first;
    expect(replaced.id, isNot('k0'));
    expect(replaced.kind, PageKind.video);
    expect(replaced.extension, 'webm');
    expect(replaced.title, 'Made-up riff');
    expect(event.pages.map((p) => p.id).skip(1), ['k1', 'k2']);
    expect(await tester.runAsync(() => library.hasPage(id, replaced)), isTrue);
    expect(
      await tester.runAsync(
        () => library.hasPage(id, const EventPage(id: 'k0', extension: 'mp4')),
      ),
      isFalse,
    );
    expect(find.byType(VideoEditScreen), findsNothing);
    expect(find.byType(FileScreen), findsOneWidget);
    expect(find.text('Made-up riff'), findsOneWidget);
  });

  testWidgets('the sound: None, or a new track from the capture\'s '
      'recordings, shifted along the video', (tester) async {
    tall(tester);
    final (library, id) = await capture(tester);
    await tester.pumpWidget(
      host(
        VideoEditScreen(
          library: library,
          eventId: id,
          page: library.byId(id)!.pages.first,
          pickFile: () async => null,
        ),
      ),
    );
    await _settle(tester);
    final save = find.byKey(const Key('video-edit-save'));
    expect(tester.widget<FilledButton>(save).enabled, isFalse);

    // None: something to save.
    await tester.tap(find.text('None'));
    await _frames(tester);
    expect(tester.widget<FilledButton>(save).enabled, isTrue);
    expect(find.byKey(const Key('video-edit-track')), findsNothing);

    // New track: the sheet lists the recording (not the image or the
    // video), and a sound file.
    await tester.tap(find.text('New track'));
    await _settle(tester);
    expect(find.byKey(const Key('video-edit-tracks')), findsOneWidget);
    expect(find.byKey(const Key('video-edit-track-k1')), findsOneWidget);
    expect(find.byKey(const Key('video-edit-track-k2')), findsNothing);
    expect(find.byKey(const Key('video-edit-track-k0')), findsNothing);
    expect(find.byKey(const Key('video-edit-track-file')), findsOneWidget);
    await tester.tap(find.byKey(const Key('video-edit-track-k1')));
    await _settle(tester);
    expect(find.byKey(const Key('video-edit-tracks')), findsNothing);
    expect(find.text('Recording 1'), findsOneWidget);
    expect(find.text('The track starts with the video'), findsOneWidget);

    // Shifted later: the slider runs from the track's length before the
    // video to the kept part's end.
    final slider = find.byKey(const Key('video-edit-offset'));
    expect(slider, findsOneWidget);
    expect(tester.widget<Slider>(slider).min, -s(180).inMilliseconds);
    expect(tester.widget<Slider>(slider).max, s(180).inMilliseconds);
    await tester.drag(slider, const Offset(40, 0));
    await _frames(tester);
    expect(find.textContaining('after the video'), findsOneWidget);

    await tester.tap(save);
    await _settle(tester);
    final (_, edit) = editor.applied.single;
    expect(edit.sound, EditSound.track);
    expect(await tester.runAsync(edit.track!.readAsBytes), [1, 2, 3]);
    expect(edit.offset, greaterThan(Duration.zero));
    expect(edit.start, Duration.zero);
    expect(edit.end, s(180));
  });
}
