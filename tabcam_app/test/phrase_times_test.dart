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

Duration s(num seconds) => Duration(milliseconds: (seconds * 1000).round());

const next = PassDirection.next;
const previous = PassDirection.previous;

void main() {
  group('PhraseTimes', () {
    test('a pass within two seconds of one the same way merges at their '
        'average time, each merged pass counting', () {
      var times = PhraseTimes.none.add(s(10), next, 1);
      times = times.add(s(11), next, 1);
      expect(times.passes, [PhrasePass(s(10.5), next, 1, count: 2)]);
      // A third, 1.5 s off: the average of all three.
      times = times.add(s(12), next, 1);
      expect(times.passes, [PhrasePass(s(11), next, 1, count: 3)]);
      // Exactly two seconds off still merges; the newer's line is kept.
      times = times.add(s(9), next, 2);
      expect(times.passes, [PhrasePass(s(10.5), next, 2, count: 4)]);
    });

    test('passes further apart, or the other way, stay apart, in order', () {
      final times = PhraseTimes.none
          .add(s(20), next, 2)
          .add(s(10), next, 1)
          .add(s(10.5), previous, 0)
          .add(s(12.1), next, 2);
      expect(times.passes, [
        PhrasePass(s(10), next, 1),
        PhrasePass(s(10.5), previous, 0),
        PhrasePass(s(12.1), next, 2),
        PhrasePass(s(20), next, 2),
      ]);
    });

    test('merged, a pass now within reach of another merges with it too', () {
      var times = PhraseTimes.none.add(s(10), next, 1).add(s(13), next, 2);
      expect(times.passes, hasLength(2));
      // 11.9 merges into 13, the nearest: 12.45, still 2.45 s from 10.
      times = times.add(s(11.9), next, 2);
      expect(times.passes, [
        PhrasePass(s(10), next, 1),
        PhrasePass(s(12.45), next, 2, count: 2),
      ]);
      // 11 merges into 10: 10.5, now 1.95 s from 12.45, so those merge.
      times = times.add(s(11), next, 1);
      expect(times.passes, hasLength(1));
      final merged = times.passes.single;
      expect(merged.count, 4);
      expect(merged.at, s((10 + 11 + 11.9 + 13) / 4));
    });

    test('the neckline at a position: the last pass before it, or where '
        'the first turns from', () {
      final times = PhraseTimes.none
          .add(s(10), next, 1)
          .add(s(20), next, 2)
          .add(s(30), previous, 1);
      expect(times.lineAt(s(0)), 0);
      expect(times.lineAt(s(10)), 1);
      expect(times.lineAt(s(25)), 2);
      expect(times.lineAt(s(99)), 1);
      expect(PhraseTimes.none.lineAt(s(5)), isNull);
      expect(PhraseTimes.none.add(s(5), previous, 3).lineAt(s(1)), 4);
    });

    test('JSON keeps them; what it can\'t read is left out', () {
      final times = PhraseTimes.none
          .add(s(1), next, 1)
          .add(s(2), next, 1)
          .add(s(9), previous, 0);
      final json = jsonDecode(jsonEncode(times.toJson()));
      expect(PhraseTimes.fromJson(json).passes, times.passes);
      expect(
        PhraseTimes.fromJson([
          {'ms': 5000, 'dir': 'next', 'line': 2},
          {'ms': -1, 'dir': 'next', 'line': 1},
          {'ms': 1000, 'dir': 'sideways', 'line': 1},
          {'ms': 1000, 'dir': 'next', 'line': 1, 'n': 0},
          'junk',
          {'ms': 2000, 'dir': 'previous', 'line': 0, 'n': 3},
        ]).passes,
        [PhrasePass(s(2), previous, 0, count: 3), PhrasePass(s(5), next, 2)],
      );
      expect(PhraseTimes.fromJson('junk').isEmpty, isTrue);
      expect(
        PhraseTimes.mapFromJson({
          'abc': [
            {'ms': 1, 'dir': 'next', 'line': 1},
          ],
          '../x': [
            {'ms': 1, 'dir': 'next', 'line': 1},
          ],
          'empty': <Object>[],
          'junk': 'junk',
        }, checkId).keys,
        // An empty list: a song cleared on purpose, kept as none.
        ['abc', 'empty'],
      );
      final cleared = {'song': PhraseTimes.none};
      expect(PhraseTimes.mapToJson(cleared), {'song': <Object>[]});
      final back = PhraseTimes.mapFromJson(
        PhraseTimes.mapToJson(cleared),
        checkId,
      );
      expect(back['song']!.isEmpty, isTrue);
    });

    test('songPhrasesOf puts a take\'s passes at the song\'s times, those '
        'made while it played; merged with what\'s there', () {
      // The take's own, on its clock.
      final take = PhraseTimes.none
          .add(s(0.2), next, 1) // before the song started in the take
          .add(s(3), next, 2)
          .add(s(7), next, 3)
          .add(s(13), previous, 2) // played again from 30 s, at 1.5x
          .add(s(25), next, 3); // another song
      const segments = [
        SongSegment(at: 1000, to: 11000, page: 'k1', from: 5000),
        SongSegment(at: 12000, to: 20000, page: 'k1', from: 30000, speed: 1.5),
        SongSegment(at: 21000, to: 30000, page: 'k2', from: 0),
      ];
      final song = songPhrasesOf(take, segments, 'k1');
      expect(song.passes, [
        PhrasePass(s(7), next, 2),
        PhrasePass(s(11), next, 3),
        PhrasePass(s(31.5), previous, 2),
      ]);
      expect(songPhrasesOf(take, segments, 'k2').passes, [
        PhrasePass(s(4), next, 3),
      ]);
      // Into another take's: merged within two seconds, as live.
      final both = songPhrasesOf(
        take,
        segments,
        'k1',
        into: PhraseTimes.none.add(s(8), next, 2),
      );
      expect(both.passes.first, PhrasePass(s(7.5), next, 2, count: 2));
      expect(songPhrasesOf(take, const [], 'k1').isEmpty, isTrue);
    });
  });

  group('AutoPass', () {
    final times = PhraseTimes.none
        .add(s(10), next, 1)
        .add(s(20), next, 2)
        .add(s(25), previous, 1);

    test('the first position, or a jump, shows the passes\' line there; '
        'playing on, each pass turns the tab as it is passed', () {
      final auto = AutoPass();
      expect(auto.tick(times, s(0)), 0);
      expect(auto.tick(times, s(0.1)), isNull);
      expect(auto.tick(times, s(9.9)), 0); // a jump: 9.8 s on
      expect(auto.tick(times, s(10)), 1);
      expect(auto.tick(times, s(10.1)), isNull);
      // Two passed in one tick: the last one's line.
      expect(auto.tick(times, s(19.5)), 1); // a jump
      expect(auto.tick(times, s(21)), 2);
      // Back at the start (a loop): the line before the first pass.
      expect(auto.tick(times, s(0.2)), 0);
      auto.reset();
      expect(auto.tick(times, s(22)), 2);
    });

    test('a pass by hand right after auto-pass made it, the same way, is '
        'that pass: once', () {
      final auto = AutoPass();
      auto.tick(times, s(9.9));
      expect(auto.tick(times, s(10)), 1);
      expect(auto.absorbs(s(11), previous), isFalse);
      expect(auto.absorbs(s(11), next), isTrue);
      expect(auto.absorbs(s(11.5), next), isFalse);
      // More than two seconds after: a pass of its own.
      auto.tick(times, s(19.9));
      expect(auto.tick(times, s(20)), 2);
      expect(auto.absorbs(s(22.1), next), isFalse);
      // A jump forgets what was passed.
      auto.tick(times, s(24.9));
      expect(auto.tick(times, s(25)), 1);
      auto.tick(times, s(2));
      expect(auto.absorbs(s(25.5), previous), isFalse);
    });

    test('a take\'s passes: each turn of the tab in it', () {
      final take = takePhrases([
        (Duration.zero, 0),
        (s(4), 1),
        (s(8), 2),
        (s(9), 1),
        (s(15), 2),
      ]);
      expect(take.passes, [
        PhrasePass(s(4), next, 1),
        PhrasePass(s(8), next, 2),
        PhrasePass(s(9), previous, 1),
        PhrasePass(s(15), next, 2),
      ]);
      expect(takePhrases([(Duration.zero, 3)]).isEmpty, isTrue);
    });

    test('a take\'s passes: none for the turns made with auto-pass off', () {
      final marks = [
        (Duration.zero, 0),
        (s(4), 1),
        (s(8), 2),
        (s(15), 1),
        (s(20), 2),
      ];
      // Off for the turns at 8 s and 15 s: the next one still turns from
      // where the tab was.
      expect(takePhrases(marks, skip: {2, 3}).passes, [
        PhrasePass(s(4), next, 1),
        PhrasePass(s(20), next, 2),
      ]);
      expect(takePhrases(marks, skip: {1, 2, 3, 4}).isEmpty, isTrue);
      // The gap they leave: the tab stays where the pass before left it,
      // and catches up at the next pass.
      final gapped = takePhrases(marks, skip: {2, 3});
      expect(gapped.lineAt(s(10)), 1);
      expect(gapped.lineAt(s(20)), 2);
      // Off for the first turns: before the first pass kept, the tab is
      // where that pass turned from, not where the take started.
      final late = takePhrases(marks, skip: {1, 2, 3});
      expect(late.passes, [PhrasePass(s(20), next, 2)]);
      expect(late.lineAt(Duration.zero), 1);
    });
  });

  group('Library', () {
    Future<(Library, CaptureEvent)> withSong() async {
      final library = Library(PlatformEventStore(), null, (_) async => null);
      await library.load();
      var event = await library.create(const []);
      event = await library.addMedia(event, [
        Media(
          XFile.fromData(Uint8List.fromList([1]), name: 'song.m4a'),
          PageKind.audio,
          'm4a',
        ),
      ]);
      event = await library.addLink(
        event,
        Uri.parse('https://example.com/riff.mp3'),
      );
      return (library, event);
    }

    test('a song\'s phrase times are kept with the capture, in its JSON, '
        'not as a page; cleared, they are gone', () async {
      final (library, event) = await withSong();
      final song = event.pages.first.id;
      final times = PhraseTimes.none.add(s(3), next, 1);
      await library.setPhrases(event.id, song, times);
      expect(library.phrasesOf(event.id, song).passes, times.passes);
      final saved = library.byId(event.id)!;
      expect(saved.pages, hasLength(2));
      expect(saved.updated.isAfter(event.updated), isTrue);
      final json = jsonDecode(jsonEncode(saved.toJson(local: false)));
      expect(CaptureEvent.fromJson(json).phrases[song]!.passes, times.passes);

      // A page that isn't there keeps none.
      await library.setPhrases(event.id, 'gone', times);
      expect(library.byId(event.id)!.phrases.keys, [song]);

      await library.setPhrases(event.id, song, null);
      expect(library.byId(event.id)!.phrases, isEmpty);
      expect(library.byId(event.id)!.toJson().containsKey('phrases'), isFalse);
    });

    test(
      'each file keeps its own, at its own times; a file deleted keeps '
      'its in the trash, purged they go with it, the others\' stay',
      () async {
        final (library, event) = await withSong();
        final (song, link) = (event.pages.first.id, event.pages.last.id);
        final songs = PhraseTimes.none.add(s(3), next, 1).add(s(9), next, 2);
        final links = PhraseTimes.none.add(s(5), previous, 0);
        await library.setPhrases(event.id, song, songs);
        await library.setPhrases(event.id, link, links);
        expect(library.phrasesOf(event.id, song).passes, songs.passes);
        expect(library.phrasesOf(event.id, link).passes, links.passes);
        // One changed, the other is as it was.
        await library.setPhrases(event.id, song, songs.add(s(20), next, 2));
        expect(library.phrasesOf(event.id, song).passes, hasLength(3));
        expect(library.phrasesOf(event.id, link).passes, links.passes);

        final now = library.byId(event.id)!;
        await library.deletePage(
          now,
          now.pages.firstWhere((p) => p.id == song),
        );
        // In the trash, the file keeps its passes (restored, it has them).
        expect(library.phrasesOf(event.id, song).passes, hasLength(3));
        await library.purge();
        final after = library.byId(event.id)!;
        expect(after.phrases.keys, [link]);
        expect(library.phrasesOf(event.id, song).isEmpty, isTrue);
        expect(after.phrases[link]!.passes, links.passes);
      },
    );

    /// [event] with a take that played along [song] from 5 s in, from its
    /// first second to its 21st, its own passes [own] (on its clock).
    Future<(CaptureEvent, EventPage)> withTake(
      Library library,
      CaptureEvent event,
      String song,
      PhraseTimes own,
    ) async {
      final take = EventPage(
        id: 'take1',
        kind: PageKind.video,
        extension: 'mp4',
        take: true,
        takeLog: TakeLog(
          burned: false,
          lagMs: 0,
          song: [SongSegment(at: 1000, to: 21000, page: song, from: 5000)],
        ),
      );
      var now = await library.update(
        library
            .byId(event.id)!
            .copyWith(pages: [...library.byId(event.id)!.pages, take]),
      );
      await library.setPhrases(event.id, take.id, own);
      now = library.byId(event.id)!;
      return (now, take);
    }

    final own = PhraseTimes.none
        .add(s(2), next, 1)
        .add(s(6), next, 2)
        .add(s(25), next, 3); // after the song stopped in the take

    test('a take deleted gives the song it played along its passes, at the '
        'song\'s times, where it has none kept: they outlive the take, and '
        'auto-pass turns the tab along the song', () async {
      final (library, event) = await withSong();
      final song = event.pages.first.id;
      final (now, take) = await withTake(library, event, song, own);
      expect(library.phrasesOf(event.id, song).isEmpty, isTrue);

      await library.deletePage(now, take);
      final kept = [PhrasePass(s(6), next, 1), PhrasePass(s(10), next, 2)];
      expect(library.phrasesOf(event.id, song).passes, kept);
      // In the trash the take keeps its own; purged, they go, the song's
      // stay, saved with the capture.
      expect(library.phrasesOf(event.id, take.id).passes, own.passes);
      await library.purge();
      final after = library.byId(event.id)!;
      expect(after.pages.any((p) => p.id == take.id), isFalse);
      expect(after.phrases.containsKey(take.id), isFalse);
      expect(library.phrasesOf(event.id, song).passes, kept);
      final json = jsonDecode(jsonEncode(after.toJson(local: false)));
      expect(CaptureEvent.fromJson(json).phrases[song]!.passes, kept);

      // Played along again, the tab turns at the song's passes.
      final auto = AutoPass();
      final times = library.phrasesOf(event.id, song);
      expect(auto.tick(times, s(5)), 0);
      expect(auto.tick(times, s(6.1)), 1);
      expect(auto.tick(times, s(6.2)), isNull);
      expect(auto.tick(times, s(10.1)), 2);
    });

    test('a song with passes of its own keeps them as they are; one cleared '
        'on purpose stays cleared when its take goes', () async {
      final (library, event) = await withSong();
      final (song, link) = (event.pages.first.id, event.pages.last.id);
      final mine = PhraseTimes.none.add(s(40), next, 4);
      await library.setPhrases(event.id, song, mine);
      final (now, take) = await withTake(library, event, song, own);
      await library.deletePage(now, take);
      expect(library.phrasesOf(event.id, song).passes, mine.passes);

      // Cleared: an empty list in its JSON, and nothing comes back.
      await library.restorePage(event.id, take);
      await library.clearPhrases(event.id, song);
      expect(library.byId(event.id)!.toJson()['phrases'], {
        song: <Object>[],
        take.id: own.toJson(),
      });
      await library.deletePage(library.byId(event.id)!, take);
      await library.purge();
      expect(library.phrasesOf(event.id, song).isEmpty, isTrue);
      expect(library.byId(event.id)!.phrases[song]!.isEmpty, isTrue);
      expect(library.byId(event.id)!.phrases.containsKey(link), isFalse);
    });

    test('on a capture shared to read, the user\'s own take deleted gives '
        'the owner\'s song their passes, in their contribution', () async {
      final (library, event) = await withSong();
      final song = event.pages.first.id;
      final take = EventPage(
        id: 'take1',
        kind: PageKind.video,
        extension: 'mp4',
        take: true,
        takeLog: TakeLog(
          burned: false,
          lagMs: 0,
          song: [SongSegment(at: 1000, to: 21000, page: song, from: 5000)],
        ),
      );
      await library.update(
        library
            .byId(event.id)!
            .copyWith(
              sharedBy: 'o@x.com',
              readOnly: true,
              contributions: [
                Contribution(
                  updated: DateTime(2026, 11, 22),
                  pages: [take],
                  phrases: {take.id: own},
                ),
              ],
            ),
      );
      await library.deleteContributionPage(library.byId(event.id)!, take);
      final now = library.byId(event.id)!;
      expect(now.phrases.containsKey(song), isFalse);
      expect(now.myContribution!.pages, isEmpty);
      expect(now.myContribution!.phrases.keys, [song]);
      expect(library.phrasesOf(event.id, song).passes, [
        PhrasePass(s(6), next, 1),
        PhrasePass(s(10), next, 2),
      ]);
    });

    test('a clone keeps them, for its own copies of the songs', () async {
      final (library, event) = await withSong();
      final link = event.pages.last.id;
      final times = PhraseTimes.none.add(s(3), next, 1);
      await library.setPhrases(event.id, link, times);
      final copy = await library.clone(library.byId(event.id)!);
      expect(copy.phrases.keys, [copy.pages.last.id]);
      expect(copy.phrases.values.single.passes, times.passes);
    });

    test('on a capture shared to read, they go to the user\'s own '
        'contribution, over the owner\'s', () async {
      final (library, event) = await withSong();
      final song = event.pages.first.id;
      final owners = PhraseTimes.none.add(s(3), next, 1);
      await library.setPhrases(event.id, song, owners);
      await library.update(
        library.byId(event.id)!.copyWith(sharedBy: 'o@x.com', readOnly: true),
      );
      expect(library.phrasesOf(event.id, song).passes, owners.passes);
      final mine = owners.add(s(4), next, 1);
      await library.setPhrases(event.id, song, mine);
      final now = library.byId(event.id)!;
      expect(now.phrases[song]!.passes, owners.passes);
      expect(now.myContribution!.phrases[song]!.passes, mine.passes);
      expect(library.phrasesOf(event.id, song).passes, mine.passes);
      final json = jsonDecode(
        jsonEncode(now.myContribution!.toJson(local: false)),
      );
      expect(Contribution.fromJson(json).phrases[song]!.passes, mine.passes);
    });
  });
}
