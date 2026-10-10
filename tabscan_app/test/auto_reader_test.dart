import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:image/image.dart' as img;
import 'package:tabscan_app/library/event_store_memory.dart';
import 'package:tabscan_app/library/library.dart';
import 'package:tabscan_app/recognition/auto_reader.dart';

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

  test('pages added: read again, replacing what a read left', () async {
    reader();
    await settle();
    final event = await library.create([page()]);
    await settle();
    await library.addPages(library.byId(event.id)!, [page()]);
    await settle();
    expect(reads, [1, 2]);
    expect(library.byId(event.id)!.tabText, riff(2));
  });

  test('a text the user edited is never replaced', () async {
    reader();
    await settle();
    final event = await library.create([page()]);
    await settle();
    await library.update(
      library.byId(event.id)!.copyWith(tabText: 'mine', tabTextAuto: false),
    );
    await library.addPages(library.byId(event.id)!, [page()]);
    await settle();
    expect(reads, [1, 2]);
    expect(library.byId(event.id)!.tabText, 'mine');
  });

  test('a text marked correct is never replaced', () async {
    reader();
    await settle();
    final event = await library.create([page()]);
    await settle();
    await library.update(
      library.byId(event.id)!.copyWith(tabTextCorrect: true),
    );
    await library.addPages(library.byId(event.id)!, [page()]);
    await settle();
    expect(reads, [1, 2]);
    expect(library.byId(event.id)!.tabText, riff(1));
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
