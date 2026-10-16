import 'dart:typed_data';

import 'package:cross_file/cross_file.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:image/image.dart' as img;
import 'package:tabcam_app/capture/media.dart';
import 'package:tabcam_app/library/capture_event.dart';
import 'package:tabcam_app/library/event_store_memory.dart';
import 'package:tabcam_app/library/library.dart';
import 'package:tabcam_app/screens/event_screen.dart';

Future<void> frames(WidgetTester tester) async {
  for (var i = 0; i < 20; i++) {
    await tester.pump(const Duration(milliseconds: 50));
  }
}

Media _file(String name, PageKind kind, String ext) =>
    Media(XFile.fromData(Uint8List.fromList([1]), path: name), kind, ext);

void main() {
  late Library library;
  setUp(() => library = Library(PlatformEventStore(), null, (_) async => null));

  test('a file is named after its file; a page can be renamed', () async {
    await library.load();
    var event = await library.addMedia(await library.create(const []), [
      _file('Lesson 3.pdf', PageKind.pdf, 'pdf'),
      _file('riff take 2.m4a', PageKind.audio, 'm4a'),
    ]);
    expect(event.pages.map((p) => p.title), ['Lesson 3', 'riff take 2']);

    final pdf = event.pages.first;
    event = (await library.renamePage(event.id, pdf.id, '  Intro  '))!;
    expect(event.pages.first.title, 'Intro');
    // Emptied, it goes back to its default name.
    event = (await library.renamePage(event.id, pdf.id, ' '))!;
    expect(event.pages.first.title, isNull);
    expect(event.pages.last.title, 'riff take 2');
  });

  test('names from file names', () {
    expect(nameOfFile('Lesson 3.pdf'), 'Lesson 3');
    expect(nameOfFile('/tmp/a/riff.v2.m4a'), 'riff.v2');
    expect(nameOfFile('.pdf'), '.pdf');
    expect(nameOfFile(''), isNull);
  });

  Future<String> open(WidgetTester tester, {bool readOnly = false}) async {
    late String id;
    await tester.runAsync(() async {
      await library.load();
      var event = await library.create([
        img.encodeJpg(img.Image(width: 8, height: 8)),
      ]);
      event = await library.addLink(
        event,
        Uri.parse('https://example.com/lesson'),
      );
      if (readOnly) {
        event = await library.update(event.copyWith(readOnly: true));
      }
      id = event.id;
    });
    await tester.pumpWidget(
      MaterialApp(
        home: EventScreen(library: library, eventId: id),
      ),
    );
    await frames(tester);
    return id;
  }

  testWidgets('every file in a capture can be renamed from its list', (
    tester,
  ) async {
    final id = await open(tester);
    final event = library.byId(id)!;
    final link = event.pages.last;
    expect(find.text('example.com'), findsOneWidget);

    await tester.tap(find.byKey(ValueKey('rename-${link.id}')));
    await frames(tester);
    await tester.enterText(find.byType(TextField), 'Lesson one');
    await tester.tap(find.text('Save'));
    await tester.runAsync(
      () => Future<void>.delayed(const Duration(milliseconds: 20)),
    );
    await frames(tester);
    expect(library.byId(id)!.pages.last.title, 'Lesson one');
    expect(find.text('Lesson one'), findsOneWidget);

    // The photo too.
    final photo = event.pages.first;
    await tester.tap(find.byKey(ValueKey('rename-${photo.id}')));
    await frames(tester);
    await tester.enterText(find.byType(TextField), 'Verse');
    await tester.tap(find.text('Save'));
    await tester.runAsync(
      () => Future<void>.delayed(const Duration(milliseconds: 20)),
    );
    await frames(tester);
    expect(library.byId(id)!.pages.first.title, 'Verse');
  });

  /// The file screen's Rename tool, beside Delete.
  IconButton renameTool(WidgetTester tester) => tester.widget<IconButton>(
    find.descendant(
      of: find.byKey(const Key('rename-file')),
      matching: find.byType(IconButton),
    ),
  );

  testWidgets('an opened file is renamed from the tool beside Delete', (
    tester,
  ) async {
    // A narrow phone: View, Rotate, Rename and Delete fit along the bottom.
    tester.view.physicalSize = const Size(320, 640);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);
    final id = await open(tester);
    final photo = library.byId(id)!.pages.first;
    await tester.tap(find.byKey(ValueKey('file-${photo.id}')));
    await frames(tester);

    // Rename sits just before Delete.
    final rename = tester.getCenter(find.byIcon(Icons.edit_outlined));
    final delete = tester.getCenter(find.byIcon(Icons.delete_outline));
    expect(rename.dx, lessThan(delete.dx));
    expect(rename.dy, delete.dy);

    await tester.tap(find.byKey(const Key('rename-file')));
    await frames(tester);
    expect(find.byType(AlertDialog), findsOneWidget);
    await tester.enterText(find.byType(TextField), 'Opening riff');
    await tester.tap(find.text('Save'));
    await tester.runAsync(
      () => Future<void>.delayed(const Duration(milliseconds: 20)),
    );
    await frames(tester);
    expect(library.byId(id)!.pages.first.title, 'Opening riff');
    expect(find.text('Opening riff'), findsWidgets);
    expect(tester.takeException(), isNull);
  });

  testWidgets('a link opened is renamed beside Delete too', (tester) async {
    final id = await open(tester);
    // A tap on a link opens it; its chevron opens it on its own screen.
    final link = library.byId(id)!.pages.last;
    await tester.tap(find.byKey(ValueKey('details-${link.id}')));
    await frames(tester);
    await tester.tap(find.byKey(const Key('rename-file')));
    await frames(tester);
    await tester.enterText(find.byType(TextField), 'The lesson');
    await tester.tap(find.text('Save'));
    await tester.runAsync(
      () => Future<void>.delayed(const Duration(milliseconds: 20)),
    );
    await frames(tester);
    expect(library.byId(id)!.pages.last.title, 'The lesson');
    expect(find.text('The lesson'), findsWidgets);
  });

  testWidgets('a capture shared read only can\'t be renamed', (tester) async {
    final id = await open(tester, readOnly: true);
    final link = library.byId(id)!.pages.last;
    expect(find.byKey(ValueKey('rename-${link.id}')), findsNothing);

    // Opened (Details: tapping a link's row opens the link), its Rename
    // tool (like Delete) is off.
    await tester.tap(find.byKey(ValueKey('details-${link.id}')));
    await frames(tester);
    expect(renameTool(tester).onPressed, isNull);
    await tester.tap(find.byKey(const Key('rename-file')));
    await frames(tester);
    expect(find.byType(AlertDialog), findsNothing);
  });
}
