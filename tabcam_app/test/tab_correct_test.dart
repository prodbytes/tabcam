import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:image/image.dart' as img;
import 'package:tabcam_app/library/capture_event.dart';
import 'package:tabcam_app/library/event_store_memory.dart';
import 'package:tabcam_app/library/library.dart';
import 'package:tabcam_app/screens/event_screen.dart';
import 'package:tabcam_app/screens/tab_text_view.dart';

const _riff = 'e|--3--5--|\nB|-5------|';

/// A library with one single-page event, its text tab [_riff].
Future<(Library, CaptureEvent)> _event(
  WidgetTester tester, {
  bool correct = false,
  bool readOnly = false,
}) async {
  final library = Library(PlatformEventStore());
  late CaptureEvent event;
  await tester.runAsync(() async {
    await library.load();
    final page = img.encodeJpg(img.Image(width: 8, height: 8));
    event = await library.update(
      (await library.create([
        page,
      ])).copyWith(tabText: _riff, tabTextCorrect: correct, readOnly: readOnly),
    );
  });
  return (library, event);
}

void main() {
  test('the mark is saved with the event, and off by default', () {
    final event = CaptureEvent(
      id: 'abc',
      title: 'Riff',
      created: DateTime.utc(2026, 10, 10),
      tabText: _riff,
    );
    expect(event.toJson().containsKey('tabTextCorrect'), isFalse);
    expect(CaptureEvent.fromJson(event.toJson()).tabTextCorrect, isFalse);
    final marked = event.copyWith(tabTextCorrect: true);
    expect(marked.toJson(local: false)['tabTextCorrect'], isTrue);
    expect(CaptureEvent.fromJson(marked.toJson()).tabTextCorrect, isTrue);
  });

  testWidgets('the text tab is marked correct, and unmarked', (tester) async {
    final (library, event) = await _event(tester);
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: TabTextView(library: library, eventId: event.id),
        ),
      ),
    );

    await tester.runAsync(() => tester.tap(find.text('Verified')));
    await tester.pump();
    expect(library.byId(event.id)!.tabTextCorrect, isTrue);
    expect(find.text('Verified'), findsOneWidget);

    await tester.runAsync(() => tester.tap(find.text('Verified')));
    await tester.pump();
    expect(library.byId(event.id)!.tabTextCorrect, isFalse);
    expect(find.text('Verified'), findsOneWidget);
  });

  testWidgets('read only, the mark is shown but not changed', (tester) async {
    var (library, event) = await _event(tester, readOnly: true);
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: TabTextView(library: library, eventId: event.id),
        ),
      ),
    );
    expect(find.text('Verified'), findsNothing);

    (library, event) = await _event(tester, readOnly: true, correct: true);
    await tester.pumpWidget(
      MaterialApp(
        key: UniqueKey(),
        home: Scaffold(
          body: TabTextView(library: library, eventId: event.id),
        ),
      ),
    );
    await tester.tap(find.text('Verified'));
    await tester.pump();
    expect(library.byId(event.id)!.tabTextCorrect, isTrue);
  });

  testWidgets('an event marked correct opens on its text tab', (tester) async {
    final (library, event) = await _event(tester, correct: true);
    await tester.pumpWidget(
      MaterialApp(
        home: EventScreen(library: library, eventId: event.id),
      ),
    );
    await tester.pump();
    await tester.pump(const Duration(seconds: 1));
    expect(find.byType(TabTextView), findsOneWidget);

    // The files are the Files tool away.
    await tester.tap(find.byKey(const Key('files')));
    await tester.pump();
    await tester.pump(const Duration(seconds: 1));
    expect(find.byType(TabTextView), findsNothing);
    expect(find.text('Page 1'), findsOneWidget);
  });

  testWidgets('an event not marked correct opens on its files', (tester) async {
    final (library, event) = await _event(tester);
    await tester.pumpWidget(
      MaterialApp(
        home: EventScreen(library: library, eventId: event.id),
      ),
    );
    await tester.pump();
    await tester.pump(const Duration(seconds: 1));
    expect(find.byType(TabTextView), findsNothing);
    expect(find.text('Page 1'), findsOneWidget);
  });
}
