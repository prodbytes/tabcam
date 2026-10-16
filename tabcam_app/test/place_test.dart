import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:image/image.dart' as img;
import 'package:tabcam_app/library/event_store_memory.dart';
import 'package:tabcam_app/library/library.dart';
import 'package:tabcam_app/main.dart';
import 'package:tabcam_app/screens/event_screen.dart';
import 'package:tabcam_app/screens/file_screen.dart';
import 'package:tabcam_app/screens/place.dart';

Future<void> frames(WidgetTester tester) async {
  for (var i = 0; i < 20; i++) {
    await tester.pump(const Duration(milliseconds: 50));
  }
}

void main() {
  late Library library;
  setUp(() async {
    library = Library(PlatformEventStore(), null, (_) async => null);
  });

  testWidgets('a restart opens on the tab the user was on', (tester) async {
    await tester.runAsync(() async {
      await library.load();
      await library.writeMeta(
        PlaceMemory.metaName,
        jsonEncode({'tab': 'profile'}),
      );
    });
    await tester.pumpWidget(TabCamApp(library: library));
    await tester.runAsync(
      () => Future<void>.delayed(const Duration(milliseconds: 50)),
    );
    await frames(tester);
    expect(find.text('About'), findsOneWidget);
  });

  testWidgets('a restart reopens the event, on its Text view', (tester) async {
    late String id;
    await tester.runAsync(() async {
      await library.load();
      final event = await library.create([
        img.encodeJpg(img.Image(width: 8, height: 8)),
      ]);
      id = (await library.update(event.copyWith(tabText: 'e|--0--3--|'))).id;
      await library.writeMeta(
        PlaceMemory.metaName,
        jsonEncode({'tab': 'home', 'event': id, 'text': true}),
      );
    });
    await tester.pumpWidget(TabCamApp(library: library));
    await tester.runAsync(
      () => Future<void>.delayed(const Duration(milliseconds: 50)),
    );
    await frames(tester);
    expect(find.byType(EventScreen), findsOneWidget);
    expect(find.textContaining('e|--0--3--|'), findsWidgets);
  });

  testWidgets('moving around is remembered', (tester) async {
    await tester.runAsync(library.load);
    await tester.pumpWidget(TabCamApp(library: library));
    await frames(tester);
    await tester.tap(find.text('Capture'));
    await frames(tester);
    await tester.runAsync(() => PlaceMemory.of(library).flush());
    late String? saved;
    await tester.runAsync(() async {
      saved = await library.readMeta(PlaceMemory.metaName);
    });
    expect(jsonDecode(saved!), {'tab': 'capture'});
  });

  testWidgets('a restart reopens the file that was open', (tester) async {
    late String id;
    late String file;
    await tester.runAsync(() async {
      await library.load();
      final event = await library.create([
        img.encodeJpg(img.Image(width: 8, height: 8)),
        img.encodeJpg(img.Image(width: 8, height: 8)),
      ]);
      id = event.id;
      file = event.pages.last.id;
      await library.writeMeta(
        PlaceMemory.metaName,
        jsonEncode({'tab': 'home', 'event': id, 'file': file}),
      );
    });
    await tester.pumpWidget(TabCamApp(library: library));
    await tester.runAsync(
      () => Future<void>.delayed(const Duration(milliseconds: 50)),
    );
    await frames(tester);
    expect(find.byType(FileScreen), findsOneWidget);
    expect(find.text('Page 2'), findsOneWidget);
    expect(PlaceMemory.of(library).place.fileId, file);

    // Back on the list, it's forgotten.
    await tester.pageBack();
    await frames(tester);
    expect(find.byType(FileScreen), findsNothing);
    expect(PlaceMemory.of(library).place.fileId, isNull);
    expect(PlaceMemory.of(library).place.eventId, id);
  });

  test('a place reads back as it was written', () {
    const place = Place(tab: 'home', eventId: 'abc', text: true, fileId: 'f');
    final back = Place.fromJson(jsonDecode(jsonEncode(place.toJson())));
    expect(
      (back.tab, back.eventId, back.text, back.fileId),
      ('home', 'abc', true, 'f'),
    );
  });
}
