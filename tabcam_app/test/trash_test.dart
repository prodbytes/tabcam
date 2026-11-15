import 'dart:typed_data';

import 'package:cross_file/cross_file.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:image/image.dart' as img;
import 'package:tabcam_app/capture/media.dart';
import 'package:tabcam_app/l10n/app_localizations.dart';
import 'package:tabcam_app/library/capture_event.dart';
import 'package:tabcam_app/library/event_store_memory.dart';
import 'package:tabcam_app/library/library.dart';
import 'package:tabcam_app/screens/home_screen.dart';
import 'package:tabcam_app/screens/messages.dart';

Uint8List _photo() => img.encodeJpg(img.Image(width: 8, height: 8));

Media _video(List<int> b) => Media(
  XFile.fromData(Uint8List.fromList(b), name: 'riff.mp4'),
  PageKind.video,
  'mp4',
);

/// Deletes never delete files: captures and files go to the trash, to
/// restore, until Profile's Purge.
void main() {
  late Library library;
  setUp(() async {
    library = Library(PlatformEventStore(), null, (_) async => null);
    await library.load();
  });

  test('a deleted capture goes to the trash, files and all, and comes back '
      'restored', () async {
    final event = await library.create([_photo()]);
    await library.delete(event);
    expect(library.events, isEmpty);
    expect(library.byId(event.id), isNull);
    expect(library.trashed.map((e) => e.id), [event.id]);
    expect(library.hasTrash, isTrue);
    expect(await library.hasPage(event.id, event.pages.single), isTrue);
    expect(library.byIdAll(event.id)!.isDeleted, isFalse);

    await library.restore(library.byIdAll(event.id)!);
    expect(library.events.map((e) => e.id), [event.id]);
    expect(library.hasTrash, isFalse);
  });

  test('a deleted file goes to its capture\'s trash with its passes; '
      'restored, it\'s back at the end', () async {
    var event = await library.create([_photo()]);
    event = await library.addMedia(event, [
      _video([1, 2, 3]),
    ]);
    final video = event.pages.last;
    final times = PhraseTimes.none.add(
      const Duration(seconds: 3),
      PassDirection.next,
      1,
    );
    await library.setPhrases(event.id, video.id, times);
    event = await library.deletePage(library.byId(event.id)!, video);
    expect(event.pages, hasLength(1));
    expect(event.deletedPages, [video]);
    expect(await library.hasPage(event.id, video), isTrue);
    expect(library.withDeletedPages.map((e) => e.id), [event.id]);
    // Its passes stay, through other changes too.
    await library.setPhrases(event.id, event.pages.first.id, null);
    expect(library.phrasesOf(event.id, video.id).passes, times.passes);

    event = (await library.restorePage(event.id, video))!;
    expect(event.pages.last, video);
    expect(event.deletedPages, isEmpty);
    expect(library.phrasesOf(event.id, video.id).passes, times.passes);
  });

  test(
    'a replaced file and a turned image keep the old file in the trash',
    () async {
      var event = await library.create([_photo()]);
      event = await library.addMedia(event, [
        _video([1]),
      ]);
      final video = event.pages.last;
      event = await library.replacePage(event, video, _video([2]));
      final image = event.pages.first;
      event = await library.rotatePage(event, image);
      expect(event.deletedPages.map((p) => p.id), [video.id, image.id]);
      expect(await library.hasPage(event.id, video), isTrue);
      expect(await library.hasPage(event.id, image), isTrue);
    },
  );

  test('purge deletes the trash for good: files, trashed captures and '
      'their passes', () async {
    var kept = await library.create([_photo()]);
    kept = await library.addMedia(kept, [
      _video([1]),
    ]);
    final video = kept.pages.last;
    await library.setPhrases(
      kept.id,
      video.id,
      PhraseTimes.none.add(const Duration(seconds: 1), PassDirection.next, 1),
    );
    kept = await library.deletePage(library.byId(kept.id)!, video);
    final gone = await library.create([_photo()]);
    await library.delete(gone);

    await library.purge();
    expect(library.hasTrash, isFalse);
    expect(library.byIdAll(gone.id), isNull); // never synced: no tombstone
    expect(await library.hasPage(gone.id, gone.pages.single), isFalse);
    final now = library.byId(kept.id)!;
    expect(now.deletedPages, isEmpty);
    expect(now.phrases, isEmpty);
    expect(await library.hasPage(kept.id, video), isFalse);
    expect(await library.hasPage(kept.id, now.pages.single), isTrue);
  });

  test('a clone keeps the files it shows of a purged original', () async {
    final original = await library.create([_photo()]);
    final copy = await library.clone(original);
    await library.delete(library.byId(original.id)!);
    // In the trash, the original still has its file: the copy shows it.
    expect(library.byId(copy.id)!.pages.single.source, isNotNull);
    await library.purge();
    final kept = library.byId(copy.id)!;
    expect(kept.pages.single.source, isNull);
    expect(await library.hasPage(kept.id, kept.pages.single), isTrue);
  });

  test("someone else's capture brings none of its owner's trash", () {
    final event = CaptureEvent(
      id: 'abc',
      title: 'Riff',
      created: DateTime(2026, 11, 15),
      deletedPages: const [EventPage(id: 'gone1')],
    );
    expect(event.withOwnFiles().deletedPages, isEmpty);
    final json = CaptureEvent.fromJson(
      event.copyWith(trashed: () => DateTime.utc(2026, 11, 15)).toJson(),
    );
    expect(json.deletedPages.single.id, 'gone1');
    expect(json.trashed, DateTime.utc(2026, 11, 15).toLocal());
  });

  Future<void> frames(WidgetTester tester) async {
    await tester.runAsync(
      () => Future<void>.delayed(const Duration(milliseconds: 20)),
    );
    for (var i = 0; i < 20; i++) {
      await tester.pump(const Duration(milliseconds: 50));
    }
  }

  testWidgets("Profile's Deleted lists the trash to restore, and Purge asks, "
      'then deletes it for good', (tester) async {
    late CaptureEvent gone, kept;
    late EventPage video;
    await tester.runAsync(() async {
      gone = await library.create([_photo()], title: 'Made-up riff');
      await library.delete(gone);
      kept = await library.create([_photo()], title: 'Another riff');
      kept = await library.addMedia(kept, [
        _video([1]),
      ]);
      video = kept.pages.last;
      kept = await library.deletePage(kept, video);
    });
    await tester.pumpWidget(
      MaterialApp(
        localizationsDelegates: AppLocalizations.localizationsDelegates,
        supportedLocales: AppLocalizations.supportedLocales,
        builder: (context, child) => TopMessages(child: child!),
        home: Scaffold(body: ProfileView(library: library)),
      ),
    );
    await frames(tester);
    await tester.scrollUntilVisible(
      find.byKey(const Key('deleted-section')),
      200,
    );
    expect(
      find.text('1 capture, 1 file, kept until you purge them.'),
      findsOneWidget,
    );

    await tester.tap(find.byKey(const Key('trash-show')));
    await frames(tester);
    expect(find.text('Made-up riff'), findsOneWidget);
    expect(find.text('Files deleted from "Another riff"'), findsOneWidget);
    await tester.tap(find.byKey(ValueKey('restore-${gone.id}')));
    await frames(tester);
    expect(library.byId(gone.id), isNotNull);
    expect(find.text('Restored "Made-up riff"'), findsOneWidget);

    // Purge, from the trash screen: it asks; cancelled, nothing goes.
    await tester.tap(find.byKey(const Key('trash-screen-purge')));
    await frames(tester);
    expect(find.text('Purge everything deleted?'), findsOneWidget);
    await tester.tap(find.text('Cancel'));
    await frames(tester);
    expect(library.byId(kept.id)!.deletedPages, [video]);
    await tester.tap(find.byKey(const Key('trash-screen-purge')));
    await frames(tester);
    await tester.tap(find.byKey(const Key('purge-confirm')));
    await frames(tester);
    expect(library.hasTrash, isFalse);
    late bool there;
    await tester.runAsync(
      () async => there = await library.hasPage(kept.id, video),
    );
    expect(there, isFalse);
    // Back on Profile: nothing deleted.
    expect(find.byType(ProfileView), findsOneWidget);
    expect(find.byKey(const Key('trash-purge')), findsNothing);
  });
}
