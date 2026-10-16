import 'dart:convert';
import 'dart:typed_data';

import 'package:archive/archive.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:image/image.dart' as img;
import 'package:tabcam_app/export/download.dart';
import 'package:tabcam_app/l10n/app_localizations.dart';
import 'package:tabcam_app/library/event_store_memory.dart';
import 'package:tabcam_app/library/library.dart';
import 'package:tabcam_app/screens/event_screen.dart';

Future<void> frames(WidgetTester tester) async {
  await tester.runAsync(
    () => Future<void>.delayed(const Duration(milliseconds: 30)),
  );
  for (var i = 0; i < 10; i++) {
    await tester.pump(const Duration(milliseconds: 50));
  }
}

void main() {
  test('file names every platform takes', () {
    expect(safeFileName('Page 1', 'jpg'), 'Page 1.jpg');
    expect(safeFileName('AC/DC: riff?', 'pdf'), 'AC_DC_ riff_.pdf');
    expect(safeFileName('  ', 'zip'), 'file.zip');
    expect(safeFileName('..', 'txt'), 'file.txt');
    expect(safeFileName('a' * 200, 'mp4').length, 124);
  });

  late Library library;
  late String id;
  final saved = <(String, Uint8List, String)>[];

  Future<void> make(WidgetTester tester) async {
    saved.clear();
    Downloads.save = (name, bytes, type) async {
      saved.add((name, bytes, type));
      return true;
    };
    await tester.runAsync(() async {
      library = Library(PlatformEventStore(), null, (_) async => null);
      await library.load();
      var event = await library.create([
        img.encodeJpg(img.Image(width: 8, height: 8)),
        img.encodeJpg(img.Image(width: 4, height: 4)),
      ]);
      event = await library.addLink(
        event,
        Uri.parse('https://example.com/lesson'),
      );
      event = await library.update(
        event.copyWith(title: 'Morning riff', tabText: 'e|--0--3--|'),
      );
      id = event.id;
    });
  }

  Future<void> open(WidgetTester tester, Size size) async {
    tester.view.physicalSize = size;
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);
    await tester.pumpWidget(
      MaterialApp(
        localizationsDelegates: AppLocalizations.localizationsDelegates,
        supportedLocales: AppLocalizations.supportedLocales,
        home: EventScreen(library: library, eventId: id),
      ),
    );
    await frames(tester);
  }

  testWidgets('a file downloads under its name in the list', (tester) async {
    await make(tester);
    await open(tester, const Size(1000, 800));
    final page = library.byId(id)!.pages.first;
    // A link has nothing to download.
    final link = library.byId(id)!.pages.last;
    expect(find.byKey(ValueKey('download-${link.id}')), findsNothing);

    await tester.tap(find.byKey(ValueKey('download-${page.id}')));
    await frames(tester);
    final (name, bytes, type) = saved.single;
    expect(name, 'Page 1.jpg');
    expect(type, 'image/jpeg');
    expect(bytes, isNotEmpty);
  });

  testWidgets('on a narrow phone, the file\'s menu has Download', (
    tester,
  ) async {
    await make(tester);
    await open(tester, const Size(360, 740));
    final page = library.byId(id)!.pages[1];
    await tester.tap(find.byKey(ValueKey('more-${page.id}')));
    await frames(tester);
    await tester.tap(find.byKey(ValueKey('download-${page.id}')));
    await frames(tester);
    expect(saved.single.$1, 'Page 2.jpg');
  });

  testWidgets('Download all: one zip, the files, the tab and the links', (
    tester,
  ) async {
    await make(tester);
    await open(tester, const Size(1000, 800));
    await tester.tap(find.byKey(const Key('download-all')));
    await frames(tester);
    final (name, bytes, type) = saved.single;
    expect(name, 'Morning riff.zip');
    expect(type, 'application/zip');
    final zip = ZipDecoder().decodeBytes(bytes);
    expect(
      [for (final f in zip.files) f.name],
      ['Page 1.jpg', 'Page 2.jpg', 'Morning riff tab.txt', 'links.txt'],
    );
    expect(
      utf8.decode(zip.findFile('links.txt')!.content),
      'https://example.com/lesson',
    );
    expect(
      utf8.decode(zip.findFile('Morning riff tab.txt')!.content),
      'e|--0--3--|\n',
    );
  });
}
