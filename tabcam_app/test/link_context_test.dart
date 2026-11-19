import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:tabcam_app/capture/video_edit.dart';
import 'package:tabcam_app/l10n/app_localizations.dart';
import 'package:tabcam_app/library/capture_event.dart';
import 'package:tabcam_app/library/event_store_memory.dart';
import 'package:tabcam_app/library/library.dart';
import 'package:tabcam_app/screens/event_screen.dart';
import 'package:tabcam_app/screens/file_screen.dart';
import 'package:tabcam_app/screens/place.dart';
import 'package:tabcam_app/screens/video_edit_screen.dart';
import 'package:video_player_platform_interface/video_player_platform_interface.dart';

import 'video_edit_test.dart' show FakeEditor, VolumePlatform;

/// Lets the screens open, load and settle (and the place be saved).
Future<void> settle(WidgetTester tester) async {
  await tester.runAsync(
    () => Future<void>.delayed(const Duration(milliseconds: 30)),
  );
  for (var i = 0; i < 12; i++) {
    await tester.pump(const Duration(milliseconds: 50));
  }
}

/// A link opens where it was shared from: the capture, the file over it,
/// or the video editor over the file; on a capture shared with the user,
/// the editor on their copy.
void main() {
  late Library library;
  late String id;
  String? copied;

  setUp(() {
    VideoPlayerPlatform.instance = VolumePlatform();
    VideoEditor.instance = FakeEditor();
    copied = null;
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(SystemChannels.platform, (call) async {
          if (call.method == 'Clipboard.setData') {
            copied = (call.arguments as Map)['text'] as String?;
          }
          return null;
        });
  });
  tearDown(() => VideoEditor.instance = null);

  /// A capture with a video (k0, "Made-up riff") and an image (k1); shared
  /// with the user, read only, when [shared].
  Future<void> capture(WidgetTester tester, {bool shared = false}) async {
    library = Library(PlatformEventStore(), null, (_) async => null);
    await tester.runAsync(() async {
      await library.load();
      var event = await library.create(const []);
      for (final (i, (kind, ext)) in [
        (PageKind.video, 'mp4'),
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
      if (shared) {
        event = event.copyWith(sharedBy: 'owner@example.com', readOnly: true);
      }
      await library.update(event);
      id = event.id;
    });
  }

  /// The capture's screen, opened as a link (or a reload) opens it: on
  /// [file], and with [edit] the editor over it.
  Future<void> show(WidgetTester tester, {String? file, bool edit = false}) async {
    tester.view.physicalSize = const Size(900, 1600);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);
    PlaceMemory.of(library).update(
      (p) => p.copyWith(eventId: () => id, fileId: () => file, edit: edit),
    );
    await tester.pumpWidget(
      MaterialApp(
        localizationsDelegates: AppLocalizations.localizationsDelegates,
        supportedLocales: AppLocalizations.supportedLocales,
        home: EventScreen(
          library: library,
          eventId: id,
          initialFile: file,
          initialEdit: edit,
        ),
      ),
    );
    await settle(tester);
  }

  testWidgets("a link to a file's edit view opens the editor over the file; "
      'the place remembers it while it is open', (tester) async {
    await capture(tester);
    await show(tester, file: 'k0', edit: true);
    expect(find.byType(FileScreen, skipOffstage: false), findsOneWidget);
    expect(find.byType(VideoEditScreen), findsOneWidget);
    expect(PlaceMemory.of(library).place.edit, isTrue);
    expect(PlaceMemory.of(library).place.fileId, 'k0');
    // Back: the file, the editor forgotten.
    await tester.pageBack();
    await settle(tester);
    expect(find.byType(VideoEditScreen), findsNothing);
    expect(find.byType(FileScreen), findsOneWidget);
    expect(PlaceMemory.of(library).place.edit, isFalse);
    expect(PlaceMemory.of(library).place.fileId, 'k0');
  });

  testWidgets("an image's edit view is just the file", (tester) async {
    await capture(tester);
    await show(tester, file: 'k1', edit: true);
    expect(find.byType(FileScreen), findsOneWidget);
    expect(find.byType(VideoEditScreen), findsNothing);
    expect(PlaceMemory.of(library).place.edit, isFalse);
  });

  testWidgets('on a capture shared with the user, the edit view opens on '
      "their copy, over the copy's page of the file", (tester) async {
    await capture(tester, shared: true);
    await show(tester, file: 'k0', edit: true);
    final copy = library.copyOf(id);
    expect(copy, isNotNull);
    expect(find.byType(VideoEditScreen), findsOneWidget);
    final editor = tester.widget<VideoEditScreen>(
      find.byType(VideoEditScreen),
    );
    expect(editor.eventId, copy!.id);
    expect(editor.page.source, FileOrigin(id, 'k0'));
    expect(PlaceMemory.of(library).place.eventId, copy.id);
    expect(PlaceMemory.of(library).place.fileId, editor.page.id);
    expect(PlaceMemory.of(library).place.edit, isTrue);
  });

  testWidgets("Share on the file screen copies the file's link; in the "
      "editor, the file's edit view's", (tester) async {
    await capture(tester);
    await show(tester, file: 'k0');
    expect(find.byType(FileScreen), findsOneWidget);
    await tester.tap(find.byKey(const Key('share-file')));
    await settle(tester);
    expect(copied, endsWith('/app/?c=$id&f=k0'));
    await tester.tap(find.byKey(const Key('edit-video')));
    await settle(tester);
    expect(find.byType(VideoEditScreen), findsOneWidget);
    await tester.tap(find.byKey(const Key('video-edit-share')));
    await settle(tester);
    expect(copied, endsWith('/app/?c=$id&f=k0&e=1'));
  });
}
