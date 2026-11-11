import 'dart:convert';
import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:image/image.dart' as img;
import 'package:tabcam_app/library/capture_event.dart';
import 'package:tabcam_app/library/event_store_memory.dart';
import 'package:tabcam_app/library/library.dart';
import 'package:tabcam_app/main.dart';
import 'package:tabcam_app/screens/delete_account.dart';
import 'package:tabcam_app/screens/delete_confirm.dart';
import 'package:tabcam_app/screens/event_screen.dart';

/// Lets animations (menus, dialogs) and the store's writes finish. Not
/// pumpAndSettle: a card's thumbnail spinner never settles in a test.
Future<void> _frames(WidgetTester tester) async {
  await tester.runAsync(
    () => Future<void>.delayed(const Duration(milliseconds: 20)),
  );
  for (var i = 0; i < 20; i++) {
    await tester.pump(const Duration(milliseconds: 50));
  }
}

final _dontAsk = find.byKey(const Key('dont-ask-again'));
final _confirm = find.descendant(
  of: find.byType(AlertDialog),
  matching: find.byType(FilledButton),
);

Uint8List _photo() => img.encodeJpg(img.Image(width: 8, height: 8));

/// The web's store with the apps' rule for meta names: on Android, iOS and
/// the desktop a meta is a file named by its name, which must pass
/// [checkId] (event_store_io.dart).
class _AppStore extends PlatformEventStore {
  @override
  Future<String?> readMeta(String name) => super.readMeta(checkId(name));

  @override
  Future<void> writeMeta(String name, String json) =>
      super.writeMeta(checkId(name), json);
}

void main() {
  test('the meta name is one the apps\' store takes', () {
    expect(checkId(DeleteConfirms.metaName), DeleteConfirms.metaName);
  });

  testWidgets('a file\'s delete asks with "Don\'t ask again"; ticked and '
      'cancelled nothing changes, ticked and confirmed it no longer asks', (
    tester,
  ) async {
    final store = _AppStore();
    final library = Library(store);
    late String id;
    await tester.runAsync(() async {
      await library.load();
      var event = await library.create([_photo()]);
      for (final riff in ['riff-a', 'riff-b', 'riff-c']) {
        event = await library.addLink(
          event,
          Uri.parse('https://example.com/$riff'),
        );
      }
      id = event.id;
    });
    await tester.pumpWidget(
      MaterialApp(
        home: EventScreen(library: library, eventId: id),
      ),
    );
    await _frames(tester);
    Finder delete(int i) =>
        find.byKey(ValueKey('delete-${library.byId(id)!.pages[i].id}'));

    // The confirm has the checkbox, unticked.
    await tester.tap(delete(1));
    await _frames(tester);
    expect(find.byType(AlertDialog), findsOneWidget);
    expect(_dontAsk, findsOneWidget);
    expect(find.text("Don't ask again"), findsOneWidget);
    expect(tester.widget<CheckboxListTile>(_dontAsk).value, isFalse);

    // Ticked, then cancelled: nothing deleted, and it still asks.
    await tester.tap(_dontAsk);
    await tester.pump();
    expect(tester.widget<CheckboxListTile>(_dontAsk).value, isTrue);
    await tester.tap(find.text('Cancel'));
    await _frames(tester);
    expect(library.byId(id)!.pages, hasLength(4));
    expect(DeleteConfirms.of(library).asks(DeleteKind.file), isTrue);
    await tester.tap(delete(1));
    await _frames(tester);
    expect(find.byType(AlertDialog), findsOneWidget);
    expect(tester.widget<CheckboxListTile>(_dontAsk).value, isFalse);

    // Ticked and confirmed: deleted, and kept on the device.
    await tester.tap(_dontAsk);
    await tester.pump();
    await tester.tap(_confirm);
    await _frames(tester);
    expect(library.byId(id)!.pages, hasLength(3));
    expect(DeleteConfirms.of(library).asks(DeleteKind.file), isFalse);
    late String? meta;
    await tester.runAsync(
      () async => meta = await library.readMeta(DeleteConfirms.metaName),
    );
    expect(jsonDecode(meta!), {
      'skip': ['file'],
    });

    // The next file's delete doesn't ask: it's deleted at once.
    await tester.tap(delete(1));
    await _frames(tester);
    expect(find.byType(AlertDialog), findsNothing);
    expect(library.byId(id)!.pages, hasLength(2));

    // Another library on the same device's store reads it back.
    final again = Library(store);
    await tester.runAsync(() => DeleteConfirms.of(again).load());
    expect(DeleteConfirms.of(again).asks(DeleteKind.file), isFalse);
    expect(DeleteConfirms.of(again).asks(DeleteKind.capture), isTrue);
  });

  testWidgets('kinds are independent, and Profile\'s Ask before deleting '
      'brings the confirms back', (tester) async {
    final library = Library(PlatformEventStore());
    await tester.runAsync(() async {
      await library.load();
      for (var i = 0; i < 3; i++) {
        await library.create([_photo()]);
      }
      // A file's delete no longer asks.
      await DeleteConfirms.of(library).skip(DeleteKind.file);
    });
    await tester.pumpWidget(TabCamApp(library: library));
    await _frames(tester);

    Future<void> deleteFirstCard() async {
      await tester.tap(find.byTooltip('More').first);
      await _frames(tester);
      await tester.tap(find.text('Delete').last);
      await _frames(tester);
    }

    // A capture's delete still asks; ticked and confirmed, it's deleted.
    await deleteFirstCard();
    expect(find.byType(AlertDialog), findsOneWidget);
    expect(find.textContaining('pages and text tab'), findsOneWidget);
    await tester.tap(_dontAsk);
    await tester.pump();
    await tester.tap(_confirm);
    await _frames(tester);
    expect(library.events, hasLength(2));

    // The next one goes at once.
    await deleteFirstCard();
    expect(find.byType(AlertDialog), findsNothing);
    expect(library.events, hasLength(1));
    expect(DeleteConfirms.of(library).asks(DeleteKind.sharedCapture), isTrue);

    // Profile: the setting is off; turned on, every kind asks again, and
    // then it can't be turned off from there.
    await tester.tap(find.text('Profile'));
    await _frames(tester);
    final setting = find.byKey(const Key('ask-before-deleting'));
    await tester.ensureVisible(setting);
    expect(find.text('Ask before deleting'), findsOneWidget);
    expect(tester.widget<SwitchListTile>(setting).value, isFalse);
    await tester.tap(setting);
    await _frames(tester);
    expect(tester.widget<SwitchListTile>(setting).value, isTrue);
    expect(tester.widget<SwitchListTile>(setting).onChanged, isNull);
    for (final kind in DeleteKind.values) {
      expect(DeleteConfirms.of(library).asks(kind), isTrue, reason: '$kind');
    }
    await tester.tap(setting);
    await _frames(tester);
    expect(tester.widget<SwitchListTile>(setting).value, isTrue);
    for (final kind in DeleteKind.values) {
      expect(DeleteConfirms.of(library).asks(kind), isTrue, reason: '$kind');
    }

    await tester.tap(find.text('Home'));
    await _frames(tester);
    await deleteFirstCard();
    expect(find.byType(AlertDialog), findsOneWidget);
    await tester.tap(find.text('Cancel'));
    await _frames(tester);
    expect(library.events, hasLength(1));
  });

  testWidgets('removing a shared capture asks on its own: a capture\'s '
      'skipped confirm leaves it asking, and its own skip leaves the '
      'capture\'s', (tester) async {
    final library = Library(PlatformEventStore());
    await tester.runAsync(() async {
      await library.load();
      final made = await library.create([_photo()]);
      await library.applyRemote(
        made.copyWith(sharedBy: 'olga@example.com', readOnly: true),
      );
      await DeleteConfirms.of(library).skip(DeleteKind.capture);
    });
    await tester.pumpWidget(TabCamApp(library: library));
    await _frames(tester);

    Future<void> removeCard() async {
      await tester.tap(find.byTooltip('More').first);
      await _frames(tester);
      await tester.tap(find.text('Remove').last);
      await _frames(tester);
    }

    // It asks, with Remove and the checkbox, though captures don't.
    await removeCard();
    expect(find.byType(AlertDialog), findsOneWidget);
    expect(find.textContaining('olga@example.com keeps it'), findsOneWidget);
    expect(_dontAsk, findsOneWidget);
    await tester.tap(_dontAsk);
    await tester.pump();
    await tester.tap(_confirm);
    await _frames(tester);
    final confirms = DeleteConfirms.of(library);
    expect(confirms.asks(DeleteKind.sharedCapture), isFalse);
    expect(confirms.asks(DeleteKind.file), isTrue);
    expect(confirms.asks(DeleteKind.contribution), isTrue);

    // Without sync the capture stays; its next Remove doesn't ask.
    await removeCard();
    expect(find.byType(AlertDialog), findsNothing);
  });

  testWidgets('a reader\'s own file asks on its own: a file\'s skipped '
      'confirm leaves it asking, and its own skip leaves the file\'s', (
    tester,
  ) async {
    final library = Library(PlatformEventStore());
    late String id;
    await tester.runAsync(() async {
      await library.load();
      final made = await library.create([_photo()]);
      id = made.id;
      await library.applyRemote(
        made.copyWith(sharedBy: 'olga@example.com', readOnly: true),
      );
      await library.applyContribution(
        id,
        Contribution(
          updated: DateTime(2026, 11, 11),
          pages: [
            for (final riff in ['riffa', 'riffb'])
              EventPage.link(
                id: riff,
                url: Uri.parse('https://example.com/$riff'),
                title: 'Riff $riff',
              ),
          ],
        ),
      );
      await DeleteConfirms.of(library).skip(DeleteKind.file);
    });
    await tester.pumpWidget(
      MaterialApp(
        home: EventScreen(library: library, eventId: id),
      ),
    );
    await _frames(tester);
    Finder delete(String page) =>
        find.byKey(ValueKey('delete-contribution-$page'));

    // It asks, with the checkbox, though files don't.
    await tester.tap(delete('riffa'));
    await _frames(tester);
    expect(find.byType(AlertDialog), findsOneWidget);
    expect(_dontAsk, findsOneWidget);
    await tester.tap(_dontAsk);
    await tester.pump();
    await tester.runAsync(() async {
      await tester.tap(_confirm);
      await Future<void>.delayed(const Duration(milliseconds: 100));
    });
    await _frames(tester);
    expect(library.byId(id)!.myContribution!.pages.map((p) => p.id), ['riffb']);
    final confirms = DeleteConfirms.of(library);
    expect(confirms.asks(DeleteKind.contribution), isFalse);
    expect(confirms.asks(DeleteKind.capture), isTrue);
    expect(confirms.asks(DeleteKind.sharedCapture), isTrue);

    // The next one goes at once.
    await tester.runAsync(() async {
      await tester.tap(delete('riffb'));
      await Future<void>.delayed(const Duration(milliseconds: 100));
    });
    await _frames(tester);
    expect(find.byType(AlertDialog), findsNothing);
    expect(library.byId(id)!.myContribution!.pages, isEmpty);
  });

  testWidgets('deleting the account still asks, with no "Don\'t ask again"', (
    tester,
  ) async {
    final library = Library(PlatformEventStore());
    await tester.runAsync(() async {
      for (final kind in DeleteKind.values) {
        await DeleteConfirms.of(library).skip(kind);
      }
    });
    bool? confirmed;
    await tester.pumpWidget(
      MaterialApp(
        home: Builder(
          builder: (context) => TextButton(
            onPressed: () async =>
                confirmed = await confirmAccountDeletion(context),
            child: const Text('go'),
          ),
        ),
      ),
    );
    await tester.tap(find.text('go'));
    await _frames(tester);
    expect(find.text('Delete your account?'), findsOneWidget);
    expect(_dontAsk, findsNothing);
    await tester.tap(find.text('Cancel'));
    await _frames(tester);
    expect(confirmed, isFalse);
  });
}
