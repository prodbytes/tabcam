import 'dart:typed_data';

import 'package:cross_file/cross_file.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:image/image.dart' as img;
import 'package:intl/intl.dart';
import 'package:tabcam_app/capture/media.dart';
import 'package:tabcam_app/l10n/app_localizations.dart';
import 'package:tabcam_app/library/capture_event.dart';
import 'package:tabcam_app/library/event_store_memory.dart';
import 'package:tabcam_app/library/file_label.dart';
import 'package:tabcam_app/library/library.dart';
import 'package:tabcam_app/screens/event_screen.dart';

Future<void> frames(WidgetTester tester) async {
  for (var i = 0; i < 20; i++) {
    await tester.pump(const Duration(milliseconds: 50));
  }
}

Media _file(String name, PageKind kind, String ext) =>
    Media(XFile.fromData(Uint8List.fromList([1]), path: name), kind, ext);

void main() {
  late Library library;
  setUp(() => library = Library(PlatformEventStore(), null, (_) async => null));

  Future<CaptureEvent> open(WidgetTester tester, {String? title}) async {
    late CaptureEvent event;
    await tester.runAsync(() async {
      await library.load();
      event = await library.create([
        img.encodeJpg(img.Image(width: 8, height: 8)),
      ]);
      event = await library.addMedia(event, [
        _file(title ?? 'Made-up riff.m4a', PageKind.audio, 'm4a'),
      ]);
    });
    await tester.pumpWidget(
      MaterialApp(
        localizationsDelegates: AppLocalizations.localizationsDelegates,
        supportedLocales: AppLocalizations.supportedLocales,
        home: EventScreen(library: library, eventId: event.id),
      ),
    );
    await frames(tester);
    return event;
  }

  Finder nameOf(WidgetTester tester, CaptureEvent event, EventPage page) {
    final row = find.byKey(ValueKey('file-${page.id}'));
    final l10n = AppLocalizations.of(tester.element(row))!;
    return find.descendant(
      of: row,
      matching: find.text(fileLabel(l10n, event, page)),
    );
  }

  testWidgets('each file shows the date it was made right after its name, '
      'smaller and dimmer', (tester) async {
    tester.view.physicalSize = const Size(1280, 800);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);
    final event = await open(tester);
    expect(event.pages, hasLength(2));
    for (final page in event.pages) {
      final made = timeOfId(page.id)!;
      final date = find.byKey(ValueKey('file-date-${page.id}'));
      expect(date, findsOneWidget);
      expect(
        tester.widget<Text>(date).data,
        DateFormat.MMMd('en').format(made),
      );
      // After the name, on its line.
      final name = nameOf(tester, event, page);
      expect(name, findsOneWidget);
      expect(
        tester.getTopLeft(date).dx,
        greaterThan(tester.getTopRight(name).dx),
      );
      expect(
        tester.getBottomLeft(date).dy,
        moreOrLessEquals(tester.getBottomLeft(name).dy, epsilon: 1),
      );
      // Smaller than the name, and dimmer.
      final style = tester.widget<Text>(date).style!;
      final nameStyle = DefaultTextStyle.of(tester.element(name)).style;
      expect(style.fontSize!, lessThan(nameStyle.fontSize!));
      expect(style.color!.a, lessThan(1));
    }
  });

  testWidgets('on a phone, a long name keeps its line and the date goes '
      'under it, whole', (tester) async {
    tester.view.physicalSize = const Size(360, 740);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);
    final event = await open(
      tester,
      title: 'A very long name for a made-up riff take recorded twice.m4a',
    );
    expect(tester.takeException(), isNull);
    final page = event.pages.last;
    final date = find.byKey(ValueKey('file-date-${page.id}'));
    final name = nameOf(tester, event, page);
    expect(date, findsOneWidget);
    expect(tester.getTopLeft(date).dy, greaterThan(tester.getTopLeft(name).dy));
    final row = tester.getRect(find.byKey(ValueKey('file-${page.id}')));
    expect(tester.getRect(date).right, lessThanOrEqualTo(row.right));
    expect(tester.getRect(date).bottom, lessThanOrEqualTo(row.bottom));
  });

  testWidgets('the year shows only when it is not this one', (tester) async {
    late BuildContext context;
    await tester.pumpWidget(
      MaterialApp(
        home: Builder(
          builder: (c) {
            context = c;
            return const SizedBox();
          },
        ),
      ),
    );
    final now = DateTime(2026, 11, 21);
    expect(fileDate(context, DateTime(2026, 3, 4, 9, 30), now), 'Mar 4');
    expect(fileDate(context, DateTime(2025, 3, 4), now), 'Mar 4, 2025');
  });
}
