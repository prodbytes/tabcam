import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:tabcam_app/library/capture_event.dart';
import 'package:tabcam_app/library/event_store_memory.dart';
import 'package:tabcam_app/library/library.dart';
import 'package:tabcam_app/recognition/tab_doubts.dart';
import 'package:tabcam_app/screens/tab_text_view.dart';

// A made-up riff: tests never use published songs' tabs.
const _riff = 'Verse\ne|-3---5h7-|\nB|---10----|\n';
const _doubts = [TabDoubt(1, 7, '5h7'), TabDoubt(2, 5, '10')];

/// The red parts of the Text view's text.
List<String> _red(WidgetTester tester) {
  final field = tester.widget<EditableText>(find.byType(EditableText));
  final span = field.controller.buildTextSpan(
    context: tester.element(find.byType(EditableText)),
    withComposing: false,
  );
  final out = <String>[];
  span.visitChildren((s) {
    if (s is TextSpan && s.style?.fontWeight == FontWeight.bold) {
      out.add(s.text!);
    }
    return true;
  });
  return out;
}

void main() {
  test('a doubt stands while its note is where it was read', () {
    expect(doubtRanges(_riff, _doubts), [(13, 16), (24, 26)]);
    // Fixed (another note there), or now part of a longer number: gone.
    final fixed = _riff.replaceFirst('5h7', '5h8').replaceFirst('10', '105');
    expect(doubtRanges(fixed, _doubts), isEmpty);
    expect(standingDoubts(fixed, _doubts), isEmpty);
    expect(standingDoubts(_riff, _doubts), _doubts);
    // Past the text's end, or a line too far: no doubt, no error.
    expect(doubtRanges('e|-3-|', _doubts), isEmpty);
  });

  test('the cursor on a red note, or right beside it, finds it', () {
    // "5h7" is at 13..16 on its line (6..17), "10" at 24..26 on its own.
    for (final at in [12, 13, 15, 16, 17]) {
      expect(doubtAt(_riff, _doubts, at), _doubts.first, reason: '$at');
    }
    for (final at in [23, 24, 26, 27]) {
      expect(doubtAt(_riff, _doubts, at), _doubts.last, reason: '$at');
    }
    // Two away, or past the line's end: none.
    for (final at in [3, 11, 18, 22, 28]) {
      expect(doubtAt(_riff, _doubts, at), isNull, reason: '$at');
    }
    // A note the user changed isn't doubtful any more.
    expect(doubtAt(_riff.replaceFirst('10', '12'), _doubts, 24), isNull);
  });

  test('doubts are saved with the event, and odd ones are dropped', () {
    final event = CaptureEvent(
      id: 'e1',
      title: 'Riff',
      created: DateTime.utc(2026, 10, 16),
      tabText: _riff,
      tabTextDoubts: _doubts,
    );
    final json = event.toJson();
    expect(json['tabTextDoubts'], [
      [1, 7, '5h7'],
      [2, 5, '10'],
    ]);
    expect(CaptureEvent.fromJson(json).tabTextDoubts, _doubts);
    json['tabTextDoubts'] = [
      [1, 7, '5h7'],
      [-1, 0, 'x'],
      'nonsense',
    ];
    expect(CaptureEvent.fromJson(json).tabTextDoubts, [_doubts.first]);
    // None: nothing saved.
    expect(
      event.copyWith(tabTextDoubts: const []).toJson(),
      isNot(contains('tabTextDoubts')),
    );
  });

  testWidgets(
    'the Text view shows doubtful notes in red until they are fixed',
    (tester) async {
      final library = Library(PlatformEventStore());
      await library.load();
      final event = await library.update(
        (await library.create(
          const [],
        )).copyWith(tabText: _riff, tabTextAuto: true, tabTextDoubts: _doubts),
      );
      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: TabTextView(library: library, eventId: event.id),
          ),
        ),
      );
      expect(_red(tester), ['5h7', '10']);

      // The user fixes one: it's no longer red, nor saved as doubtful.
      await tester.enterText(
        find.byType(TextField),
        _riff.replaceFirst('10', '12'),
      );
      await tester.pump(const Duration(seconds: 2));
      expect(_red(tester), ['5h7']);
      expect(library.byId(event.id)!.tabTextDoubts, [_doubts.first]);

      // A tap right beside the other one: the user looked at it, so it
      // isn't red any more, nor saved as doubtful.
      final field = tester.widget<TextField>(find.byType(TextField));
      field.controller!.selection = const TextSelection.collapsed(offset: 17);
      field.onTap!();
      await tester.pump(const Duration(seconds: 2));
      expect(_red(tester), isEmpty);
      expect(library.byId(event.id)!.tabTextDoubts, isEmpty);
      expect(library.byId(event.id)!.tabText, _riff.replaceFirst('10', '12'));

      // Verified: the user checked it, nothing is red.
      await tester.tap(find.text('Verified'));
      await tester.pumpAndSettle();
      expect(_red(tester), isEmpty);
    },
  );
}
