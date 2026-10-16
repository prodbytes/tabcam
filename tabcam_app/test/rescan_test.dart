import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:image/image.dart' as img;
import 'package:tabcam_app/l10n/app_localizations.dart';
import 'package:tabcam_app/library/event_store_memory.dart';
import 'package:tabcam_app/library/library.dart';
import 'package:tabcam_app/recognition/auto_reader.dart';
import 'package:tabcam_app/screens/event_screen.dart';

/// The Text view's Rescan reads every page again. The text stays while it
/// reads (the view spins); a tab found replaces it, even one the user
/// edited and marked verified; none found keeps it, with a message.
void main() {
  Future<(Library, AutoReader, String, void Function(Completer<String?>))>
  setUp(WidgetTester tester, void Function() onRead) async {
    var reading = Completer<String?>();
    late Library library;
    late AutoReader reader;
    late String id;
    await tester.runAsync(() async {
      library = Library(PlatformEventStore(), null, (_) async => null);
      reader = AutoReader(
        library: library,
        supported: true,
        read: (_) {
          onRead();
          return reading.future;
        },
      );
      await library.load();
      await reader.start();
      final event = await library.create([
        img.encodeJpg(img.Image(width: 8, height: 8)),
      ]);
      id = event.id;
    });
    return (library, reader, id, (Completer<String?> c) => reading = c);
  }

  testWidgets('Rescan replaces an edited, verified text', (tester) async {
    var reading = Completer<String?>();
    var reads = 0;
    late Library library;
    late AutoReader reader;
    late String id;
    await tester.runAsync(() async {
      library = Library(PlatformEventStore(), null, (_) async => null);
      reader = AutoReader(
        library: library,
        supported: true,
        read: (_) {
          reads++;
          return reading.future;
        },
      );
      await library.load();
      await reader.start();
      final event = await library.create([
        img.encodeJpg(img.Image(width: 8, height: 8)),
      ]);
      id = event.id;
    });
    Future<void> settle() async {
      await tester.runAsync(
        () => Future<void>.delayed(const Duration(milliseconds: 50)),
      );
      await tester.pump();
    }

    // Made-up riffs. The first reading, then the user's edit and mark.
    reading.complete('e|--0--3--|');
    await settle();
    await tester.runAsync(
      () => library.patch(
        id,
        (now) => now.copyWith(
          tabText: 'e|--0--5--|',
          tabTextAuto: false,
          tabTextCorrect: true,
        ),
      ),
    );

    await tester.pumpWidget(
      MaterialApp(
        localizationsDelegates: AppLocalizations.localizationsDelegates,
        supportedLocales: AppLocalizations.supportedLocales,
        home: AutoReaderScope(
          notifier: reader,
          child: EventScreen(library: library, eventId: id),
        ),
      ),
    );
    await tester.pumpAndSettle();
    // Verified: it opens on its text.
    expect(find.text('e|--0--5--|'), findsWidgets);

    // Cancel keeps it.
    await tester.tap(find.text('Rescan'));
    await tester.pumpAndSettle();
    expect(find.text('Rescan the pages?'), findsOneWidget);
    await tester.tap(find.text('Cancel'));
    await tester.pumpAndSettle();
    expect(library.byId(id)!.tabText, 'e|--0--5--|');

    reading = Completer<String?>();
    await tester.tap(find.text('Rescan'));
    await tester.pumpAndSettle();
    await tester.tap(
      find.descendant(
        of: find.byType(AlertDialog),
        matching: find.widgetWithText(FilledButton, 'Rescan'),
      ),
    );
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 300));
    for (var i = 0; i < 4; i++) {
      await settle();
    }
    expect(reads, 2);
    // Kept, and still marked, while it reads; the view spins.
    expect(library.byId(id)!.tabText, 'e|--0--5--|');
    expect(library.byId(id)!.tabTextCorrect, isTrue);
    expect(find.text('Rescanning the pages…'), findsOneWidget);
    expect(find.byType(LinearProgressIndicator), findsOneWidget);

    reading.complete('A|--2--5--|');
    await settle();
    await settle();
    final event = library.byId(id)!;
    expect(event.tabText, 'A|--2--5--|');
    expect(event.tabTextAuto, isTrue);
    expect(event.tabTextCorrect, isFalse);
    expect(find.text('A|--2--5--|'), findsWidgets);
    expect(find.text('Rescanning the pages…'), findsNothing);

    await tester.pumpWidget(const SizedBox());
    await tester.pump(const Duration(seconds: 5));
  });

  testWidgets('Rescan finding no tab keeps the text, with a message', (
    tester,
  ) async {
    final (library, reader, id, setReading) = await setUp(tester, () {});
    var reading = Completer<String?>();
    setReading(reading);
    Future<void> settle() async {
      await tester.runAsync(
        () => Future<void>.delayed(const Duration(milliseconds: 50)),
      );
      await tester.pump();
    }

    // Made-up riffs: the first reading, then the user's edit and mark.
    reading.complete('e|--0--3--|');
    await settle();
    await tester.runAsync(
      () => library.patch(
        id,
        (now) => now.copyWith(
          tabText: 'e|--0--7--|',
          tabTextAuto: false,
          tabTextCorrect: true,
        ),
      ),
    );
    await tester.pumpWidget(
      MaterialApp(
        localizationsDelegates: AppLocalizations.localizationsDelegates,
        supportedLocales: AppLocalizations.supportedLocales,
        home: AutoReaderScope(
          notifier: reader,
          child: EventScreen(library: library, eventId: id),
        ),
      ),
    );
    await tester.pumpAndSettle();

    reading = Completer<String?>();
    setReading(reading);
    await tester.tap(find.text('Rescan'));
    await tester.pumpAndSettle();
    await tester.tap(
      find.descendant(
        of: find.byType(AlertDialog),
        matching: find.widgetWithText(FilledButton, 'Rescan'),
      ),
    );
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 300));
    await settle();
    expect(find.text('Rescanning the pages…'), findsOneWidget);

    reading.complete(null); // no tab in the pages
    await settle();
    await settle();
    final event = library.byId(id)!;
    expect(event.tabText, 'e|--0--7--|');
    expect(event.tabTextAuto, isFalse);
    expect(event.tabTextCorrect, isTrue);
    expect(find.text('e|--0--7--|'), findsWidgets);
    expect(find.text('Rescanning the pages…'), findsNothing);
    expect(find.textContaining('No tab found in the pages.'), findsOneWidget);
    expect(find.textContaining('The text was kept.'), findsOneWidget);

    await tester.pumpWidget(const SizedBox());
    await tester.pump(const Duration(seconds: 5));
  });
}
