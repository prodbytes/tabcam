import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:image/image.dart' as img;
import 'package:tabcam_app/l10n/app_localizations.dart';
import 'package:tabcam_app/library/event_store_memory.dart';
import 'package:tabcam_app/library/library.dart';
import 'package:tabcam_app/recognition/auto_reader.dart';
import 'package:tabcam_app/screens/event_screen.dart';

/// The Text view's Rescan deletes the text tab, even one the user edited
/// and marked verified, and reads every page again into it.
void main() {
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
    // Deleted, and unmarked, while it reads.
    expect(library.byId(id)!.tabText, '');
    expect(library.byId(id)!.tabTextCorrect, isFalse);
    expect(find.text('Reading the tab…'), findsOneWidget);

    reading.complete('A|--2--5--|');
    await settle();
    await settle();
    final event = library.byId(id)!;
    expect(event.tabText, 'A|--2--5--|');
    expect(event.tabTextAuto, isTrue);
    expect(find.text('A|--2--5--|'), findsWidgets);

    await tester.pumpWidget(const SizedBox());
    await tester.pump(const Duration(seconds: 5));
  });
}
