import 'dart:async';
import 'dart:typed_data';

import 'package:cross_file/cross_file.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:tabcam_app/capture/video_edit.dart';
import 'package:tabcam_app/dictionary/dictionary_sidebar.dart';
import 'package:tabcam_app/export/download.dart';
import 'package:tabcam_app/l10n/app_localizations.dart';
import 'package:tabcam_app/library/capture_event.dart';
import 'package:tabcam_app/library/event_store_memory.dart';
import 'package:tabcam_app/library/library.dart';
import 'package:tabcam_app/metronome/metronome.dart';
import 'package:tabcam_app/screens/download_settings.dart';
import 'package:tabcam_app/screens/sidebar_widths.dart';
import 'package:tabcam_app/screens/video_edit_screen.dart';
import 'package:video_player_platform_interface/video_player_platform_interface.dart';

import 'video_edit_test.dart' show FakeEditor, VolumePlatform;

Duration s(double seconds) => Duration(milliseconds: (seconds * 1000).round());

/// An editor whose renders wait for [hold]: a Download in progress.
class _HeldEditor extends FakeEditor {
  final hold = Completer<void>();

  @override
  Future<XFile> render(
    RenderPlan plan, {
    void Function(double done)? onProgress,
  }) async {
    await hold.future;
    return super.render(plan, onProgress: onProgress);
  }
}

void main() {
  late VolumePlatform platform;
  setUp(() {
    VideoPlayerPlatform.instance = platform = VolumePlatform();
    VideoEditor.instance = FakeEditor();
    Downloads.save = (name, bytes, type) async => true;
  });
  tearDown(() {
    VideoEditor.instance = null;
    DownloadSettingsState.instance.reset();
    SidebarWidths.instance.clear();
    DictionaryState.instance.clear();
    MetronomeState.instance.close();
  });

  Future<void> frames(WidgetTester tester) async {
    for (var i = 0; i < 20; i++) {
      await tester.pump(const Duration(milliseconds: 50));
    }
  }

  /// Lets the view's players open (they do, off the test clock).
  Future<void> settle(WidgetTester tester) async {
    await tester.runAsync(
      () => Future<void>.delayed(const Duration(milliseconds: 100)),
    );
    await frames(tester);
  }

  /// A capture named [title] with a video (k0, named [first]), a
  /// recording (k1) and another video (k2, named [second]), kept edited
  /// to 0:10–0:20 when [secondEdit] is.
  Future<(Library, String)> capture(
    WidgetTester tester, {
    Library? into,
    String title = 'Made-up riffs',
    String first = 'First riff',
    String second = 'Second riff',
    PageEdit? secondEdit,
  }) async {
    final library =
        into ?? Library(PlatformEventStore(), null, (_) async => null);
    late String id;
    await tester.runAsync(() async {
      if (into == null) await library.load();
      var event = await library.create(const [], title: title);
      final pages = [
        EventPage(
          id: 'k0',
          kind: PageKind.video,
          extension: 'mp4',
          title: first,
        ),
        const EventPage(id: 'k1', kind: PageKind.audio, extension: 'm4a'),
        EventPage(
          id: 'k2',
          kind: PageKind.video,
          extension: 'mp4',
          title: second,
          edit: secondEdit,
        ),
      ];
      for (final page in pages) {
        await library.putPageStream(
          event.id,
          page,
          Stream.value(Uint8List.fromList([1, 2, 3])),
        );
      }
      event = event.copyWith(pages: pages);
      await library.update(event);
      id = event.id;
    });
    return (library, id);
  }

  Widget editScreen(Library library, String id, {VideoEditing? editor}) =>
      MaterialApp(
        localizationsDelegates: AppLocalizations.localizationsDelegates,
        supportedLocales: AppLocalizations.supportedLocales,
        home: VideoEditScreen(
          library: library,
          eventId: id,
          page: library.byId(id)!.pages.first,
          editor: editor,
          pickFile: () async => null,
        ),
      );

  void tall(WidgetTester tester) {
    tester.view.physicalSize = const Size(900, 1600);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);
  }

  /// Switches the view's main row to [page] ([StudioView.switchMain]),
  /// lets it open, and says whether it switched.
  Future<bool> switchTo(
    WidgetTester tester,
    EventPage? page, {
    String? eventId,
  }) async {
    bool? switched;
    unawaited(
      StudioView.switchMain(
        tester.state<State<StudioView>>(find.byType(StudioView)),
        page,
        eventId: eventId,
      ).then((done) => switched = done),
    );
    await settle(tester);
    await settle(tester);
    expect(switched, isNotNull, reason: 'the switch finished');
    return switched!;
  }

  EventPage pageOf(Library library, String id, String pageId) =>
      library.byId(id)!.pages.firstWhere((p) => p.id == pageId);

  /// The app bar's title.
  String? titleShown(WidgetTester tester) =>
      (tester.widget<AppBar>(find.byType(AppBar)).title as Text).data;

  group('the main row switched', () {
    testWidgets('from A to B: A\'s change still waiting is kept with A, B '
        'opens with its own edit, untouched, and B\'s changes are B\'s', (
      tester,
    ) async {
      tall(tester);
      final kept = PageEdit(start: s(10), end: s(20));
      final (library, id) = await capture(tester, secondEdit: kept);
      await tester.pumpWidget(editScreen(library, id));
      await settle(tester);
      expect(titleShown(tester), 'First riff');
      expect(find.text('Keep 0:00.0–3:00.0'), findsOneWidget);

      // Trimmed to where the player is, 12 s in; not kept yet.
      await tester.tap(find.byKey(const Key('video-edit-end-here')));
      await tester.pump();
      expect(find.text('Keep 0:00.0–0:12.0'), findsOneWidget);
      expect(pageOf(library, id, 'k0').edit, isNull);

      expect(await switchTo(tester, pageOf(library, id, 'k2')), isTrue);
      // A's change kept with A at once, as it went.
      expect(pageOf(library, id, 'k0').edit, PageEdit(start: s(0), end: s(12)));
      // B as it was kept: untouched, and shown.
      expect(pageOf(library, id, 'k2').edit, kept);
      expect(titleShown(tester), 'Second riff');
      expect(find.text('Keep 0:10.0–0:20.0'), findsOneWidget);
      expect(find.byKey(const Key('video-edit-preview')), findsOneWidget);
      // A's player let go of, B's its own.
      expect(platform.disposed, [0]);
      expect(platform.lastPlayer, 1);
      // Nothing of A's is B's: Reset is B's, the edit kept is B's.
      expect(
        tester
            .widget<ButtonStyleButton>(
              find.byKey(const Key('video-edit-reset')),
            )
            .enabled,
        isTrue,
      );

      // A change now is B's, kept with B; A's stays as it was kept.
      await tester.tap(find.byKey(const Key('video-edit-start-here')));
      await settle(tester);
      expect(find.text('Keep 0:12.0–0:20.0'), findsOneWidget);
      expect(
        pageOf(library, id, 'k2').edit,
        PageEdit(start: s(12), end: s(20)),
      );
      expect(pageOf(library, id, 'k0').edit, PageEdit(start: s(0), end: s(12)));
    });

    testWidgets('to another capture\'s page: the change waiting is kept '
        'with the first capture\'s, the next ones with the other\'s', (
      tester,
    ) async {
      tall(tester);
      final (library, id) = await capture(tester);
      final (_, other) = await capture(
        tester,
        into: library,
        title: 'Other riffs',
        first: 'Other riff',
      );
      await tester.pumpWidget(editScreen(library, id));
      await settle(tester);
      await tester.tap(find.byKey(const Key('video-edit-end-here')));
      await tester.pump();

      expect(
        await switchTo(tester, pageOf(library, other, 'k0'), eventId: other),
        isTrue,
      );
      expect(pageOf(library, id, 'k0').edit, PageEdit(start: s(0), end: s(12)));
      expect(pageOf(library, other, 'k0').edit, isNull);
      expect(titleShown(tester), 'Other riff');
      expect(find.text('Keep 0:00.0–3:00.0'), findsOneWidget);

      await tester.tap(find.byKey(const Key('video-edit-start-here')));
      await settle(tester);
      expect(
        pageOf(library, other, 'k0').edit,
        PageEdit(start: s(12), end: s(180)),
      );
      expect(pageOf(library, id, 'k0').edit, PageEdit(start: s(0), end: s(12)));
    });

    testWidgets('to none: no player opens and nothing spins; back to A, it '
        'opens again with the edit it was left with', (tester) async {
      tall(tester);
      final (library, id) = await capture(tester);
      await tester.pumpWidget(editScreen(library, id));
      await settle(tester);
      await tester.tap(find.byKey(const Key('video-edit-end-here')));
      await tester.pump();

      expect(await switchTo(tester, null), isTrue);
      expect(find.byType(CircularProgressIndicator), findsNothing);
      expect(find.byKey(const Key('video-edit-preview')), findsNothing);
      expect(find.byKey(const Key('video-edit-retry')), findsNothing);
      expect(find.byKey(const Key('video-edit-reset')), findsNothing);
      expect(platform.disposed, [0]);
      expect(platform.lastPlayer, 0);
      expect(pageOf(library, id, 'k0').edit, PageEdit(start: s(0), end: s(12)));
      // Nothing is kept from none.
      await settle(tester);
      expect(pageOf(library, id, 'k0').edit, PageEdit(start: s(0), end: s(12)));

      expect(await switchTo(tester, pageOf(library, id, 'k0')), isTrue);
      expect(titleShown(tester), 'First riff');
      expect(find.text('Keep 0:00.0–0:12.0'), findsOneWidget);
      expect(platform.lastPlayer, 1);
      expect(platform.disposed, [0]);
    });

    testWidgets('during a Download it doesn\'t switch', (tester) async {
      tall(tester);
      final (library, id) = await capture(tester);
      final editor = _HeldEditor();
      await tester.pumpWidget(editScreen(library, id, editor: editor));
      await settle(tester);
      await tester.tap(find.byKey(const Key('video-edit-download')));
      await settle(tester);
      expect(find.byKey(const Key('video-edit-progress')), findsOneWidget);

      expect(await switchTo(tester, pageOf(library, id, 'k2')), isFalse);
      expect(titleShown(tester), 'First riff');
      expect(platform.disposed, isEmpty);
      expect(platform.lastPlayer, 0);

      editor.hold.complete();
      await settle(tester);
      expect(find.byKey(const Key('video-edit-progress')), findsNothing);
      expect(editor.rendered, hasLength(1));
    });

    testWidgets('while the page before still opens: its player, once '
        'there, is let go of, and only the new page shows', (tester) async {
      tall(tester);
      final kept = PageEdit(start: s(10), end: s(20));
      final (library, id) = await capture(tester, secondEdit: kept);
      final hold = platform.createHold = Completer<void>();
      await tester.pumpWidget(editScreen(library, id));
      await settle(tester);
      expect(find.byType(CircularProgressIndicator), findsOneWidget);

      bool? switched;
      unawaited(
        StudioView.switchMain(
          tester.state<State<StudioView>>(find.byType(StudioView)),
          pageOf(library, id, 'k2'),
        ).then((done) => switched = done),
      );
      await settle(tester);
      expect(find.byType(CircularProgressIndicator), findsOneWidget);
      platform.createHold = null;
      hold.complete();
      await settle(tester);
      await settle(tester);
      expect(switched, isTrue);
      expect(titleShown(tester), 'Second riff');
      expect(find.text('Keep 0:10.0–0:20.0'), findsOneWidget);
      // Both players made; the first page's let go of as it came.
      expect(platform.lastPlayer, 1);
      expect(platform.disposed, hasLength(1));
      expect(pageOf(library, id, 'k0').edit, isNull);
      expect(pageOf(library, id, 'k2').edit, kept);
    });
  });
}
