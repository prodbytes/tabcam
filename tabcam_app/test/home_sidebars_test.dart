import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:tabcam_app/dictionary/dictionary_sidebar.dart';
import 'package:tabcam_app/library/event_store_memory.dart';
import 'package:tabcam_app/library/library.dart';
import 'package:tabcam_app/main.dart';
import 'package:tabcam_app/metronome/click_track.dart';
import 'package:tabcam_app/metronome/metronome.dart';
import 'package:tabcam_app/metronome/metronome_sound.dart';
import 'package:tabcam_app/screens/event_screen.dart';
import 'package:tabcam_app/screens/rename_dialog.dart';
import 'package:tabcam_app/screens/sidebar_widths.dart';

/// Records what it was asked to play.
class _Sound implements MetronomeSound {
  final List<String> calls = [];

  @override
  Future<void> start(int bpm, TimeSignature signature) async =>
      calls.add('start $bpm ${signature.label}');

  @override
  Future<void> stop() async => calls.add('stop');
}

void main() {
  late _Sound sound;
  final metronome = MetronomeState.instance;
  final dictionary = DictionaryState.instance;

  setUp(() {
    sound = _Sound();
    metronome.reset(sound);
    dictionary.clear();
    SidebarWidths.instance.clear();
  });

  tearDown(() {
    metronome.reset(_Sound());
    dictionary.clear();
    SidebarWidths.instance.clear();
  });

  /// Home, on a screen [size], with captures of made-up riffs named
  /// [titles], and [readOnly] ones shared with the user to read only.
  Future<void> home(
    WidgetTester tester, {
    Size size = const Size(1200, 800),
    List<String> titles = const ['Riff in E', 'Slow blues lick'],
    List<String> readOnly = const [],
  }) async {
    tester.view.physicalSize = size;
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);
    final library = Library(PlatformEventStore());
    await library.load();
    for (final title in titles) {
      final event = await library.create(const []);
      await library.update(event.copyWith(title: title));
    }
    for (final title in readOnly) {
      final event = await library.create(const []);
      await library.update(
        event.copyWith(
          title: title,
          sharedBy: 'friend@example.com',
          readOnly: true,
        ),
      );
    }
    await tester.pumpWidget(TabCamApp(library: library));
    await tester.pumpAndSettle();
  }

  final dictionaryButton = find.byKey(const Key('dictionary'));
  final metronomeButton = find.byKey(const Key('metronome'));
  final dictionarySidebar = find.byKey(const Key('dictionary-sidebar'));
  final metronomeSidebar = find.byKey(const Key('metronome-sidebar'));
  final search = find.byKey(const Key('home-search'));
  final bar = find.byType(NavigationBar);
  Finder tab(String label) =>
      find.descendant(of: bar, matching: find.text(label));

  testWidgets('Home has Dictionary and Metronome; each opens its sidebar '
      'beside the captures, above the navigation bar, and hides it', (
    tester,
  ) async {
    await home(tester);
    final appBar = find.byType(AppBar);
    expect(find.descendant(of: appBar, matching: dictionaryButton), findsOne);
    expect(find.descendant(of: appBar, matching: metronomeButton), findsOne);
    // Dictionary first, then Metronome, as on the other screens.
    expect(
      tester.getCenter(dictionaryButton).dx,
      lessThan(tester.getCenter(metronomeButton).dx),
    );
    expect(dictionarySidebar, findsNothing);
    expect(metronomeSidebar, findsNothing);

    await tester.tap(dictionaryButton);
    await tester.pumpAndSettle();
    expect(dictionarySidebar, findsOneWidget);
    expect(tester.getTopRight(dictionarySidebar).dx, 1200);
    // Over the navigation bar, not on it.
    expect(
      tester.getBottomLeft(dictionarySidebar).dy,
      lessThanOrEqualTo(tester.getTopLeft(bar).dy),
    );
    // The captures stay, at its left, and still work.
    expect(
      tester.getTopRight(search).dx,
      lessThan(tester.getTopLeft(dictionarySidebar).dx),
    );
    await tester.enterText(search, 'blues');
    await tester.pumpAndSettle();
    expect(find.text('Slow blues lick'), findsOneWidget);
    expect(find.text('Riff in E'), findsNothing);

    await tester.tap(metronomeButton);
    await tester.pumpAndSettle();
    expect(metronomeSidebar, findsOneWidget);
    // The metronome's is the rightmost, the dictionary's left of it.
    expect(tester.getTopRight(metronomeSidebar).dx, 1200);
    expect(
      tester.getTopRight(dictionarySidebar).dx,
      lessThan(tester.getTopLeft(metronomeSidebar).dx),
    );
    expect(
      tester.getBottomLeft(metronomeSidebar).dy,
      lessThanOrEqualTo(tester.getTopLeft(bar).dy),
    );
    // The navigation bar still works.
    await tester.tap(tab('Capture'));
    await tester.pumpAndSettle();
    expect(find.text('Scan'), findsOneWidget);
    await tester.tap(tab('Home'));
    await tester.pumpAndSettle();

    await tester.tap(dictionaryButton);
    await tester.tap(metronomeButton);
    await tester.pumpAndSettle();
    expect(dictionarySidebar, findsNothing);
    expect(metronomeSidebar, findsNothing);
    expect(dictionary.open, isFalse);
    expect(metronome.open, isFalse);
  });

  testWidgets('on Capture and Profile the buttons and sidebars are hidden '
      'and the metronome stops; back on Home they show again', (tester) async {
    await home(tester);
    await tester.tap(dictionaryButton);
    await tester.tap(metronomeButton);
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const Key('metronome-play')));
    await tester.pump();
    expect(metronome.playing, isTrue);

    for (final other in ['Profile', 'Capture']) {
      await tester.tap(tab(other));
      await tester.pumpAndSettle();
      expect(dictionaryButton, findsNothing);
      expect(metronomeButton, findsNothing);
      expect(dictionarySidebar, findsNothing);
      expect(metronomeSidebar, findsNothing);
      expect(metronome.playing, isFalse);
      expect(sound.calls.last, 'stop');
    }
    // Profile's content spans the screen again.
    await tester.tap(tab('Profile'));
    await tester.pumpAndSettle();
    expect(find.text('About'), findsOneWidget);
    // Still open, app-wide: back on Home they show, stopped.
    expect(dictionary.open, isTrue);
    expect(metronome.open, isTrue);
    await tester.tap(tab('Home'));
    await tester.pumpAndSettle();
    expect(dictionarySidebar, findsOneWidget);
    expect(metronomeSidebar, findsOneWidget);
    expect(metronome.playing, isFalse);
    // And it plays again there.
    await tester.tap(find.byKey(const Key('metronome-play')));
    await tester.pump();
    expect(metronome.playing, isTrue);
    expect(sound.calls.last, 'start 80 4/4');
    await tester.tap(find.byKey(const Key('metronome-close')));
    await tester.pumpAndSettle();
    expect(metronome.playing, isFalse);
  });

  testWidgets('it plays on from Home into a capture and back', (tester) async {
    await home(tester, titles: const ['Riff in E']);
    await tester.tap(metronomeButton);
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const Key('metronome-play')));
    await tester.pump();
    await tester.tap(find.text('Riff in E'));
    for (var i = 0; i < 20; i++) {
      await tester.pump(const Duration(milliseconds: 50));
    }
    expect(find.byType(EventScreen), findsOneWidget);
    expect(metronome.playing, isTrue);
    expect(metronomeSidebar, findsOneWidget);
    await tester.pageBack();
    for (var i = 0; i < 20; i++) {
      await tester.pump(const Duration(milliseconds: 50));
    }
    expect(find.byType(EventScreen), findsNothing);
    expect(metronome.playing, isTrue);
    expect(sound.calls, ['start 80 4/4']);
    await tester.tap(metronomeButton);
    await tester.pump();
    expect(metronome.playing, isFalse);
  });

  Future<void> frames(WidgetTester tester) async {
    for (var i = 0; i < 20; i++) {
      await tester.pump(const Duration(milliseconds: 50));
    }
  }

  testWidgets('a dialog over Home lets it play; a screen without the '
      'metronome opened over Home stops it', (tester) async {
    await home(tester);
    await tester.tap(metronomeButton);
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const Key('metronome-play')));
    await tester.pump();
    expect(metronome.playing, isTrue);

    final context = tester.element(search);
    unawaited(
      showDialog<void>(
        context: context,
        builder: (_) => const AlertDialog(content: Text('A dialog')),
      ),
    );
    await frames(tester);
    expect(find.text('A dialog'), findsOneWidget);
    expect(metronome.playing, isTrue);
    Navigator.of(context).pop();
    await frames(tester);

    // As a capture link that's still loading, or unavailable, is.
    unawaited(
      Navigator.of(context).push(
        MaterialPageRoute<void>(
          builder: (_) => const Scaffold(body: Text('Elsewhere')),
        ),
      ),
    );
    await frames(tester);
    expect(find.text('Elsewhere'), findsOneWidget);
    expect(metronome.playing, isFalse);
    expect(sound.calls, ['start 80 4/4', 'stop']);
    // Back on Home, the sidebar shows again, stopped.
    Navigator.of(context).pop();
    await frames(tester);
    expect(metronomeSidebar, findsOneWidget);
    expect(metronome.playing, isFalse);
  });

  testWidgets('a card squeezed by a sidebar on a phone has no ⋮; a '
      'long-press opens its menu, read only too', (tester) async {
    await home(
      tester,
      size: const Size(360, 640),
      titles: const ['Riff in E'],
      readOnly: const ['Waltz in D'],
    );
    final more = find.byTooltip('More');
    expect(more, findsNWidgets(2));
    await tester.tap(metronomeButton);
    await tester.pumpAndSettle();
    expect(tester.takeException(), isNull);
    expect(more, findsNothing);

    await tester.longPress(find.text('Riff in E'));
    await tester.pumpAndSettle();
    for (final item in ['Rename', 'Share', 'Clone', 'Delete']) {
      expect(find.text(item), findsOneWidget);
    }
    await tester.tap(find.text('Rename'));
    await tester.pumpAndSettle();
    expect(find.byType(RenameDialog), findsOneWidget);
    await tester.tap(find.text('Cancel'));
    await tester.pumpAndSettle();

    await tester.ensureVisible(find.text('Waltz in D'));
    await tester.pumpAndSettle();
    await tester.longPress(find.text('Waltz in D'));
    await tester.pumpAndSettle();
    expect(find.text('Rename'), findsNothing);
    for (final item in ['Share', 'Clone', 'Remove']) {
      expect(find.text(item), findsOneWidget);
    }
    await tester.tapAt(const Offset(4, 4));
    await tester.pumpAndSettle();

    // The sidebar closed, the ⋮ is back, and long-press renames again.
    await tester.tap(metronomeButton);
    await tester.pumpAndSettle();
    expect(more, findsNWidgets(2));
    await tester.longPress(find.text('Riff in E'));
    await tester.pumpAndSettle();
    expect(find.text('Share'), findsNothing);
    expect(find.byType(RenameDialog), findsOneWidget);
  });

  testWidgets('the dictionary rotated is a panel under the captures, above '
      'the navigation bar', (tester) async {
    await home(tester);
    await tester.tap(dictionaryButton);
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const Key('dictionary-rotate')));
    await tester.pumpAndSettle();
    expect(SidebarWidths.instance.isBelow(SidebarWidths.dictionary), isTrue);
    final panel = tester.getRect(dictionarySidebar);
    expect(panel.left, 0);
    expect(panel.right, 1200);
    expect(panel.bottom, lessThanOrEqualTo(tester.getTopLeft(bar).dy));
    expect(
      tester.getBottomLeft(search).dy,
      lessThan(tester.getTopLeft(dictionarySidebar).dy),
    );
  });

  for (final (name, titles) in [
    ('with captures', const ['Riff in E', 'Slow blues lick', 'Waltz in D']),
    ('with none', const <String>[]),
  ]) {
    testWidgets('a small phone $name: both sidebars, at the side and '
        'rotated, overflow nothing', (tester) async {
      await home(tester, size: const Size(320, 568), titles: titles);
      // The title and both buttons fit the app bar.
      expect(dictionaryButton, findsOneWidget);
      expect(metronomeButton, findsOneWidget);
      expect(tester.getTopRight(metronomeButton).dx, lessThanOrEqualTo(320));
      await tester.tap(dictionaryButton);
      await tester.pumpAndSettle();
      expect(tester.takeException(), isNull);
      expect(dictionarySidebar, findsOneWidget);
      await tester.tap(metronomeButton);
      await tester.pumpAndSettle();
      expect(tester.takeException(), isNull);
      // Rotated (the metronome's closed to reach Rotate, then open again).
      await tester.tap(find.byKey(const Key('metronome-close')));
      await tester.pumpAndSettle();
      await tester.tap(find.byKey(const Key('dictionary-rotate')));
      await tester.pumpAndSettle();
      expect(tester.takeException(), isNull);
      await tester.tap(metronomeButton);
      await tester.pumpAndSettle();
      expect(tester.takeException(), isNull);
      expect(metronomeSidebar, findsOneWidget);
      // The navigation bar stays whole and works.
      expect(tester.getBottomLeft(bar).dy, 568);
      await tester.tap(tab('Profile'));
      await tester.pumpAndSettle();
      expect(tester.takeException(), isNull);
      expect(find.text('About'), findsOneWidget);
    });
  }
}
