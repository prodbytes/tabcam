import 'dart:typed_data';

import 'package:desktop_drop/desktop_drop.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:image/image.dart' as img;
import 'package:tabscan_app/l10n/app_localizations.dart';
import 'package:tabscan_app/library/event_store_memory.dart';
import 'package:tabscan_app/library/library.dart';
import 'package:tabscan_app/screens/event_screen.dart';
import 'package:tabscan_app/screens/file_drop_area.dart';

Future<void> _frames(WidgetTester tester) async {
  for (var i = 0; i < 20; i++) {
    await tester.pump(const Duration(milliseconds: 50));
  }
}

/// Drops [files] on the screen, as the platform would.
Future<void> _drop(WidgetTester tester, List<DropItem> files) async {
  final target = tester.widget<DropTarget>(find.byType(DropTarget));
  await tester.runAsync(() async {
    target.onDragDone!(
      DropDoneDetails(
        files: files,
        localPosition: Offset.zero,
        globalPosition: Offset.zero,
      ),
    );
    await Future<void>.delayed(const Duration(milliseconds: 200));
  });
  await _frames(tester);
}

void main() {
  final jpeg = Uint8List.fromList(
    img.encodeJpg(img.Image(width: 8, height: 8)),
  );

  testWidgets('files dropped on a capture are added to it', (tester) async {
    final library = Library(PlatformEventStore(), null, (_) async => null);
    late String id;
    await tester.runAsync(() async {
      await library.load();
      id = (await library.create([jpeg])).id;
    });
    await tester.pumpWidget(
      MaterialApp(
        localizationsDelegates: AppLocalizations.localizationsDelegates,
        supportedLocales: AppLocalizations.supportedLocales,
        home: EventScreen(library: library, eventId: id),
      ),
    );
    await _frames(tester);
    expect(find.byType(FileDropArea), findsOneWidget);

    await _drop(tester, [
      DropItemFile.fromData(jpeg, name: 'riff.jpg', mimeType: 'image/jpeg'),
      DropItemFile.fromData(Uint8List.fromList([1, 2, 3]), name: 'notes.xyz'),
      DropItemDirectory('/tmp/folder', const []),
    ]);

    // The photo is added; the unknown file and the folder are skipped.
    expect(library.byId(id)!.pages, hasLength(2));
    expect(
      find.text("2 files aren't a photo or video, so not added."),
      findsOneWidget,
    );
  });

  testWidgets('a capture shared read only takes no drops', (tester) async {
    final library = Library(PlatformEventStore(), null, (_) async => null);
    late String id;
    await tester.runAsync(() async {
      await library.load();
      final made = await library.create([jpeg]);
      id = made.id;
      await library.applyRemote(
        made.copyWith(sharedBy: 'olga@example.com', readOnly: true),
      );
    });
    await tester.pumpWidget(
      MaterialApp(
        localizationsDelegates: AppLocalizations.localizationsDelegates,
        supportedLocales: AppLocalizations.supportedLocales,
        home: EventScreen(library: library, eventId: id),
      ),
    );
    await _frames(tester);
    expect(tester.widget<DropTarget>(find.byType(DropTarget)).enable, isFalse);
  });
}
