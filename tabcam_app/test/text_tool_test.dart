import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:image/image.dart' as img;
import 'package:tabcam_app/l10n/app_localizations.dart';
import 'package:tabcam_app/library/event_store_memory.dart';
import 'package:tabcam_app/library/library.dart';
import 'package:tabcam_app/recognition/auto_reader.dart';
import 'package:tabcam_app/screens/event_screen.dart';

/// The Text tool says how the tab stands: a spinner while it's read, as
/// usual once there's text, greyed out without one.
void main() {
  testWidgets('the Text tool: reading, read, no tab found, deleted', (
    tester,
  ) async {
    var reading = Completer<String?>();
    late Library library;
    late AutoReader reader;
    late String id;
    // Made in the real zone, where they're awaited.
    await tester.runAsync(() async {
      library = Library(PlatformEventStore(), null, (_) async => null);
      reader = AutoReader(
        library: library,
        supported: true,
        read: (_) => reading.future,
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
    Color? iconColor() => tester
        .widget<Icon>(find.descendant(of: tool, matching: find.byType(Icon)))
        .color;
    Future<void> settle() async {
      await tester.runAsync(
        () => Future<void>.delayed(const Duration(milliseconds: 50)),
      );
      await tester.pump();
    }

    // Being read: a spinner, and it says so.
    expect(spinner, findsOneWidget);
    expect(find.byTooltip('Reading the tab…'), findsOneWidget);

    // Read: the icon as usual.
    reading.complete('e|--0--3--|');
    await settle();
    expect(spinner, findsNothing);
    expect(iconColor(), isNull);

    // The text deleted: greyed out.
    await tester.runAsync(
      () => library.patch(id, (e) => e.copyWith(tabText: '')),
    );
    await settle();
    expect(iconColor(), isNotNull);

    // Read again, and no tab found: greyed out, and still opens the Text
    // view.
    reading = Completer<String?>();
    reader.readSoon(id, again: true);
    await tester.pump();
    expect(spinner, findsOneWidget);
    reading.complete(null);
    await settle();
    expect(spinner, findsNothing);
    expect(iconColor(), isNotNull);
    await tester.tap(tool);
    await tester.pump();
    expect(
      tester
          .widget<IconButton>(
            find.descendant(of: tool, matching: find.byType(IconButton)),
          )
          .isSelected,
      isTrue,
    );
    await tester.pumpWidget(const SizedBox());
    await tester.pump(const Duration(seconds: 5));
  });
}
