import 'dart:async';
import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:image/image.dart' as img;
import 'package:tabcam_app/library/event_store_memory.dart';
import 'package:tabcam_app/library/library.dart';
import 'package:tabcam_app/recognition/auto_reader.dart';

import 'fakes.dart';

Uint8List page() => img.encodeJpg(img.Image(width: 8, height: 8));

/// A made-up riff, as the reader "reads" it: one line per page.
String riff(int pages) => List.filled(pages, 'e|--0--3--|').join('\n');

void main() {
  late Library library;
  late List<int> reads;
  setUp(() async {
    library = Library(PlatformEventStore(), null, (_) async => null);
    await library.load();
    reads = [];
  });

  AutoReader reader({FakeAuth? auth, String? Function(int pages)? text}) =>
      AutoReader(
        library: library,
        auth: auth,
        supported: true,
        read: (pages) async {
          reads.add(pages.length);
          return (text ?? riff)(pages.length);
        },
      )..start();

  /// Lets the reader's queue run.
  Future<void> settle() async {
    for (var i = 0; i < 20; i++) {
      await Future<void>.delayed(Duration.zero);
    }
  }

  test('a new capture is read by itself into its text tab', () async {
    final r = reader();
    await settle();
    final event = await library.create([page(), page()]);
    await settle();
    final read = library.byId(event.id)!;
    expect(read.tabText, riff(2));
    expect(read.tabTextAuto, isTrue);
    expect(r.stateOf(event.id), isNull);
  });

  test(
    'an event with a text tab isn\'t read again when its pages change',
    () async {
      final r = reader();
      await settle();
      final event = await library.create([page(), page()]);
      await settle();
      expect(reads, [2]);
      var now = library.byId(event.id)!;
      await library.reorderPages(now.id, [now.pages[1].id, now.pages[0].id]);
      await settle();
      now = library.byId(event.id)!;
      await library.rotatePage(now, now.pages[0]);
      await settle();
      now = library.byId(event.id)!;
      await library.addPages(now, [page()]);
      await settle();
      now = library.byId(event.id)!;
      await library.deletePage(now, now.pages[0]);
      await settle();
      expect(reads, [2]);
      expect(library.byId(event.id)!.tabText, riff(2));
      expect(r.stateOf(event.id), isNull);
    },
  );

  test('pages added to an event without a text tab are read', () async {
    var found = false;
    final r = reader(text: (pages) => found ? riff(pages) : null);
    await settle();
    final event = await library.create([page()]);
    await settle();
    expect(r.stateOf(event.id), ReadState.noTab);
    found = true;
    await library.addPages(library.byId(event.id)!, [page()]);
    await settle();
    expect(reads, [1, 2]);
    expect(library.byId(event.id)!.tabText, riff(2));
    expect(r.stateOf(event.id), isNull);
  });

  test('Read again replaces the text a read left', () async {
    var lines = 1;
    final r = reader(text: (_) => riff(lines));
    await settle();
    final event = await library.create([page()]);
    await settle();
    lines = 3;
    r.readSoon(event.id, again: true);
    expect(r.stateOf(event.id), ReadState.reading);
    await settle();
    expect(reads, [1, 1]);
    expect(library.byId(event.id)!.tabText, riff(3));
    expect(r.stateOf(event.id), isNull);
  });

  test('a text the user edited is never replaced', () async {
    final r = reader();
    await settle();
    final event = await library.create([page()]);
    await settle();
    await library.update(
      library.byId(event.id)!.copyWith(tabText: 'mine', tabTextAuto: false),
    );
    r.readSoon(event.id, again: true);
    await settle();
    expect(reads, [1, 1]);
    expect(library.byId(event.id)!.tabText, 'mine');
    expect(r.stateOf(event.id), isNull);
  });

  test('a text marked correct is never replaced', () async {
    final r = reader(text: (_) => riff(reads.length));
    await settle();
    final event = await library.create([page()]);
    await settle();
    await library.update(
      library.byId(event.id)!.copyWith(tabTextCorrect: true),
    );
    r.readSoon(event.id, again: true);
    await settle();
    expect(reads, [1, 1]);
    expect(library.byId(event.id)!.tabText, riff(1));
  });

  test('a read that never ends fails after the timeout', () async {
    final hang = Completer<String?>();
    final r = AutoReader(
      library: library,
      supported: true,
      read: (_) => hang.future,
      cloudTimeout: const Duration(milliseconds: 50),
    )..start();
    await settle();
    final event = await library.create([page()]);
    await settle();
    expect(r.stateOf(event.id), ReadState.reading);
    await Future<void>.delayed(const Duration(milliseconds: 100));
    expect(r.stateOf(event.id), ReadState.failed);
    r.dispose();
  });

  test('a deleted event has nothing more to say', () async {
    final r = reader(text: (_) => null);
    await settle();
    final event = await library.create([page()]);
    await settle();
    expect(r.stateOf(event.id), ReadState.noTab);
    await library.delete(library.byId(event.id)!);
    await settle();
    expect(r.stateOf(event.id), isNull);
  });

  test('changes that aren\'t to the image pages don\'t read again', () async {
    reader();
    await settle();
    final event = await library.create([page()]);
    await settle();
    await library.update(library.byId(event.id)!.copyWith(title: 'Riff'));
    await settle();
    expect(reads, [1]);
  });

  test('events there were before it started aren\'t read', () async {
    await library.create([page()]);
    reader();
    await settle();
    expect(reads, isEmpty);
  });

  test('no tab found says so', () async {
    final r = reader(text: (_) => null);
    await settle();
    final event = await library.create([page()]);
    await settle();
    expect(r.stateOf(event.id), ReadState.noTab);
    expect(library.byId(event.id)!.tabText, isNull);
  });

  test('signed out, it waits, and reads at sign-in', () async {
    final auth = FakeAuth();
    final r = reader(auth: auth);
    await settle();
    final event = await library.create([page()]);
    await settle();
    expect(r.stateOf(event.id), ReadState.needsSignIn);
    expect(reads, isEmpty);
    auth.signInAs('ana');
    await settle();
    expect(library.byId(event.id)!.tabText, riff(1));
  });

  test('where the device can\'t read (the web), it says so', () async {
    final r = AutoReader(library: library, supported: false)..start();
    await settle();
    final event = await library.create([page()]);
    await settle();
    expect(r.stateOf(event.id), ReadState.unsupported);
  });
}
