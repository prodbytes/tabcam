import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:tabscan_app/library/event_store_memory.dart';
import 'package:tabscan_app/library/library.dart';
import 'package:tabscan_app/screens/tab_text_screen.dart';

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
      MaterialApp(home: TabTextScreen(library: library, eventId: event.id)),
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
}
