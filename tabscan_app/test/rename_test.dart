import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:image/image.dart' as img;
import 'package:tabscan_app/library/library.dart';
import 'package:tabscan_app/library/event_store_memory.dart';
import 'package:tabscan_app/main.dart';

/// Lets animations (menus, dialogs) finish. Not pumpAndSettle: the card's
/// thumbnail spinner never settles in a test.
Future<void> _frames(WidgetTester tester) async {
  for (var i = 0; i < 20; i++) {
    await tester.pump(const Duration(milliseconds: 50));
  }
}

void main() {
  testWidgets('an event is renamed from its card in the list', (tester) async {
    final library = Library(PlatformEventStore());
    late String id;
    await tester.runAsync(() async {
      await library.load();
      final page = img.encodeJpg(img.Image(width: 8, height: 8));
      id = (await library.create([page])).id;
    });
    await tester.pumpWidget(TabScanApp(library: library));
    await tester.pump();

    await tester.tap(find.byTooltip('More'));
    await _frames(tester);
    await tester.tap(find.text('Rename'));
    await _frames(tester);

    // One Name field, its text selected, so typing replaces it.
    expect(find.byType(TextField), findsOneWidget);
    final name = tester.widget<TextField>(find.byType(TextField));
    expect(
      name.controller!.selection.textInside(name.controller!.text),
      library.byId(id)!.title,
    );

    // Whatever the user types is the name; no artist is kept beside it.
    await library.update(library.byId(id)!.copyWith(artist: 'Someone'));
    await tester.enterText(find.byType(TextField), 'my practice riff #2');
    await tester.tap(find.text('Save'));
    await _frames(tester);

    expect(library.byId(id)!.title, 'my practice riff #2');
    expect(library.byId(id)!.artist, '');
    expect(find.text('my practice riff #2'), findsOneWidget);
  });
}
