import 'dart:convert';
import 'dart:typed_data';

import 'package:cross_file/cross_file.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:tabcam_app/capture/auto_pass.dart';
import 'package:tabcam_app/capture/media.dart';
import 'package:tabcam_app/capture/take_log.dart';
import 'package:tabcam_app/library/capture_event.dart';
import 'package:tabcam_app/library/event_store_memory.dart';
import 'package:tabcam_app/library/library.dart';

/// A capture shared with someone: every file comes with its timings (a
/// take's log, a song's phrase passes, a take's song found in its sound),
/// on the shared capture and in the user's own copy of it, where Cam
/// records, and that copy catches up with what the owner adds later.
/// Made-up riffs only.

Duration s(num seconds) => Duration(milliseconds: (seconds * 1000).round());

const next = PassDirection.next;

Future<Library> library() async {
  final library = Library(PlatformEventStore(), null, (_) async => null);
  await library.load();
  return library;
}

Media file(String name, PageKind kind, String extension) => Media(
  XFile.fromData(Uint8List.fromList([1, 2, 3]), name: name),
  kind,
  extension,
);

/// The owner's capture as the user's library takes it from the cloud: its
/// event.json as uploaded, read back, shared with them to read.
Future<CaptureEvent> share(Library owner, String id, Library reader) async {
  final json = jsonDecode(jsonEncode(owner.byId(id)!.toJson(local: false)));
  final theirs = CaptureEvent.fromJson((json as Map).cast<String, Object?>())
      .withOwnFiles();
  await reader.applyRemote(
    theirs.copyWith(
      owner: 'us-east-1:owner',
      sharedBy: 'owner@example.com',
      readOnly: true,
    ),
  );
  return reader.byId(id)!;
}

/// A take of [song], with the tab turned at 0 s and 10 s.
TakeLog takeOf(String song, {TakeSync? sync}) => TakeLog(
  burned: false,
  tab: TakeTab.of(
    ['e|--0--2--|', 'e|--3--5--|'],
    [(Duration.zero, 0), (s(10), 1)],
  ),
  song: [SongSegment(at: 0, to: 30000, page: song, from: 0)],
  sync: sync,
);

Future<CaptureEvent> addTake(Library owner, CaptureEvent event, TakeLog log) =>
    owner.addMedia(
      event,
      [file('take.mp4', PageKind.video, 'mp4')],
      take: true,
      takeLog: log,
    );

void main() {
  test('shared, a capture brings its takes\' logs and its songs\' phrase '
      'passes; the user\'s copy (where Cam records) has them, on its own '
      'pages, and auto-pass turns the tab by them', () async {
    final owner = await library();
    var event = await owner.create(const []);
    event = await owner.addMedia(event, [
      file('riff.m4a', PageKind.audio, 'm4a'),
    ]);
    final song = event.pages.single.id;
    event = await addTake(owner, event, takeOf(song));
    final take = event.pages.last.id;
    final passes = PhraseTimes.none.add(s(10), next, 1).add(s(20), next, 2);
    final takePasses = PhraseTimes.none.add(s(10), next, 1);
    await owner.setPhrases(event.id, song, passes);
    await owner.setPhrases(event.id, take, takePasses);

    final reader = await library();
    final shared = await share(owner, event.id, reader);
    // The shared capture itself: every file, with its timings.
    expect(shared.pages.map((p) => p.id), [song, take]);
    expect(shared.pages.last.takeLog, owner.byId(event.id)!.pages.last.takeLog);
    expect(reader.phrasesOf(event.id, song).passes, passes.passes);
    expect(reader.phrasesOf(event.id, take).passes, takePasses.passes);

    // The user's copy, where Cam opens: its own pages, each with its
    // timings, the take's log naming the copy's song.
    final copy = await reader.copyToAdd(shared);
    expect(copy.id, isNot(event.id));
    final (mySong, myTake) = (copy.clonedPages[song]!, copy.clonedPages[take]!);
    expect(copy.pages.map((p) => p.id), [mySong, myTake]);
    expect(reader.phrasesOf(copy.id, mySong).passes, passes.passes);
    expect(reader.phrasesOf(copy.id, myTake).passes, takePasses.passes);
    final log = copy.pages.last.takeLog!;
    expect(log.song.single.page, mySong);
    expect(log.tab!.marks, takeOf(song).tab!.marks);
    expect(copy.pages.first.source, FileOrigin(event.id, song));

    // Auto-pass, playing the copy's song: the tab turns where the owner's
    // passes are.
    final auto = AutoPass();
    final times = reader.phrasesOf(copy.id, mySong);
    expect(auto.tick(times, s(0)), 0);
    expect(auto.tick(times, s(0.1)), isNull);
    expect(auto.tick(times, s(10)), 1);
    expect(auto.tick(times, s(20)), 2);

    // Kept with the copy (event.json), as it syncs.
    final saved = CaptureEvent.fromJson(
      (jsonDecode(
        jsonEncode(reader.byId(copy.id)!.toJson(local: false)),
      ) as Map).cast<String, Object?>(),
    );
    expect(saved.clonedPages, {song: mySong, take: myTake});
    expect(saved.phrases[mySong]!.passes, passes.passes);
  });

  test('the user\'s copy, made before, catches up with what the owner '
      'added since: new files with their logs and passes, passes for a song '
      'it had none for, a take\'s sync; what the user deleted or recorded '
      'there stays theirs', () async {
    final owner = await library();
    var event = await owner.create(const []);
    event = await owner.addMedia(event, [
      file('page.jpg', PageKind.image, 'jpg'),
      file('riff.m4a', PageKind.audio, 'm4a'),
      file('bass.m4a', PageKind.audio, 'm4a'),
    ]);
    final [page, song, bass] = [for (final p in event.pages) p.id];
    final reader = await library();
    var copy = await reader.copyToAdd(await share(owner, event.id, reader));
    final mySong = copy.clonedPages[song]!;
    final myBass = copy.clonedPages[bass]!;
    expect(reader.phrasesOf(copy.id, mySong).isEmpty, isTrue);
    // The user deletes the picture from their copy, and records their own
    // passes along the bass.
    await reader.deletePage(
      copy,
      copy.pages.firstWhere((p) => p.id == copy.clonedPages[page]),
    );
    final mine = PhraseTimes.none.add(s(4), next, 1);
    await reader.setPhrases(copy.id, myBass, mine);

    // The owner records passes along both songs, and adds a take with its
    // own passes, then finds the song in it.
    final passes = PhraseTimes.none.add(s(10), next, 1);
    await owner.setPhrases(event.id, song, passes);
    await owner.setPhrases(event.id, bass, passes.add(s(30), next, 2));
    event = await addTake(owner, owner.byId(event.id)!, takeOf(song));
    final take = event.pages.last.id;
    await owner.setPhrases(event.id, take, passes);
    var shared = await share(owner, event.id, reader);
    expect(reader.copyOf(event.id)!.id, copy.id);

    copy = await reader.copyToAdd(shared);
    final myTake = copy.clonedPages[take]!;
    // The picture stays deleted; the take comes at the end.
    expect(copy.pages.map((p) => p.id), [mySong, myBass, myTake]);
    expect(copy.deletedPages, hasLength(1));
    expect(copy.pages.last.source, FileOrigin(event.id, take));
    expect(copy.pages.last.takeLog!.song.single.page, mySong);
    expect(copy.pages.last.takeLog!.sync, isNull);
    // The owner's passes where the copy had none; the user's own kept.
    expect(reader.phrasesOf(copy.id, mySong).passes, passes.passes);
    expect(reader.phrasesOf(copy.id, myTake).passes, passes.passes);
    expect(reader.phrasesOf(copy.id, myBass).passes, mine.passes);

    // Nothing new: the copy stays as it is (no change to sync).
    final updated = reader.byId(copy.id)!.updated;
    expect((await reader.copyToAdd(shared)).updated, updated);

    // The owner's device finds the song in the take's sound: it comes to
    // the copy's log, naming the copy's song.
    await owner.setTakeSync(
      event.id,
      take,
      TakeSync(page: song, from: SyncFrom.sound, ms: 40),
    );
    shared = await share(owner, event.id, reader);
    copy = await reader.copyToAdd(shared);
    final sync = copy.pages.last.takeLog!.sync!;
    expect((sync.page, sync.ms), (mySong, 40));
  });

  test('a song whose passes the user cleared in their copy gets none of '
      'the owner\'s back', () async {
    final owner = await library();
    var event = await owner.create(const []);
    event = await owner.addMedia(event, [
      file('riff.m4a', PageKind.audio, 'm4a'),
    ]);
    final song = event.pages.single.id;
    final reader = await library();
    var copy = await reader.copyToAdd(await share(owner, event.id, reader));
    final mySong = copy.clonedPages[song]!;
    await reader.clearPhrases(copy.id, mySong);

    // The owner records passes along it later.
    await owner.setPhrases(
      event.id,
      song,
      PhraseTimes.none.add(s(10), next, 1),
    );
    copy = await reader.copyToAdd(await share(owner, event.id, reader));
    expect(reader.phrasesOf(copy.id, mySong).isEmpty, isTrue);
  });

  test(
    'a copy made before it kept which pages it took catches up without '
    'taking again the pages it had, those whose file became its own too',
    () async {
      final owner = await library();
      var event = await owner.create(const []);
      event = await owner.addMedia(event, [
        file('riff.m4a', PageKind.audio, 'm4a'),
        file('page.jpg', PageKind.image, 'jpg'),
      ]);
      final reader = await library();
      final shared = await share(owner, event.id, reader);
      var copy = await reader.clone(shared);
      // As copies were made before: no record of the pages taken, and one
      // page's file its own already.
      copy = await reader.update(
        copy.copyWith(
          clonedPages: const {},
          pages: [
            copy.pages.first,
            copy.pages.last.copyWith(source: () => null),
          ],
        ),
      );
      // Later than the copy: a new song of the owner's.
      await Future<void>.delayed(const Duration(milliseconds: 5));
      event = await owner.addMedia(owner.byId(event.id)!, [
        file('bass.m4a', PageKind.audio, 'm4a'),
      ]);
      final bass = event.pages.last.id;
      final song = event.pages.first.id;
      await owner.setPhrases(
        event.id,
        song,
        PhraseTimes.none.add(s(10), next, 1),
      );

      copy = await reader.copyToAdd(await share(owner, event.id, reader));
      expect(copy.pages, hasLength(3));
      expect(copy.pages.last.source, FileOrigin(event.id, bass));
      // The song still showing the original's file is known: its passes come.
      final mySong = copy.clonedPages[song]!;
      expect(mySong, copy.pages.first.id);
      expect(reader.phrasesOf(copy.id, mySong).passes, hasLength(1));
      // The page whose file became the copy's own is taken, its copy unknown.
      expect(copy.clonedPages[event.pages[1].id], '');
      // Again: nothing more.
      expect(
        (await reader.copyToAdd(reader.byId(event.id)!)).pages,
        hasLength(3),
      );
    },
  );

  test('a clone copies all of a page, a newer app\'s keys too, its file '
      'the original\'s', () async {
    final owner = await library();
    var event = await owner.create(const []);
    event = await owner.addMedia(event, [
      file('riff.m4a', PageKind.audio, 'm4a'),
    ]);
    final page = event.pages.single;
    final withExtra = EventPage.fromJson({
      ...page.toJson(),
      'songTimings': {'beats': 4},
    });
    event = await owner.update(event.copyWith(pages: [withExtra]));
    final copy = await owner.clone(event);
    expect(copy.pages.single.extra, {
      'songTimings': {'beats': 4},
    });
    expect(copy.pages.single.source, FileOrigin(event.id, page.id));
    expect(copy.pages.single.title, page.title);
  });
}
