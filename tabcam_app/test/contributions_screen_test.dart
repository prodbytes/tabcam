import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:image/image.dart' as img;
import 'package:tabcam_app/l10n/app_localizations.dart';
import 'package:tabcam_app/library/capture_event.dart';
import 'package:tabcam_app/library/event_store_memory.dart';
import 'package:tabcam_app/library/library.dart';
import 'package:tabcam_app/screens/event_screen.dart';

Future<void> _frames(WidgetTester tester) async {
  for (var i = 0; i < 20; i++) {
    await tester.pump(const Duration(milliseconds: 50));
  }
}

void main() {
  final jpeg = Uint8List.fromList(
    img.encodeJpg(img.Image(width: 8, height: 8)),
  );
  final cover = EventPage.link(
    id: 'cover1',
    url: Uri.parse('https://example.com/ana-cover'),
    title: "Ana's cover",
  );

  Future<(Library, String)> lesson(
    WidgetTester tester, {
    bool reader = false,
  }) async {
    final library = Library(PlatformEventStore(), null, (_) async => null);
    late String id;
    await tester.runAsync(() async {
      await library.load();
      final made = await library.create([jpeg]);
      id = made.id;
      if (reader) {
        await library.applyRemote(
          made.copyWith(sharedBy: 'julio@example.com', readOnly: true),
        );
      }
      await library.applyContribution(
        id,
        Contribution(
          by: reader ? null : 'us-east-1:ana',
          updated: DateTime(2026, 10, 16),
          pages: [cover],
        ),
      );
      if (!reader) {
        await library.nameContributions(
          id,
          emails: {'us-east-1:ana': 'ana@example.com'},
        );
      }
    });
    await tester.pumpWidget(
      MaterialApp(
        localizationsDelegates: AppLocalizations.localizationsDelegates,
        supportedLocales: AppLocalizations.supportedLocales,
        home: EventScreen(library: library, eventId: id),
      ),
    );
    await _frames(tester);
    return (library, id);
  }

  testWidgets("the owner sees a student's files and publishes one", (
    tester,
  ) async {
    final (library, id) = await lesson(tester);
    expect(find.text('From ana@example.com'), findsOneWidget);
    expect(
      find.text('Only you see these until you publish them'),
      findsOneWidget,
    );
    expect(find.text("Ana's cover"), findsOneWidget);

    await tester.runAsync(() async {
      await tester.tap(find.byKey(const ValueKey('publish-cover1')));
      await Future<void>.delayed(const Duration(milliseconds: 100));
    });
    await _frames(tester);
    final event = library.byId(id)!;
    expect(event.isPublished(cover), isTrue);
    // In the capture's own list now, and marked Published in hers.
    expect(find.text("Ana's cover"), findsNWidgets(2));
    expect(find.text('Published'), findsOneWidget);

    await tester.runAsync(() async {
      await tester.tap(find.byKey(const ValueKey('publish-cover1')));
      await Future<void>.delayed(const Duration(milliseconds: 100));
    });
    await _frames(tester);
    expect(library.byId(id)!.isPublished(cover), isFalse);
    expect(library.byId(id)!.contributions.single.pages, [cover]);
  });

  testWidgets('a reader adds and deletes their own files, and sees '
      "who else sees them", (tester) async {
    final (library, id) = await lesson(tester, reader: true);
    expect(
      find.text('Shared by julio@example.com · Can view and add'),
      findsOneWidget,
    );
    expect(find.text('Your files'), findsOneWidget);
    expect(
      find.text('Only you and julio@example.com see these'),
      findsOneWidget,
    );
    expect(find.byKey(const ValueKey('publish-cover1')), findsNothing);

    await tester.tap(find.byKey(const ValueKey('delete-contribution-cover1')));
    await _frames(tester);
    await tester.runAsync(() async {
      await tester.tap(find.text('Delete'));
      await Future<void>.delayed(const Duration(milliseconds: 100));
    });
    await _frames(tester);
    expect(library.byId(id)!.myContribution!.pages, isEmpty);
    expect(library.byId(id)!.pages, hasLength(1));
  });
}
