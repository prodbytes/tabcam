import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:image/image.dart' as img;
import 'package:tabcam_app/l10n/app_localizations.dart';
import 'package:tabcam_app/library/event_store_memory.dart';
import 'package:tabcam_app/library/library.dart';
import 'package:tabcam_app/recognition/auto_reader.dart';
import 'package:tabcam_app/screens/event_screen.dart';

/// The Text tool only opens the Text view: tapped again there, it doesn't
/// read the tab again (that's the Text view's Rescan).
void main() {
  testWidgets('the Text tool opens the Text view, and reads nothing again', (
    tester,
  ) async {
    var reading = Completer<String?>();
    var reads = 0;
    late Library library;
    late AutoReader reader;
    late String id;
    // Made in the real zone, where they're awaited.
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
      id = (await library.create([
        img.encodeJpg(img.Image(width: 8, height: 8)),
      ])).id;
    });

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
    await tester.pump();

    final tool = find.byKey(const Key('text'));
    final spinner = find.descendant(
      of: tool,
      matching: find.byKey(const Key('tool-working')),
    );
    Future<void> settle() async {
      await tester.runAsync(
        () => Future<void>.delayed(const Duration(milliseconds: 50)),
      );
      await tester.pump();
    }

    // Made-up riffs.
    reading.complete('e|--0--3--|');
    await settle();
    expect(reads, 1);
    expect(spinner, findsNothing);

    // From the Files view: the Text view, nothing asked.
    await tester.tap(tool);
    await tester.pumpAndSettle();
    expect(find.text('Read the tab again?'), findsNothing);
    expect(find.text('e|--0--3--|'), findsWidgets);

    // Again: nothing asked, nothing read.
    await tester.tap(tool);
    await tester.pumpAndSettle();
    await settle();
    expect(find.byType(AlertDialog), findsNothing);
    expect(reads, 1);
    expect(spinner, findsNothing);
    expect(find.text('e|--0--3--|'), findsWidgets);

    await tester.pumpWidget(const SizedBox());
    await tester.pump(const Duration(seconds: 5));
  });
}
