import 'dart:convert';
import 'dart:io';

import 'package:cross_file/cross_file.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:image/image.dart' as img;
import 'package:tabcam_app/capture/media.dart';
import 'package:tabcam_app/library/capture_event.dart';
import 'package:tabcam_app/library/event_store_io.dart';
import 'package:tabcam_app/library/json_extra.dart';
import 'package:tabcam_app/library/library.dart';

/// What a newer app might write on a take's page: a made-up log.
const _takeLog = {
  'v': 1,
  'lagMs': 120,
  'burned': false,
  'marks': [
    {'ms': 0, 'line': 0},
    {'ms': 2400, 'line': 1},
  ],
  'lines': ['e|--0--3--|', 'e|--5--7--|'],
  'song': <Object?>[],
};

/// What a newer app might add to an edit.
const _editV2 = {
  'v': 2,
  'ownVolume': 0.8,
  'nudgeMs': -120,
  'title': {
    'on': true,
    'lines': ['Blue Riff', 'Made-up Band'],
  },
  'watermark': false,
};

Uint8List _jpeg(int width, int height) => img.encodeJpg(
  img.Image(width: width, height: height)..clear(img.ColorRgb8(240, 240, 240)),
);

/// [json] through a JSON string, as saved and loaded.
Map<String, Object?> _encoded(Map<String, Object?> json) =>
    (jsonDecode(jsonEncode(json)) as Map).cast<String, Object?>();

Map<String, Object?> _pageJson({Map<String, Object?> edit = const {}}) => {
  'id': 'p1',
  'filter': 'original',
  'kind': 'video',
  'extension': 'mp4',
  'take': true,
  'edit': {
    'startMs': 1000,
    'endMs': 5000,
    'sound': 'track',
    'trackId': 'p2',
    'offsetMs': 1500,
    'trackVolume': 0.5,
    ...edit,
  },
  'takeLog': _takeLog,
  'future': 1,
};

void main() {
  group('pages', () {
    test('keep keys they don\'t know through copyWith and toJson', () {
      final page = EventPage.fromJson(_pageJson());
      expect(page.extra.keys, ['takeLog', 'future']);
      final json = _encoded(page.copyWith(title: () => 'x').toJson());
      expect(json['title'], 'x');
      expect(json['takeLog'], _takeLog);
      expect(json['future'], 1);
      // And again, loaded back.
      final again = EventPage.fromJson(json).toJson();
      expect(_encoded(again), json);
    });

    test('links keep them too', () {
      final page = EventPage.fromJson({
        'id': 'l1',
        'kind': 'link',
        'url': 'https://example.com/lesson',
        'future': {'a': 1},
      });
      expect(page.isLink, isTrue);
      expect(page.copyWith(title: () => 'Lesson').toJson()['future'], {'a': 1});
    });

    test('known keys are read and checked as before, never kept as extra', () {
      // A key it knows is never taken from extra, even when the page has
      // no value for it.
      final image = EventPage.fromJson({
        'id': 'p1',
        'kind': 'image',
        'url': 'javascript:alert(1)',
        'edit': {'startMs': 0, 'endMs': 10},
        'from': 'abc',
      });
      expect(image.url, isNull);
      expect(image.edit, isNull);
      expect(image.extra, isEmpty);
      expect(image.toJson().containsKey('url'), isFalse);
      expect(image.toJson().containsKey('edit'), isFalse);
      // A bad ID, link or extension still throws.
      expect(
        () => EventPage.fromJson({'id': '../x', 'future': 1}),
        throwsFormatException,
      );
      expect(
        () => EventPage.fromJson({
          'id': 'l1',
          'kind': 'link',
          'url': 'file:///etc/passwd',
          'future': 1,
        }),
        throwsFormatException,
      );
    });

    test('known keys win over extra keys of the same name', () {
      const page = EventPage(
        id: 'p1',
        kind: PageKind.video,
        extension: 'mp4',
        extra: {
          'id': '../evil',
          'url': 'javascript:alert(1)',
          'extension': 'sh',
          'take': true,
          'future': 1,
        },
      );
      final json = page.toJson();
      expect(json['id'], 'p1');
      expect(json['extension'], 'mp4');
      expect(json.containsKey('url'), isFalse);
      expect(json.containsKey('take'), isFalse);
      expect(json['future'], 1);
      const edit = PageEdit(
        start: Duration(seconds: 1),
        end: Duration(seconds: 2),
        extra: {'startMs': 9000, 'trackId': '../x', 'v': 2},
      );
      expect(edit.toJson(), {
        'startMs': 1000,
        'endMs': 2000,
        'sound': 'original',
        'v': 2,
      });
    });

    test('values that aren\'t JSON, or nest too deep, are left out', () {
      Object deep = 'bottom';
      for (var i = 0; i < maxExtraDepth + 5; i++) {
        deep = [deep];
      }
      final extra = unknownKeys({
        'ok': {
          'a': [1, 2.5, null, true, 'x'],
        },
        'nan': double.nan,
        'deep': deep,
        'object': Object(),
        'intKeys': {1: 'one'},
        3: 'not a string key',
      }, const {});
      expect(extra.keys, ['ok']);
      // Kept values are copies that can't be changed.
      expect(() => (extra['ok']! as Map)['b'] = 1, throwsUnsupportedError);
    });
  });

  group('edits', () {
    test('keep keys they don\'t know through every rebuild', () {
      final json = {
        'startMs': 1000,
        'endMs': 5000,
        'sound': 'track',
        'trackId': 'p2',
        'trackVolume': 0.5,
        ..._editV2,
      };
      final edit = PageEdit.fromJson(json)!;
      expect(edit.extra, _editV2);
      expect(_encoded(edit.toJson()), _encoded(json));
      final changed = edit.withTrackVolume(0.3).withTrackId('p9');
      expect(changed.trackVolume, 0.3);
      expect(changed.trackId, 'p9');
      expect(changed.extra, _editV2);
      expect(_encoded(changed.toJson())['title'], _editV2['title']);
    });

    test('are equal only with the same extra keys', () {
      final a = PageEdit.fromJson({'startMs': 0, 'endMs': 10, ..._editV2})!;
      final b = PageEdit.fromJson(_encoded(a.toJson()))!;
      expect(a, b);
      expect(a.hashCode, b.hashCode);
      expect(
        a ==
            const PageEdit(
              start: Duration.zero,
              end: Duration(milliseconds: 10),
            ),
        isFalse,
      );
    });

    test('come in a page and go out with it', () {
      final page = EventPage.fromJson(_pageJson(edit: _editV2));
      expect(page.edit!.extra, _editV2);
      final json = _encoded(page.copyWith(title: () => 'Take 1').toJson());
      expect(json['edit'], containsPair('v', 2));
      expect(json['edit'], containsPair('title', _editV2['title']));
      expect(json['takeLog'], _takeLog);
    });
  });

  group('the library keeps them', () {
    late Directory root;

    setUp(() async => root = await Directory.systemTemp.createTemp('tabcam'));
    tearDown(() => root.delete(recursive: true));

    /// A capture with an image and a video, each with a newer app's keys.
    Future<(Library, CaptureEvent)> capture() async {
      final library = Library(PlatformEventStore(root));
      await library.load();
      var event = await library.create([_jpeg(40, 60)]);
      final pick = await MediaPick.from([
        XFile.fromData(
          Uint8List.fromList(List.generate(64, (i) => i)),
          path: 'take.mp4',
        ),
      ]);
      event = await library.addMedia(event, pick.media, take: true);
      final video = event.pages.last;
      event = await library.update(
        event.copyWith(
          pages: [
            event.pages.first.copyWith(extra: const {'future': 1}),
            video.copyWith(
              extra: const {'takeLog': _takeLog},
              edit: () =>
                  PageEdit.fromJson({'startMs': 0, 'endMs': 2000, ..._editV2}),
            ),
          ],
        ),
      );
      return (library, event);
    }

    test('across a restart', () async {
      final (_, event) = await capture();
      final reopened = Library(PlatformEventStore(root));
      await reopened.load();
      final pages = reopened.byId(event.id)!.pages;
      expect(pages.first.extra, {'future': 1});
      expect(pages.last.extra, {'takeLog': _takeLog});
      expect(pages.last.edit!.extra, _editV2);
    });

    test('when a page is renamed or its edit changed', () async {
      final (library, event) = await capture();
      final video = event.pages.last;
      var now = (await library.renamePage(event.id, video.id, 'Take 1'))!;
      expect(now.pages.last.title, 'Take 1');
      expect(now.pages.last.extra, {'takeLog': _takeLog});
      now = (await library.setPageEdit(
        event.id,
        video.id,
        video.edit!.withTrackVolume(0.4),
      ))!;
      expect(now.pages.last.extra, {'takeLog': _takeLog});
      expect(now.pages.last.edit!.trackVolume, 0.4);
      expect(now.pages.last.edit!.extra, _editV2);
      // Taking the edit off keeps the page's own.
      now = (await library.setPageEdit(event.id, video.id, null))!;
      expect(now.pages.last.edit, isNull);
      expect(now.pages.last.extra, {'takeLog': _takeLog});
    });

    test('when a page is rotated or replaced', () async {
      final (library, event) = await capture();
      var now = await library.rotatePage(event, event.pages.first);
      expect(now.pages.first.id, isNot(event.pages.first.id));
      expect(now.pages.first.extra, {'future': 1});
      final pick = await MediaPick.from([
        XFile.fromData(Uint8List.fromList([1, 2, 3]), path: 'edited.mp4'),
      ]);
      now = await library.replacePage(now, now.pages.last, pick.media.single);
      expect(now.pages.last.id, isNot(event.pages.last.id));
      expect(now.pages.last.take, isTrue);
      expect(now.pages.last.extra, {'takeLog': _takeLog});
    });

    test('in a clone, as they are', () async {
      final (library, event) = await capture();
      final video = event.pages.last;
      // An extra key naming a page isn't remapped: only the edit's track
      // is (a newer app's clone remaps what it knows).
      await library.update(
        event.copyWith(
          pages: [
            event.pages.first,
            video.copyWith(
              edit: () => video.edit!.withTrackId(event.pages.first.id),
              extra: {'takeLog': _takeLog, 'page': event.pages.first.id},
            ),
          ],
        ),
      );
      final copy = await library.clone(library.byId(event.id)!);
      expect(copy.pages.first.extra, {'future': 1});
      expect(copy.pages.last.extra, {
        'takeLog': _takeLog,
        'page': event.pages.first.id,
      });
      expect(copy.pages.last.edit!.trackId, copy.pages.first.id);
      expect(copy.pages.last.edit!.extra, _editV2);
    });

    test('when a contribution\'s page is published', () async {
      final store = PlatformEventStore(root);
      final library = Library(store);
      await library.load();
      final event = await library.create([_jpeg(10, 10)]);
      const file = EventPage(
        id: 'f1',
        extension: 'jpg',
        extra: {'future': 'file'},
      );
      await store.putPage(event.id, file, _jpeg(10, 10));
      await library.applyContribution(
        event.id,
        Contribution(
          by: 'us-east-1:them',
          updated: DateTime(2026, 11, 11),
          pages: [
            EventPage.link(
              id: 'l1',
              url: Uri.parse('https://example.com/lesson'),
              extra: const {'future': 'link'},
            ),
            file,
          ],
        ),
      );
      var now = library.byId(event.id)!;
      for (final page in now.contributions.single.pages) {
        now = (await library.publish(now, page))!;
      }
      expect(now.pages.skip(1).map((p) => (p.from, p.extra['future'])), [
        ('l1', 'link'),
        ('f1', 'file'),
      ]);
    });
  });
}
