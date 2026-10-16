import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:tabcam_app/library/event_store_memory.dart';
import 'package:tabcam_app/library/library.dart';
import 'package:tabcam_app/screens/tab_text_view.dart';

void main() {
  testWidgets('Copy at the top puts the tab on the clipboard', (tester) async {
    const riff = 'e|--3--5--|\nB|-5------|';
    final library = Library(PlatformEventStore());
    await library.load();
    final event = await library.update(
      (await library.create(const [])).copyWith(tabText: riff),
    );

    String? copied;
    tester.binding.defaultBinaryMessenger.setMockMethodCallHandler(
      SystemChannels.platform,
      (call) async {
        if (call.method == 'Clipboard.setData') {
          copied = (call.arguments as Map)['text'] as String?;
        }
        return null;
      },
    );
    addTearDown(
      () => tester.binding.defaultBinaryMessenger.setMockMethodCallHandler(
        SystemChannels.platform,
        null,
      ),
    );

    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          appBar: AppBar(),
          body: TabTextView(library: library, eventId: event.id),
        ),
      ),
    );

    final copy = find.widgetWithText(FilledButton, 'Copy');
    expect(copy, findsOneWidget);
    // Above the text, not in the app bar.
    expect(
      tester.getTopLeft(copy).dy,
      lessThan(tester.getTopLeft(find.byType(TextField)).dy),
    );
    expect(
      find.descendant(of: find.byType(AppBar), matching: copy),
      findsNothing,
    );

    await tester.tap(copy);
    await tester.pump();
    expect(copied, riff);
    expect(find.text('Tab copied'), findsOneWidget);
  });

  testWidgets('an edit is saved, and makes the text the user\'s', (
    tester,
  ) async {
    final library = Library(PlatformEventStore());
    await library.load();
    final event = await library.update(
      (await library.create(const []))
          .copyWith(tabText: 'e|--0--|', tabTextAuto: true),
    );
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: TabTextView(library: library, eventId: event.id),
        ),
      ),
    );
    await tester.enterText(find.byType(TextField), 'e|--2--|');
    await tester.pump(const Duration(seconds: 2));
    final saved = library.byId(event.id)!;
    expect(saved.tabText, 'e|--2--|');
    expect(saved.tabTextAuto, isFalse);
  });

  testWidgets('a read that ends while it shows fills the text in', (
    tester,
  ) async {
    final library = Library(PlatformEventStore());
    await library.load();
    final event = await library.create(const []);
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: TabTextView(library: library, eventId: event.id),
        ),
      ),
    );
    await tester.runAsync(
      () => library.update(
        library
            .byId(event.id)!
            .copyWith(tabText: 'G|--5--|', tabTextAuto: true),
      ),
    );
    await tester.pump();
    final field = tester.widget<TextField>(find.byType(TextField));
    expect(field.controller!.text, 'G|--5--|');
  });
}
