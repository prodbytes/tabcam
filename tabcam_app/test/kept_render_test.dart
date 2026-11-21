import 'dart:typed_data';

import 'package:cross_file/cross_file.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:tabcam_app/capture/video_edit.dart';
import 'package:tabcam_app/export/download.dart';
import 'package:tabcam_app/l10n/app_localizations.dart';
import 'package:tabcam_app/library/capture_event.dart';
import 'package:tabcam_app/library/event_store_memory.dart';
import 'package:tabcam_app/library/library.dart';
import 'package:tabcam_app/screens/event_screen.dart';
import 'package:tabcam_app/screens/file_screen.dart';
import 'package:tabcam_app/screens/video_edit_screen.dart';
import 'package:tabcam_app/screens/video_page.dart';
import 'package:video_player_platform_interface/video_player_platform_interface.dart';

import 'mini_player_test.dart' show FakeVideoPlatform;
import 'video_edit_test.dart' show FakeEditor;

/// The fake platform, with what each player was opened on.
class SourcePlatform extends FakeVideoPlatform {
  final sources = <String?>[];

  @override
  Future<int?> createWithOptions(VideoCreationOptions options) {
    sources.add(options.dataSource.uri);
    return super.createWithOptions(options);
  }

  /// The bytes player [id] plays (files in memory play from data URLs).
  List<int> bytesOf(int id) => Uri.parse(sources[id]!).data!.contentAsBytes();
}

Duration s(double seconds) => Duration(milliseconds: (seconds * 1000).round());

Uint8List bytes(List<int> b) => Uint8List.fromList(b);

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

/// A capture named "Blue riff" by "Made-up Band" with a video (v1, a
/// [video] file of bytes 1, 2, 3) and an image (i1).
Future<(Library, String)> _capture({String video = 'mp4'}) async {
  final library = Library(PlatformEventStore(), null, (_) async => null);
  await library.load();
  var event = await library.create(const [], title: 'Blue riff');
  for (final page in [
    EventPage(id: 'v1', kind: PageKind.video, extension: video),
    const EventPage(id: 'i1', extension: 'jpg'),
  ]) {
    await library.putPageStream(event.id, page, Stream.value(bytes([1, 2, 3])));
    event = event.copyWith(pages: [...event.pages, page]);
  }
  await library.update(event.copyWith(artist: 'Made-up Band'));
  return (library, event.id);
}

EventPage _page(Library library, String id, [String pageId = 'v1']) =>
    library.byId(id)!.pages.firstWhere((p) => p.id == pageId);

XFile _made(List<int> b) =>
    XFile.fromData(bytes(b), name: 'edit.mp4', mimeType: 'video/mp4');

final _edit = PageEdit(start: s(2), end: s(12));

void main() {
  group('a page\'s render', () {
    test('is kept in the page\'s JSON and read back: its file, the edit '
        'it was made from and its title', () {
      final page = EventPage(
        id: 'v1',
        kind: PageKind.video,
        extension: 'mov',
        edit: _edit,
        render: PageRender(
          id: 'r1',
          extension: 'mp4',
          edit: _edit,
          title: 'Blue riff\nMade-up Band',
        ),
      );
      final json = page.toJson();
      expect(json['render'], {
        'id': 'r1',
        'extension': 'mp4',
        'edit': _edit.toJson(),
        'title': 'Blue riff\nMade-up Band',
      });
      final back = EventPage.fromJson(json);
      expect(back.render, page.render);
      expect(back.render!.file.fileName, 'r1.mp4');
      expect(back.render!.file.isVideo, isTrue);
      // Renamed or retitled, it's kept.
      expect(page.copyWith(title: () => 'Take').render, page.render);
      expect(page.copyWith(render: () => null).render, isNull);

      // Made from no edit, with no title: neither is written.
      expect(const PageRender(id: 'r2', extension: 'webm').toJson(), {
        'id': 'r2',
        'extension': 'webm',
      });
    });

    test('a broken one, or one on a page that isn\'t a video, is none', () {
      for (final render in [
        'r1.mp4',
        {'id': 'r1'},
        {'id': '../r1', 'extension': 'mp4'},
        {'id': 'r1', 'extension': 'mp4/x'},
      ]) {
        expect(
          EventPage.fromJson({
            'id': 'v1',
            'kind': 'video',
            'extension': 'mp4',
            'render': render,
          }).render,
          isNull,
          reason: '$render',
        );
      }
      expect(
        EventPage.fromJson({
          'id': 'a1',
          'kind': 'audio',
          'extension': 'm4a',
          'render': {'id': 'r1', 'extension': 'mp4'},
        }).render,
        isNull,
      );
    });

    test('its file is one of the event\'s: the page\'s own, then the '
        'render\'s, the trash\'s too', () {
      const render = PageRender(id: 'r1', extension: 'mp4');
      const page = EventPage(
        id: 'v1',
        kind: PageKind.video,
        extension: 'mp4',
        render: render,
      );
      expect(page.files.map((p) => p.fileName), ['v1.mp4', 'r1.mp4']);
      final event = CaptureEvent(
        id: 'e1',
        title: 'Blue riff',
        created: DateTime(2026, 11, 21),
        pages: const [EventPage(id: 'i1', extension: 'jpg')],
        deletedPages: const [page],
      );
      expect(event.storedFiles.map((p) => p.fileName), [
        'i1.jpg',
        'v1.mp4',
        'r1.mp4',
      ]);
    });
  });

  group('Library', () {
    test('keepRender keeps the file as the page\'s render; a new one '
        'replaces it, its file gone', () async {
      final (library, id) = await _capture();
      await library.setPageEdit(id, 'v1', _edit);
      await library.keepRender(
        id,
        'v1',
        _made([9, 9]),
        extension: 'mp4',
        edit: _edit,
        title: 'Blue riff\nMade-up Band',
      );
      final first = _page(library, id).render!;
      expect(first.edit, _edit);
      expect(first.extension, 'mp4');
      expect(first.title, 'Blue riff\nMade-up Band');
      final event = library.byId(id)!;
      expect(await library.original(event, first.file), [9, 9]);
      // The page's own file is as it was.
      expect(await library.original(event, _page(library, id)), [1, 2, 3]);

      await library.keepRender(
        id,
        'v1',
        _made([8]),
        extension: 'mp4',
        edit: _edit,
      );
      final second = _page(library, id).render!;
      expect(second.id, isNot(first.id));
      expect(await library.original(library.byId(id)!, second.file), [8]);
      expect(await library.hasPage(id, first.file), isFalse);
    });

    test('only a video of the user\'s own keeps one', () async {
      final (library, id) = await _capture();
      expect(
        await library.keepRender(id, 'i1', _made([9]), extension: 'mp4'),
        isNull,
      );
      expect(
        await library.keepRender(id, 'gone', _made([9]), extension: 'mp4'),
        isNull,
      );
      expect(library.byId(id)!.pages.map((p) => p.render), [null, null]);
    });

    test('a change of the edit drops the render, with its file; the same '
        'edit kept again keeps it', () async {
      final (library, id) = await _capture();
      await library.setPageEdit(id, 'v1', _edit);
      await library.keepRender(
        id,
        'v1',
        _made([9]),
        extension: 'mp4',
        edit: _edit,
      );
      final render = _page(library, id).render!;
      await library.setPageEdit(id, 'v1', PageEdit(start: s(2), end: s(12)));
      expect(_page(library, id).render, render);
      expect(await library.hasPage(id, render.file), isTrue);

      await library.setPageEdit(id, 'v1', PageEdit(start: s(3), end: s(12)));
      expect(_page(library, id).render, isNull);
      expect(await library.hasPage(id, render.file), isFalse);
    });

    test('a deleted video keeps its render in the trash, restored with it; '
        'purged, its file goes', () async {
      final (library, id) = await _capture();
      await library.keepRender(id, 'v1', _made([9]), extension: 'mp4');
      final page = _page(library, id);
      final render = page.render!;
      await library.deletePage(library.byId(id)!, page);
      expect(await library.hasPage(id, render.file), isTrue);
      await library.restorePage(id, library.byId(id)!.deletedPages.single);
      expect(_page(library, id).render, render);

      await library.deletePage(library.byId(id)!, _page(library, id));
      await library.purge();
      expect(await library.hasPage(id, render.file), isFalse);
      expect(await library.hasPage(id, page), isFalse);
    });

    test('a clone\'s video has no render (its file is the original\'s '
        'folder\'s); the capture purged, the render\'s file goes', () async {
      final (library, id) = await _capture();
      await library.keepRender(id, 'v1', _made([9]), extension: 'mp4');
      final render = _page(library, id).render!;
      final copy = await library.clone(library.byId(id)!);
      expect(copy.pages.map((p) => p.render), [null, null]);

      await library.delete(library.byId(id)!);
      await library.purge();
      expect(await library.hasPage(id, render.file), isFalse);
    });
  });

  group('currentRender', () {
    test('plays while the edit and the title are as it was made with, and '
        'its file is here', () async {
      final (library, id) = await _capture();
      await library.setPageEdit(id, 'v1', _edit);
      Future<EventPage?> current() =>
          currentRender(library, library.byId(id)!, _page(library, id));
      expect(await current(), isNull);

      await library.keepRender(
        id,
        'v1',
        _made([9]),
        extension: 'mp4',
        edit: _edit,
        title: 'Blue riff\nMade-up Band',
      );
      expect((await current())?.id, _page(library, id).render!.id);

      // The capture renamed: its title would show something else.
      await library.update(library.byId(id)!.copyWith(title: 'Red riff'));
      expect(await current(), isNull);
      await library.update(library.byId(id)!.copyWith(title: 'Blue riff'));
      expect(await current(), isNotNull);

      // An edit with its own title, or none: what it shows counts.
      final untitled = PageEdit(
        start: s(2),
        end: s(12),
        title: const EditTitle(on: false),
      );
      await library.update(
        library
            .byId(id)!
            .copyWith(
              pages: [
                for (final p in library.byId(id)!.pages)
                  p.id == 'v1'
                      ? p.copyWith(
                          edit: () => untitled,
                          render: () => p.render == null
                              ? null
                              : PageRender(
                                  id: p.render!.id,
                                  extension: 'mp4',
                                  edit: untitled,
                                ),
                        )
                      : p,
              ],
            ),
      );
      expect(await current(), isNotNull);
      await library.update(library.byId(id)!.copyWith(title: 'Red riff'));
      expect(await current(), isNotNull);

      // Its file not here (not come yet): the page plays as before.
      await library.update(
        library
            .byId(id)!
            .copyWith(
              pages: [
                for (final p in library.byId(id)!.pages)
                  p.id == 'v1'
                      ? p.copyWith(
                          render: () => PageRender(
                            id: 'r9',
                            extension: 'mp4',
                            edit: untitled,
                          ),
                        )
                      : p,
              ],
            ),
      );
      expect(await current(), isNull);
    });
  });

  group('the editor\'s Download', () {
    late SourcePlatform platform;
    late FakeEditor editor;
    final saved = <(String, Uint8List, String)>[];
    var saving = true;
    setUp(() {
      VideoPlayerPlatform.instance = platform = SourcePlatform();
      VideoEditor.instance = editor = FakeEditor();
      saved.clear();
      saving = true;
      Downloads.now = () => DateTime(2026, 11, 21, 18, 5, 9);
      Downloads.save = (name, bytes, type) async {
        if (!saving) return false;
        saved.add((name, bytes, type));
        return true;
      };
    });
    tearDown(() => VideoEditor.instance = null);

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

    Future<void> download(
      WidgetTester tester,
      Library library,
      String id, {
      String key = 'video-edit-download',
    }) async {
      await tester.pumpWidget(
        host(
          VideoEditScreen(
            library: library,
            eventId: id,
            page: _page(library, id),
            pickFile: () async => null,
          ),
        ),
      );
      await _settle(tester);
      if (key != 'video-edit-download') {
        await tester.tap(find.byKey(const Key('video-edit-download-more')));
        await _frames(tester);
      }
      await tester.tap(find.byKey(Key(key)));
      await _settle(tester);
      await tester.pumpWidget(const SizedBox());
      await _settle(tester);
    }

    testWidgets('keeps the video it made: the file list and the file '
        'screen play it, until the edit changes', (tester) async {
      tall(tester);
      // A WebM, which Download makes again as an MP4.
      final (library, id) = (await tester.runAsync(
        () => _capture(video: 'webm'),
      ))!;
      await download(tester, library, id);
      expect(editor.rendered, hasLength(1));
      expect(saved.single.$2, [9, 9, 9]);
      final render = _page(library, id).render!;
      expect(render.extension, 'mp4');
      // Made from the video as it is (no edit), its title the capture's.
      expect(render.edit, isNull);
      expect(render.title, 'Blue riff\nMade-up Band');
      expect(
        await tester.runAsync(
          () => library.original(library.byId(id)!, render.file),
        ),
        [9, 9, 9],
      );

      // The file list's play button plays it.
      await tester.pumpWidget(host(EventScreen(library: library, eventId: id)));
      await _settle(tester);
      await tester.tap(find.byKey(const ValueKey('mini-play-v1')));
      await _settle(tester);
      expect(platform.bytesOf(platform.playing.single), [9, 9, 9]);

      // So does the file screen's, looping it.
      await tester.pumpWidget(const SizedBox());
      await tester.pumpWidget(
        host(FileScreen(library: library, eventId: id, pageId: 'v1')),
      );
      await _settle(tester);
      await tester.tap(find.byIcon(Icons.play_circle_fill));
      await _settle(tester);
      final playing = platform.playing.single;
      expect(platform.bytesOf(playing), [9, 9, 9]);
      expect(platform.looping[playing], isTrue);

      // The edit changed: it plays the video as its edit says again.
      await tester.pumpWidget(const SizedBox());
      await tester.runAsync(() => library.setPageEdit(id, 'v1', _edit));
      expect(_page(library, id).render, isNull);
      await tester.pumpWidget(
        host(FileScreen(library: library, eventId: id, pageId: 'v1')),
      );
      await _settle(tester);
      await tester.tap(find.byIcon(Icons.play_circle_fill));
      await _settle(tester);
      expect(platform.bytesOf(platform.lastPlayer), [1, 2, 3]);
      expect(platform.seeks, contains(s(2)));
    });

    testWidgets('a download cancelled, the sound alone or the video as it '
        'is keeps nothing', (tester) async {
      tall(tester);
      final (library, id) = (await tester.runAsync(
        () => _capture(video: 'webm'),
      ))!;
      saving = false;
      await download(tester, library, id);
      expect(editor.rendered, hasLength(1));
      expect(_page(library, id).render, isNull);

      saving = true;
      await download(tester, library, id, key: 'video-edit-download-sound');
      expect(saved, hasLength(1));
      expect(_page(library, id).render, isNull);

      // An MP4 as it is (no watermark, title nor fades: a capture with
      // the app's own name) is saved as it is: nothing is made to keep.
      final (plain, plainId) = (await tester.runAsync(() async {
        final library = Library(PlatformEventStore(), null, (_) async => null);
        await library.load();
        var event = await library.create(const []);
        const page = EventPage(
          id: 'v1',
          kind: PageKind.video,
          extension: 'mp4',
        );
        await library.putPageStream(
          event.id,
          page,
          Stream.value(bytes([1, 2, 3])),
        );
        event = await library.update(event.copyWith(pages: [page]));
        await library.setPageEdit(
          event.id,
          'v1',
          PageEdit(
            start: Duration.zero,
            end: const Duration(minutes: 3),
            watermark: false,
            fadeIn: Duration.zero,
            fadeOut: Duration.zero,
          ),
        );
        return (library, event.id);
      }))!;
      editor.rendered.clear();
      saved.clear();
      await download(tester, plain, plainId);
      expect(editor.rendered, isEmpty);
      expect(saved.single.$2, [1, 2, 3]);
      expect(_page(plain, plainId).render, isNull);
    });

    testWidgets('a change still waiting to be kept is kept first: the '
        'render names the edit it was made from', (tester) async {
      tall(tester);
      final (library, id) = (await tester.runAsync(
        () => _capture(video: 'webm'),
      ))!;
      await tester.pumpWidget(
        host(
          VideoEditScreen(
            library: library,
            eventId: id,
            page: _page(library, id),
            pickFile: () async => null,
          ),
        ),
      );
      await _settle(tester);
      // The start moved, and Download at once (before the edit's kept).
      await tester.tap(find.byKey(const Key('video-edit-start-later')));
      await tester.pump();
      await tester.tap(find.byKey(const Key('video-edit-download')));
      await _settle(tester);
      final page = _page(library, id);
      expect(page.edit, isNotNull);
      expect(page.edit!.start, greaterThan(Duration.zero));
      expect(page.render?.edit, page.edit);
      expect(editor.rendered.single.start, page.edit!.start);
      await tester.pumpWidget(const SizedBox());
      await _settle(tester);
      expect(_page(library, id).render, isNotNull);
    });
  });
}
