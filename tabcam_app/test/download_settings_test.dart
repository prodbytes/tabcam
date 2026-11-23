import 'dart:async';
import 'dart:math';

import 'package:cross_file/cross_file.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:tabcam_app/capture/take_log.dart';
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
import 'package:tabcam_app/screens/split_handle.dart';
import 'package:tabcam_app/screens/video_edit_screen.dart';
import 'package:video_player_platform_interface/video_player_platform_interface.dart';

import 'video_edit_test.dart' show FakeEditor, VolumePlatform;

/// Made-up riffs for the take's tab.
const _riffA = 'e|--3--5--7--|';
const _riffB = 'e|--5--7--8--|';

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
  // A tap that would land on something else (under the dock, off the
  // list) fails the test rather than warning.
  WidgetController.hitTestWarningShouldBeFatal = true;
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

  /// Lets the editor's players open (they do, off the test clock).
  Future<void> settle(WidgetTester tester) async {
    await tester.runAsync(
      () => Future<void>.delayed(const Duration(milliseconds: 100)),
    );
    await frames(tester);
  }

  /// A capture named "Blue Riff" with one of Cam's takes (k0), its tab
  /// kept apart from its picture, and a recording (k1): with [song], the
  /// take played along with it, lined up from the take's log.
  Future<(Library, String)> capture(
    WidgetTester tester, {
    bool song = false,
  }) async {
    final library = Library(PlatformEventStore(), null, (_) async => null);
    late String id;
    await tester.runAsync(() async {
      await library.load();
      var event = await library.create(const [], title: 'Blue Riff');
      final pages = [
        EventPage(
          id: 'k0',
          kind: PageKind.video,
          extension: 'mp4',
          title: 'Take 1',
          take: true,
          takeLog: TakeLog(
            burned: false,
            song: [
              if (song)
                const SongSegment(at: 1000, to: 31000, page: 'k1', from: 0),
            ],
            tab: TakeTab(
              lines: const [_riffA, _riffB],
              marks: const [(0, 0), (4210, 1), (8380, 0)],
            ),
          ),
        ),
        const EventPage(id: 'k1', kind: PageKind.audio, extension: 'm4a'),
      ];
      for (final page in pages) {
        await library.putPageStream(
          event.id,
          page,
          Stream.value(Uint8List.fromList([1, 2, 3])),
        );
      }
      event = event.copyWith(pages: pages, tabText: '$_riffA\n\n$_riffB');
      await library.update(event);
      id = event.id;
    });
    return (library, id);
  }

  void sized(WidgetTester tester, Size size, {double text = 1}) {
    tester.view.physicalSize = size;
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);
    if (text != 1) {
      tester.platformDispatcher.textScaleFactorTestValue = text;
      addTearDown(tester.platformDispatcher.clearTextScaleFactorTestValue);
    }
  }

  Widget editScreen(
    Library library,
    String id, {
    Locale? locale,
    VideoEditing? editor,
  }) => MaterialApp(
    locale: locale,
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

  Future<(Library, String)> open(WidgetTester tester, Size size) async {
    sized(tester, size);
    final (library, id) = await capture(tester);
    await tester.pumpWidget(editScreen(library, id));
    await settle(tester);
    expect(tester.takeException(), isNull);
    return (library, id);
  }

  final settings = find.byKey(const Key('video-edit-settings-panel'));
  final button = find.byKey(const Key('video-edit-settings'));
  final close = find.byKey(const Key('sidebar-close'));
  final split = find.byKey(const Key('video-edit-settings-split'));
  final preview = find.byKey(const Key('video-edit-preview'));
  final side = find.byKey(const Key('video-edit-side'));

  /// The viewer's box: the black around the picture, as large as it gets.
  Rect viewer(WidgetTester tester) => tester.getRect(
    find.ancestor(of: preview, matching: find.byType(Center)).first,
  );

  bool selected(WidgetTester tester) =>
      tester.widget<IconButton>(button).isSelected ?? false;

  /// Whether [key] shows within the Download settings' list (scrolled
  /// into view, not under its edge).
  bool inView(WidgetTester tester, String key) {
    final list = tester.getRect(
      find.descendant(of: settings, matching: find.byType(Scrollable)).first,
    );
    final shown = tester.getRect(find.byKey(Key(key)));
    return shown.top >= list.top - 0.5 && shown.top < list.bottom;
  }

  testWidgets('on a phone, the sidebar is hidden as the editor opens, the '
      'editor having the width; the Download settings button shows it, its '
      'Download tab alone, at the right, the editor cut at its edge; '
      'pressed again, or its ✕, hides it', (tester) async {
    await open(tester, const Size(390, 844));
    expect(settings, findsNothing);
    expect(side, findsNothing);
    expect(selected(tester), isFalse);
    expect(tester.widget<IconButton>(button).tooltip, 'Download settings');
    final alone = viewer(tester);
    expect(alone.width, 390);

    await tester.tap(button);
    await frames(tester);
    expect(settings, findsOneWidget);
    expect(selected(tester), isTrue);
    expect(
      tester.widget<IconButton>(button).tooltip,
      'Hide the download settings',
    );
    // Its tabs: Download alone (nothing to play along with here), its
    // name a tooltip in a sidebar this narrow.
    expect(find.byKey(const Key('sidebar-tab-download')), findsOneWidget);
    expect(find.byKey(const Key('sidebar-tab-playAlong')), findsNothing);
    expect(
      find.descendant(of: settings, matching: find.byTooltip('Download')),
      findsOneWidget,
    );
    // At the right, at its least; the editor laid out as wide as a small
    // phone, cut at its edge, not squeezed.
    final sidebar = tester.getRect(settings);
    expect(sidebar.right, 390);
    expect(sidebar.width, DownloadSidebarBeside.minWidth);
    expect(tester.getRect(split).right, sidebar.left);
    expect(viewer(tester).width, 360);
    // Its content: the master, On the video.
    for (final key in ['video-edit-master', 'video-edit-on-video']) {
      expect(
        find.descendant(of: settings, matching: find.byKey(Key(key))),
        findsOneWidget,
        reason: key,
      );
    }
    expect(tester.takeException(), isNull);

    await tester.tap(button);
    await frames(tester);
    expect(settings, findsNothing);
    expect(find.byKey(const Key('video-edit-master')), findsNothing);
    expect(selected(tester), isFalse);
    expect(viewer(tester), alone);
    // The transport and the lanes stay where they were.
    expect(find.byKey(const Key('video-edit-take-bar')), findsOneWidget);

    await tester.tap(button);
    await frames(tester);
    expect(settings, findsOneWidget);
    await tester.tap(close);
    await frames(tester);
    expect(settings, findsNothing);
    expect(DownloadSettingsState.instance.open, isFalse);
    expect(viewer(tester), alone);
    expect(tester.takeException(), isNull);
  });

  testWidgets('on a wide screen the sidebar is beside the editor, on its '
      'Download tab, as it opens; hidden, the picture grows into its room', (
    tester,
  ) async {
    await open(tester, const Size(900, 1600));
    expect(side, findsOneWidget);
    final sidebar = tester.getRect(settings);
    expect(sidebar.width, 360);
    expect(sidebar.right, 900);
    expect(tester.getRect(split).right, sidebar.left);
    // Wide enough for the tab's name beside its icon.
    expect(
      find.descendant(of: settings, matching: find.text('Download')),
      findsOneWidget,
    );
    final picture = tester.getRect(preview);
    expect(picture.right, lessThanOrEqualTo(tester.getRect(split).left));
    for (final key in [
      'video-edit-on-video',
      'video-edit-title-fields',
      'video-edit-master',
      'video-edit-fade-fields',
    ]) {
      expect(
        find.descendant(of: settings, matching: find.byKey(Key(key))),
        findsOneWidget,
        reason: key,
      );
    }

    await tester.tap(button);
    await frames(tester);
    expect(settings, findsNothing);
    expect(split, findsNothing);
    // The 4:3 video, as wide as the screen now.
    final grown = tester.getRect(preview);
    expect(grown.width, 900);
    expect(grown.width, greaterThan(picture.width));
    expect(grown.width / grown.height, closeTo(4 / 3, 0.02));
    expect(tester.takeException(), isNull);
  });

  testWidgets('its edge drags it wider and narrower, within the room; a '
      'double tap puts it back; the width is the play-along sidebar\'s', (
    tester,
  ) async {
    await open(tester, const Size(1280, 800));
    double width() => tester.getSize(settings).width;
    expect(width(), 360);

    // The drag's slop aside, it follows the edge.
    await tester.drag(split, const Offset(-120, 0));
    await frames(tester);
    final wider = width();
    expect(wider, inInclusiveRange(450, 480));
    expect(SidebarWidths.instance.of(SidebarWidths.playAlong), wider);
    await tester.drag(split, const Offset(220, 0));
    await frames(tester);
    expect(width(), inInclusiveRange(wider - 220, wider - 190));

    // Never narrower than the least, nor so wide the editor goes; nothing
    // overflows at either end.
    await tester.drag(split, const Offset(600, 0));
    await frames(tester);
    expect(width(), DownloadSidebarBeside.minWidth);
    expect(tester.takeException(), isNull);
    await tester.drag(split, const Offset(-2000, 0));
    await frames(tester);
    expect(
      width(),
      1280 - DownloadSidebarBeside.minChild - SplitHandle.thickness,
    );
    expect(tester.takeException(), isNull);

    // Hidden and shown again, it keeps its width.
    await tester.tap(button);
    await frames(tester);
    await tester.tap(button);
    await frames(tester);
    expect(
      width(),
      1280 - DownloadSidebarBeside.minChild - SplitHandle.thickness,
    );

    await tester.tap(split);
    await tester.pump(const Duration(milliseconds: 50));
    await tester.tap(split);
    await frames(tester);
    expect(width(), 360);
    expect(SidebarWidths.instance.of(SidebarWidths.playAlong), isNull);
  });

  for (final locale in const [Locale('en'), Locale('es'), Locale('pt')]) {
    testWidgets('dragged to its least at the largest text, all of them '
        'fit: the Master, On the video, the fades, the tab\'s style and the '
        'song\'s details: ${locale.languageCode}', (tester) async {
      sized(tester, const Size(1280, 800), text: 2);
      final (library, id) = await capture(tester, song: true);
      await tester.pumpWidget(editScreen(library, id, locale: locale));
      await settle(tester);
      expect(tester.takeException(), isNull);
      await tester.drag(split, const Offset(600, 0));
      await frames(tester);
      expect(tester.getSize(settings).width, DownloadSidebarBeside.minWidth);
      expect(tester.takeException(), isNull);
      // Down the whole list, each part laid out in turn.
      final list = tester
          .state<ScrollableState>(
            find
                .descendant(of: settings, matching: find.byType(Scrollable))
                .first,
          )
          .position;
      var seen = <String>{};
      for (var at = 0.0; ; at += 100) {
        list.jumpTo(min(at, list.maxScrollExtent));
        await tester.pump(const Duration(milliseconds: 50));
        expect(tester.takeException(), isNull, reason: 'at $at');
        seen = {
          ...seen,
          for (final key in [
            'video-edit-master',
            'video-edit-fade-fields',
            'video-edit-tab-style',
            'video-edit-song-details',
          ])
            if (find.byKey(Key(key)).evaluate().isNotEmpty) key,
        };
        if (at >= list.maxScrollExtent) break;
      }
      expect(seen, hasLength(4));
    });
  }

  testWidgets('hidden, it stays hidden in the next editor of the session, '
      'until shown again', (tester) async {
    final (library, id) = await open(tester, const Size(1280, 800));
    await tester.tap(button);
    await frames(tester);
    expect(settings, findsNothing);

    await tester.pumpWidget(const SizedBox());
    await tester.pumpWidget(editScreen(library, id));
    await settle(tester);
    expect(settings, findsNothing);
    expect(selected(tester), isFalse);
    await tester.tap(button);
    await frames(tester);
    expect(settings, findsOneWidget);

    await tester.pumpWidget(const SizedBox());
    await tester.pumpWidget(editScreen(library, id));
    await settle(tester);
    expect(settings, findsOneWidget);
    expect(selected(tester), isTrue);
  });

  testWidgets('in a short window (a phone on its side) it has no tabs at '
      'its top, the Download settings button showing and hiding it', (
    tester,
  ) async {
    await open(tester, const Size(844, 390));
    expect(settings, findsOneWidget);
    expect(find.byKey(const Key('sidebar-tabs')), findsNothing);
    expect(
      find.descendant(
        of: settings,
        matching: find.byKey(const Key('video-edit-master')),
      ),
      findsOneWidget,
    );
    await tester.tap(button);
    await frames(tester);
    expect(settings, findsNothing);
    expect(tester.takeException(), isNull);
  });

  group('hidden, a tap on the picture shows it at its field', () {
    /// A point on the title, at the picture's top left.
    Offset onTitle(WidgetTester tester) {
      final box = tester.getRect(preview);
      return box.topLeft +
          Offset(box.shortestSide * 0.05, box.shortestSide * 0.05);
    }

    /// A point on the tab's band, at the picture's bottom.
    Offset onBand(WidgetTester tester) =>
        tester.getRect(preview).bottomCenter - const Offset(0, 2);

    Future<void> hide(WidgetTester tester) async {
      if (settings.evaluate().isEmpty) return;
      await tester.tap(button);
      await frames(tester);
      expect(settings, findsNothing);
    }

    testWidgets('on a phone: the title, a long press on the band, and the '
        'fade\'s badge', (tester) async {
      await open(tester, const Size(390, 844));
      await hide(tester);
      await tester.tapAt(onTitle(tester));
      await settle(tester);
      expect(settings, findsOneWidget);
      expect(find.byKey(const Key('video-edit-title-fields')), findsOneWidget);
      expect(inView(tester, 'video-edit-title-fields'), isTrue);

      await hide(tester);
      await tester.longPressAt(onBand(tester));
      await settle(tester);
      expect(settings, findsOneWidget);
      expect(find.byKey(const Key('video-edit-tab-style')), findsOneWidget);
      expect(inView(tester, 'video-edit-tab-style'), isTrue);

      await hide(tester);
      // At the start, fading in: the badge.
      expect(find.text('Fade in · 3.0 s'), findsOneWidget);
      await tester.tap(find.byKey(const Key('video-edit-picture-fade')));
      await settle(tester);
      expect(settings, findsOneWidget);
      expect(find.byKey(const Key('video-edit-fade-fields')), findsOneWidget);
      expect(inView(tester, 'video-edit-fade-fields'), isTrue);
      expect(tester.takeException(), isNull);
    });

    testWidgets('on a wide screen: the title, a tap on the band (picking '
        'it), and the fade\'s badge, each scrolled to', (tester) async {
      await open(tester, const Size(1280, 800));
      await hide(tester);
      // The band picked: its style, the last thing in them, in view.
      await tester.tapAt(onBand(tester));
      await settle(tester);
      expect(settings, findsOneWidget);
      expect(
        find.byKey(const Key('video-edit-picture-toolbar')),
        findsOneWidget,
      );
      expect(inView(tester, 'video-edit-tab-style'), isTrue);
      expect(inView(tester, 'video-edit-on-video'), isFalse);

      await hide(tester);
      expect(find.text('Fade in · 3.0 s'), findsOneWidget);
      await tester.tap(find.byKey(const Key('video-edit-picture-fade')));
      await settle(tester);
      expect(settings, findsOneWidget);
      expect(inView(tester, 'video-edit-fade-fields'), isTrue);

      await hide(tester);
      await tester.tapAt(onTitle(tester));
      await settle(tester);
      expect(settings, findsOneWidget);
      expect(inView(tester, 'video-edit-title-fields'), isTrue);
      expect(tester.takeException(), isNull);
    });

    testWidgets('showing, a tap on the band neither scrolls it nor opens '
        'anything', (tester) async {
      await open(tester, const Size(1280, 800));
      final list = find
          .descendant(of: settings, matching: find.byType(Scrollable))
          .first;
      double at() => tester.state<ScrollableState>(list).position.pixels;
      expect(at(), 0);
      await tester.tapAt(onBand(tester));
      await settle(tester);
      expect(
        find.byKey(const Key('video-edit-picture-toolbar')),
        findsOneWidget,
      );
      expect(at(), 0);
    });
  });

  testWidgets('during a Download it takes no taps; the dictionary and the '
      'metronome still do', (tester) async {
    sized(tester, const Size(1280, 800));
    final (library, id) = await capture(tester);
    final editor = _HeldEditor();
    await tester.pumpWidget(editScreen(library, id, editor: editor));
    await settle(tester);
    await tester.tap(find.byKey(const Key('video-edit-download')));
    await settle(tester);
    expect(find.byKey(const Key('video-edit-progress')), findsOneWidget);

    await tester.tap(close, warnIfMissed: false);
    await frames(tester);
    expect(settings, findsOneWidget);
    await tester.tap(
      find.byKey(const Key('video-edit-fades')),
      warnIfMissed: false,
    );
    await settle(tester);
    expect(library.byId(id)!.pages.first.edit, isNull);

    await tester.tap(find.byKey(const Key('dictionary')));
    await frames(tester);
    expect(find.byKey(const Key('dictionary-sidebar')), findsOneWidget);
    await tester.tap(find.byKey(const Key('metronome')));
    await frames(tester);
    expect(find.byKey(const Key('metronome-sidebar')), findsOneWidget);

    editor.hold.complete();
    await settle(tester);
    expect(find.byKey(const Key('video-edit-progress')), findsNothing);
    expect(editor.rendered, hasLength(1));
    await tester.tap(close);
    await frames(tester);
    expect(settings, findsNothing);
    expect(tester.takeException(), isNull);
  });

  testWidgets('the dictionary\'s and the metronome\'s sidebars open beside '
      'the editor and its sidebar, the settings staying in it', (tester) async {
    await open(tester, const Size(1280, 1000));
    expect(side, findsOneWidget);
    await tester.tap(find.byKey(const Key('dictionary')));
    await frames(tester);
    final dictionary = find.byKey(const Key('dictionary-sidebar'));
    expect(dictionary, findsOneWidget);
    expect(tester.getRect(dictionary).right, 1280);
    expect(side, findsOneWidget);
    expect(
      tester.getRect(settings).right,
      lessThanOrEqualTo(tester.getRect(dictionary).left),
    );
    expect(tester.takeException(), isNull);

    // Typing in its field, the space bar types: the preview doesn't play.
    await tester.tap(find.byKey(const Key('dictionary-query')));
    await frames(tester);
    await tester.sendKeyEvent(LogicalKeyboardKey.space);
    await settle(tester);
    expect(platform.playing, isEmpty);

    // Closed, the editor has its keys back: the space bar plays.
    await tester.tap(find.byKey(const Key('dictionary-close')));
    await frames(tester);
    expect(side, findsOneWidget);
    await tester.sendKeyEvent(LogicalKeyboardKey.space);
    await settle(tester);
    expect(platform.playing, isNotEmpty);

    await tester.tap(find.byKey(const Key('metronome')));
    await frames(tester);
    expect(find.byKey(const Key('metronome-sidebar')), findsOneWidget);
    expect(tester.takeException(), isNull);
  });

  testWidgets('typing the title, the on-screen keyboard up, the sidebar '
      'stays as it was', (tester) async {
    await open(tester, const Size(900, 800));
    expect(side, findsOneWidget);
    // The title tapped on the picture: its fields in view, the first one
    // focused.
    final box = tester.getRect(preview);
    await tester.tapAt(
      box.topLeft + Offset(box.shortestSide * 0.05, box.shortestSide * 0.05),
    );
    await settle(tester);
    final fields = find.byKey(const Key('video-edit-title-fields'));
    expect(fields, findsOneWidget);
    final before = tester.getRect(settings);
    // The keyboard up: the body is 344 high, the window still 800.
    tester.view.viewInsets = const FakeViewPadding(bottom: 400);
    await frames(tester);
    expect(side, findsOneWidget);
    expect(fields, findsOneWidget);
    expect(tester.getRect(settings).width, before.width);
    expect(tester.takeException(), isNull);
    tester.view.viewInsets = FakeViewPadding.zero;
    await frames(tester);
    expect(side, findsOneWidget);
    expect(fields, findsOneWidget);
    expect(tester.takeException(), isNull);
  });

  for (final locale in const [Locale('en'), Locale('es'), Locale('pt')]) {
    testWidgets('on a small phone at the largest text, ⋮ holds Rec over '
        'this, Dictionary, Metronome, Share and About; the rest fits the app '
        'bar: '
        '${locale.languageCode}', (tester) async {
      sized(tester, const Size(360, 740), text: 2);
      final (library, id) = await capture(tester);
      await tester.pumpWidget(editScreen(library, id, locale: locale));
      await settle(tester);
      expect(tester.takeException(), isNull);
      final bar = find.byType(AppBar);
      final screen = Offset.zero & const Size(360, 740);
      for (final key in [
        'video-edit-reset',
        'video-edit-download',
        'video-edit-settings',
        'video-edit-more',
      ]) {
        final shown = find.descendant(of: bar, matching: find.byKey(Key(key)));
        expect(shown, findsOneWidget, reason: key);
        final r = tester.getRect(shown);
        expect(
          screen.contains(r.topLeft) &&
              screen.contains(r.bottomRight - const Offset(1, 1)),
          isTrue,
          reason: '$key at $r',
        );
      }
      for (final key in [
        'video-edit-cam',
        'dictionary',
        'metronome',
        'video-edit-share',
        'video-edit-about',
      ]) {
        expect(find.byKey(Key(key)), findsNothing, reason: key);
      }

      await tester.tap(find.byKey(const Key('video-edit-more')));
      await frames(tester);
      expect(tester.takeException(), isNull);
      for (final key in [
        'video-edit-cam',
        'dictionary',
        'metronome',
        'video-edit-share',
        'video-edit-about',
      ]) {
        expect(find.byKey(Key(key)), findsOneWidget, reason: key);
      }
      await tester.tap(find.byKey(const Key('metronome')));
      await frames(tester);
      expect(find.byKey(const Key('metronome-sidebar')), findsOneWidget);
      expect(MetronomeState.instance.open, isTrue);
      expect(tester.takeException(), isNull);
    });
  }

  testWidgets('from 600 wide, Dictionary, Metronome, Share and About are in '
      'the app bar, with no menu', (tester) async {
    await open(tester, const Size(800, 600));
    final bar = find.byType(AppBar);
    for (final key in [
      'video-edit-reset',
      'video-edit-download',
      'video-edit-settings',
      'dictionary',
      'metronome',
      'video-edit-share',
      'video-edit-about',
    ]) {
      expect(
        find.descendant(of: bar, matching: find.byKey(Key(key))),
        findsOneWidget,
        reason: key,
      );
    }
    expect(find.byKey(const Key('video-edit-more')), findsNothing);
    // 800 × 600: room for the sidebar beside the editor, from the start.
    expect(find.byKey(const Key('video-edit-side')), findsOneWidget);
  });
}
