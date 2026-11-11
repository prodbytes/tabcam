import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:tabcam_app/capture/backing_track.dart';
import 'package:tabcam_app/cloud/cloud_ocr.dart';
import 'package:tabcam_app/cloud/cloud_sync.dart';
import 'package:tabcam_app/l10n/language.dart';
import 'package:tabcam_app/library/capture_event.dart';
import 'package:tabcam_app/library/event_store_io.dart' as io;
import 'package:tabcam_app/library/event_store_memory.dart' as web;
import 'package:tabcam_app/library/meta_names.dart';
import 'package:tabcam_app/library/meta_storage.dart';
import 'package:tabcam_app/metronome/metronome.dart';
import 'package:tabcam_app/screens/delete_confirm.dart';
import 'package:tabcam_app/screens/place.dart';
import 'package:tabcam_app/screens/sidebar_widths.dart';

/// localStorage, as a map; [broken] makes every call throw, as a private
/// window or a full quota does.
class _FakeStorage implements MetaStorage {
  final Map<String, String> items = {};
  bool broken = false;

  @override
  String? getItem(String key) {
    if (broken) throw StateError('SecurityError');
    return items[key];
  }

  @override
  void setItem(String key, String value) {
    if (broken) throw StateError('QuotaExceededError');
    items[key] = value;
  }
}

void main() {
  group('meta names', () {
    test('every one passes checkId, so the apps\' store takes it', () {
      for (final name in MetaNames.all) {
        expect(checkId(name), name);
      }
    });

    test('the settings\' names are the ones listed', () {
      expect({
        MetaNames.cam, // Cam's constant is private: the scan below checks it
        BackingTrack.metaName,
        DeleteConfirms.metaName,
        SidebarWidths.metaName,
        PlaceMemory.metaName,
        LanguageSetting.metaName,
        MetronomeState.metaName,
        CloudSync.stateName,
        CloudOcr.stateName,
      }, MetaNames.all);
      expect(BackingTrack.metaName, 'playalong');
    });

    test('lib/ names its metas only through MetaNames', () {
      final literal = RegExp(r'''(read|write)Meta\(\s*['"]''');
      final constant = RegExp(
        r'''static const (String )?(metaName|stateName) = (?!MetaNames\.)''',
      );
      final offenders = [
        for (final file in Directory('lib').listSync(recursive: true))
          if (file is File && file.path.endsWith('.dart'))
            if (literal.hasMatch(file.readAsStringSync()) ||
                constant.hasMatch(file.readAsStringSync()))
              file.path,
      ];
      expect(offenders, isEmpty);
    });
  });

  group('the apps\' store', () {
    late Directory root;
    setUp(() async => root = await Directory.systemTemp.createTemp('tabcam'));
    tearDown(() => root.delete(recursive: true));

    test('keeps every meta as a file, read back by a new store', () async {
      final store = io.PlatformEventStore(Directory('${root.path}/scans'));
      for (final name in MetaNames.all) {
        await store.writeMeta(name, '{"name":"$name"}');
      }
      final reopened = io.PlatformEventStore(Directory('${root.path}/scans'));
      for (final name in MetaNames.all) {
        expect(await reopened.readMeta(name), '{"name":"$name"}');
      }
    });

    test('refuses a name that isn\'t an ID', () async {
      final store = io.PlatformEventStore(Directory('${root.path}/scans'));
      expect(store.writeMeta('play-along', '{}'), throwsFormatException);
    });
  });

  group('the web\'s store', () {
    test('keeps the device\'s settings in localStorage across a reload, '
        'and nothing else', () async {
      final storage = _FakeStorage();
      final store = web.PlatformEventStore(storage: storage);
      for (final name in MetaNames.all) {
        await store.writeMeta(name, '{"name":"$name"}');
      }
      expect(storage.items.keys.toSet(), {
        for (final name in MetaNames.deviceSettings) 'tabcam.meta.$name',
      });

      final reloaded = web.PlatformEventStore(storage: storage);
      for (final name in MetaNames.deviceSettings) {
        expect(await reloaded.readMeta(name), '{"name":"$name"}');
      }
      // Cloud sync's state describes the captures, which a reload loses.
      expect(await reloaded.readMeta(MetaNames.cloudSync), isNull);
      expect(await reloaded.readMeta(MetaNames.cloudOcr), isNull);
    });

    test('without storage, settings last in memory', () async {
      final storage = _FakeStorage()..broken = true;
      final store = web.PlatformEventStore(storage: storage);
      expect(await store.readMeta(MetaNames.playAlong), isNull);
      await store.writeMeta(MetaNames.playAlong, '{"countIn":false}');
      expect(await store.readMeta(MetaNames.playAlong), '{"countIn":false}');
      expect(storage.items, isEmpty);

      expect(
        await web.PlatformEventStore(storage: storage)
            .readMeta(MetaNames.playAlong),
        isNull,
      );
    });

    test('off the web there is no localStorage', () {
      expect(web.PlatformEventStore().storage, isNull);
    });

    test('refuses a name that isn\'t an ID, as the apps\' store does', () {
      final store = web.PlatformEventStore(storage: _FakeStorage());
      expect(store.writeMeta('play-along', '{}'), throwsFormatException);
      expect(store.readMeta('play-along'), throwsFormatException);
    });
  });
}
