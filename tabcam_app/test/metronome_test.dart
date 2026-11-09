import 'dart:async';
import 'dart:convert';
import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:tabcam_app/l10n/app_localizations.dart';
import 'package:tabcam_app/library/event_store_memory.dart';
import 'package:tabcam_app/library/library.dart';
import 'package:tabcam_app/metronome/click_track.dart';
import 'package:tabcam_app/metronome/metronome.dart';
import 'package:tabcam_app/metronome/metronome_sound.dart';
import 'package:tabcam_app/screens/sidebar_widths.dart';

/// Records what it was asked to play.
class FakeSound implements MetronomeSound {
  final List<String> calls = [];
  Object? error;
  Completer<void>? gate;

  @override
  Future<void> start(int bpm, TimeSignature signature) async {
    calls.add('start $bpm ${signature.label}');
    if (gate case final g?) await g.future;
    if (error case final e?) throw e;
  }

  @override
  Future<void> stop() async => calls.add('stop');
}

void main() {
  group('time signatures', () {
    test('accent the bar, and in eighth-note meters each group', () {
      String accents(TimeSignature s) => s.accents
          .map(
            (a) => switch (a) {
              Accent.bar => 'B',
              Accent.group => 'g',
              Accent.beat => 'b',
            },
          )
          .join();
      expect(accents(TimeSignature.fourFour), 'Bbbb');
      expect(accents(TimeSignature.threeFour), 'Bbb');
      expect(accents(TimeSignature.sixEight), 'Bbbgbb');
      expect(accents(TimeSignature.sevenEight), 'Bbgbgbb');
      expect(accents(TimeSignature.twelveEight), 'Bbbgbbgbbgbb');
    });

    test('the common ones, named as written', () {
      expect(TimeSignature.common.map((s) => s.label), [
        '2/4',
        '3/4',
        '4/4',
        '5/4',
        '6/8',
        '7/8',
        '9/8',
        '12/8',
      ]);
      expect(TimeSignature.byLabel('6/8'), TimeSignature.sixEight);
      expect(TimeSignature.byLabel('11/8'), isNull);
    });
  });

  group('the click track', () {
    int sampleRate(Uint8List wav) =>
        ByteData.sublistView(wav).getUint32(24, Endian.little);
    Int16List samples(Uint8List wav) =>
        Int16List.sublistView(Uint8List.fromList(wav.sublist(44)));
    int peak(Int16List pcm, int from, int length) {
      var top = 0;
      for (var i = from; i < from + length && i < pcm.length; i++) {
        top = pcm[i].abs() > top ? pcm[i].abs() : top;
      }
      return top;
    }

    test('is a WAV of whole bars, at least 20 seconds', () {
      final wav = clickTrackWav(bpm: 80, signature: TimeSignature.fourFour);
      expect(ascii.decode(wav.sublist(0, 4)), 'RIFF');
      expect(ascii.decode(wav.sublist(8, 16)), 'WAVEfmt ');
      final rate = sampleRate(wav);
      final pcm = samples(wav);
      final bar = rate * 60 / 80 * 4; // 3 s
      final bars = pcm.length / bar;
      expect(bars, closeTo(bars.roundToDouble(), 0.001));
      expect(pcm.length / rate, greaterThanOrEqualTo(20));
      expect(bars.round(), 7);
    });

    test('clicks on every beat, the first of the bar loudest', () {
      final wav = clickTrackWav(bpm: 120, signature: TimeSignature.sixEight);
      final rate = sampleRate(wav);
      final pcm = samples(wav);
      final beat = rate ~/ 2;
      final click = rate ~/ 25;
      final peaks = [for (var b = 0; b < 6; b++) peak(pcm, b * beat, click)];
      // Bar, beat, beat, group, beat, beat.
      expect(peaks[0], greaterThan(peaks[3]));
      expect(peaks[3], greaterThan(peaks[1]));
      expect(peaks[1], closeTo(peaks[2], 2));
      expect(peaks.every((p) => p > 1000), isTrue);
      // Silence between clicks.
      expect(peak(pcm, beat ~/ 2, beat ~/ 4), 0);
    });
  });

  group('the metronome', () {
    late FakeSound sound;
    final state = MetronomeState.instance;

    setUp(() {
      sound = FakeSound();
      state.reset(sound);
      SidebarWidths.instance.clear();
    });

    test('starts at 80 BPM in 4/4, closed and silent', () {
      expect(state.bpm, 80);
      expect(state.signature, TimeSignature.fourFour);
      expect(state.open, isFalse);
      expect(state.playing, isFalse);
    });

    test('keeps its tempo between 30 and 250', () {
      state.setBpm(10);
      expect(state.bpm, 30);
      state.setBpm(400);
      expect(state.bpm, 250);
    });

    test('playing, a new tempo or time signature starts it over with it; '
        'closing it stops it', () async {
      state.toggle();
      await state.play();
      state.setBpm(96);
      await pumpEventQueue();
      state.setSignature(TimeSignature.threeFour);
      await pumpEventQueue();
      state.close();
      await pumpEventQueue();
      expect(sound.calls, [
        'start 80 4/4',
        'start 96 4/4',
        'start 96 3/4',
        'stop',
      ]);
      expect(state.playing, isFalse);
    });

    test('a slider being dragged changes the tempo when let go', () async {
      await state.play();
      state.setBpm(100, apply: false);
      state.setBpm(110, apply: false);
      expect(sound.calls, ['start 80 4/4']);
      state.applyBpm();
      await pumpEventQueue();
      expect(sound.calls, ['start 80 4/4', 'start 110 4/4']);
    });

    test('stopped while starting, it stays silent', () async {
      sound.gate = Completer<void>();
      final playing = state.play();
      await state.stop();
      sound.gate!.complete();
      await playing;
      await pumpEventQueue();
      expect(state.playing, isFalse);
      expect(sound.calls.last, 'stop');
      expect(state.beat.value, isNull);
    });

    test("says so when it can't play", () async {
      sound.error = StateError('no audio');
      await state.play();
      expect(state.playing, isFalse);
      expect(state.error, contains('no audio'));
    });

    test('keeps the tempo and time signature on the device', () async {
      final library = Library(PlatformEventStore(), null, (_) async => null);
      await library.load();
      await state.load(library);
      state.setBpm(132);
      state.setSignature(TimeSignature.sixEight);
      await pumpEventQueue();
      expect(jsonDecode((await library.readMeta(MetronomeState.metaName))!), {
        'bpm': 132,
        'signature': '6/8',
      });
      state.reset(sound);
      await state.load(library);
      expect(state.bpm, 132);
      expect(state.signature, TimeSignature.sixEight);
    });
  });

  group('the sidebar', () {
    late FakeSound sound;
    final state = MetronomeState.instance;

    setUp(() {
      sound = FakeSound();
      state.reset(sound);
      SidebarWidths.instance.clear();
    });

    Future<void> show(WidgetTester tester, {bool host = true}) async {
      tester.view.physicalSize = const Size(1200, 800);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.reset);
      await tester.pumpWidget(
        MaterialApp(
          localizationsDelegates: AppLocalizations.localizationsDelegates,
          supportedLocales: AppLocalizations.supportedLocales,
          home: Scaffold(
            appBar: AppBar(actions: const [MetronomeButton()]),
            body: host
                ? const MetronomeBeside(
                    child: SizedBox.expand(key: Key('content')),
                  )
                : const SizedBox.expand(key: Key('content')),
          ),
        ),
      );
    }

    final sidebar = find.byKey(const Key('metronome-sidebar'));
    String bpm(WidgetTester tester) => tester
        .widget<Text>(find.byKey(const Key('metronome-bpm')))
        .textSpan!
        .toPlainText();
    final play = find.byKey(const Key('metronome-play'));
    final lights = find.byKey(const Key('metronome-lights'));

    testWidgets('the button opens it on the right of the screen, at 80 BPM '
        'in 4/4, and hides it', (tester) async {
      await show(tester);
      expect(sidebar, findsNothing);
      await tester.tap(find.byKey(const Key('metronome')));
      await tester.pumpAndSettle();
      expect(sidebar, findsOneWidget);
      expect(tester.getTopRight(sidebar).dx, 1200);
      expect(tester.getSize(sidebar).width, 340);
      expect(bpm(tester), '80 BPM');
      final fourFour = tester.widget<ChoiceChip>(
        find.byKey(const Key('metronome-signature-4/4')),
      );
      expect(fourFour.selected, isTrue);
      expect(
        find.descendant(of: lights, matching: find.byType(AnimatedContainer)),
        findsNWidgets(4),
      );
      await tester.tap(find.byKey(const Key('metronome')));
      await tester.pumpAndSettle();
      expect(sidebar, findsNothing);
    });

    testWidgets('− and + change the tempo; a time signature changes the '
        'beats', (tester) async {
      await show(tester);
      await tester.tap(find.byKey(const Key('metronome')));
      await tester.pumpAndSettle();
      await tester.tap(find.byKey(const Key('metronome-faster')));
      await tester.tap(find.byKey(const Key('metronome-faster')));
      await tester.tap(find.byKey(const Key('metronome-slower')));
      await tester.pump();
      expect(bpm(tester), '81 BPM');
      await tester.tap(find.byKey(const Key('metronome-signature-6/8')));
      await tester.pump();
      expect(state.signature, TimeSignature.sixEight);
      expect(
        find.descendant(of: lights, matching: find.byType(AnimatedContainer)),
        findsNWidgets(6),
      );
      expect(find.textContaining('eighth note'), findsOneWidget);
    });

    testWidgets('Start plays it and lights the beats as they click; Stop '
        'stops it', (tester) async {
      await show(tester);
      await tester.tap(find.byKey(const Key('metronome')));
      await tester.pumpAndSettle();
      await tester.tap(play);
      await tester.pump();
      expect(sound.calls, ['start 80 4/4']);
      expect(state.playing, isTrue);
      expect(find.text('Stop'), findsOneWidget);
      expect(state.beat.value, 0);
      await tester.pump(const Duration(milliseconds: 750)); // a beat at 80
      expect(state.beat.value, 1);
      await tester.tap(play);
      await tester.pump();
      expect(sound.calls.last, 'stop');
      expect(state.beat.value, isNull);
      expect(find.text('Start'), findsOneWidget);
    });

    testWidgets('its close button stops it', (tester) async {
      await show(tester);
      await tester.tap(find.byKey(const Key('metronome')));
      await tester.pumpAndSettle();
      await tester.tap(play);
      await tester.pump();
      await tester.tap(find.byKey(const Key('metronome-close')));
      await tester.pumpAndSettle();
      expect(sidebar, findsNothing);
      expect(state.playing, isFalse);
      expect(sound.calls.last, 'stop');
    });

    testWidgets('leaving the screens that have it stops it', (tester) async {
      await show(tester);
      await tester.tap(find.byKey(const Key('metronome')));
      await tester.pumpAndSettle();
      await tester.tap(play);
      await tester.pump();
      await show(tester, host: false);
      await tester.pump();
      expect(state.playing, isFalse);
      expect(sound.calls.last, 'stop');
    });
  });
}
