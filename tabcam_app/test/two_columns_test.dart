import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:tabcam_app/library/event_store_memory.dart';
import 'package:tabcam_app/library/library.dart';
import 'package:tabcam_app/screens/tab_editing.dart';
import 'package:tabcam_app/screens/tab_text_view.dart';

/// A made-up riff of four phrases, a blank line between them.
const _phrase = 'e|--3--5--|\nB|-5------|\nG|--------|';
const _riff = 'Intro\n$_phrase\n\n$_phrase\n\nVerse\n$_phrase\n\n$_phrase\n';

(String, String) _halves(String text) {
  final s = splitInHalf(text)!;
  return (text.substring(0, s.leftEnd), text.substring(s.rightStart));
}

void main() {
  group('splitInHalf', () {
    test('breaks at the blank line nearest the middle', () {
      final (left, right) = _halves(_riff);
      expect(left, 'Intro\n$_phrase\n\n$_phrase');
      expect(right, 'Verse\n$_phrase\n\n$_phrase\n');
    });

    test('never cuts a phrase: breaks between two that touch', () {
      const text = '$_phrase\n$_phrase';
      final (left, right) = _halves(text);
      expect(left, _phrase);
      expect(right, _phrase);
    });

    test('no blank line and only string lines: the middle line', () {
      const text = 'e|--1--|\nB|--2--|\nG|--3--|\nD|--4--|';
      final (left, right) = _halves(text);
      expect(left, 'e|--1--|\nB|--2--|');
      expect(right, 'G|--3--|\nD|--4--|');
    });

    test('nothing to break: fewer than two lines with text', () {
      expect(splitInHalf(''), isNull);
      expect(splitInHalf('e|--3--|\n\n'), isNull);
    });
  });

  testWidgets('Two columns shows the tab split in half, to read', (
    tester,
  ) async {
    tester.view.physicalSize = const Size(1400, 900);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);
    final library = Library(PlatformEventStore());
    await library.load();
    final event = await library.update(
      (await library.create(const [])).copyWith(tabText: _riff),
    );
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: TabTextView(library: library, eventId: event.id),
        ),
      ),
    );

    final toggle = find.byKey(const Key('text-columns'));
    expect(toggle, findsOneWidget);
    expect(find.byKey(const Key('text-new-phrase')), findsOneWidget);

    await tester.tap(toggle);
    await tester.pumpAndSettle();
    // No editor and no editing tools while it's on.
    expect(find.byType(TextField), findsNothing);
    expect(find.byKey(const Key('text-new-phrase')), findsNothing);
    final left = find.byKey(const Key('text-column-left'));
    final right = find.byKey(const Key('text-column-right'));
    expect(
      find.descendant(of: left, matching: find.textContaining('Intro')),
      findsOneWidget,
    );
    expect(
      find.descendant(of: right, matching: find.textContaining('Verse')),
      findsOneWidget,
    );
    // Side by side.
    expect(
      tester.getTopLeft(right).dx,
      greaterThan(tester.getTopLeft(left).dx),
    );
    expect(tester.getTopLeft(right).dy, tester.getTopLeft(left).dy);

    // Off again: back to the editor, the text unchanged.
    await tester.tap(toggle);
    await tester.pumpAndSettle();
    expect(find.byType(TextField), findsOneWidget);
    expect(find.byKey(const Key('text-column-left')), findsNothing);
    expect(library.byId(event.id)!.tabText, _riff);
  });
}
