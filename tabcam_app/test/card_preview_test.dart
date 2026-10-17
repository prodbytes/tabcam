import 'dart:ui' as ui;

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:tabcam_app/l10n/language.dart';
import 'package:tabcam_app/library/capture_event.dart';
import 'package:tabcam_app/library/event_store_memory.dart';
import 'package:tabcam_app/library/library.dart';
import 'package:tabcam_app/screens/card_preview.dart';
import 'package:tabcam_app/screens/library_screen.dart';

/// A made-up riff.
const _riff = 'Riff A\ne|--0--3--5--|\nB|--1--1--1--|\nG|--2--0--2--|';

Future<void> _frames(WidgetTester tester) async {
  for (var i = 0; i < 10; i++) {
    await tester.pump(const Duration(milliseconds: 50));
  }
}

/// Lets the previews render (which takes real time), then shows them.
Future<void> _rendered(WidgetTester tester) async {
  await tester.runAsync(
    () => Future<void>.delayed(const Duration(milliseconds: 100)),
  );
  await _frames(tester);
}

/// Home with one capture of [pages] (and [tabText]).
Future<Library> _home(
  WidgetTester tester,
  List<EventPage> pages, {
  String? tabText,
  bool hideImages = false,
}) async {
  final library = Library(PlatformEventStore(), null, (_) async => null);
  await tester.runAsync(() async {
    await library.load();
    final event = await library.create(const []);
    await library.update(
      event.copyWith(pages: pages, tabText: tabText, hideImages: hideImages),
    );
  });
  await _show(tester, library);
  return library;
}

/// Home, showing [library].
Future<void> _show(WidgetTester tester, Library library) async {
  await tester.pumpWidget(
    MaterialApp(
      localizationsDelegates: AppLocalizations.localizationsDelegates,
      supportedLocales: AppLocalizations.supportedLocales,
      home: Scaffold(body: LibraryView(library: library)),
    ),
  );
  await _frames(tester);
}

const _pdf = EventPage(id: 'p1', kind: PageKind.pdf, extension: 'pdf');

void main() {
  late List<String> rendered;
  setUp(() {
    rendered = [];
    PdfPreviews.clear();
    // The app's PDFium isn't loadable in tests: a blank page stands in.
    PdfPreviews.render = (library, event, page) async {
      rendered.add(page.id);
      final recorder = ui.PictureRecorder();
      Canvas(recorder).drawColor(Colors.white, BlendMode.src);
      return recorder.endRecording().toImage(8, 11);
    };
  });

  testWidgets('a capture with only its text tab previews the text', (
    tester,
  ) async {
    await _home(tester, const [], tabText: _riff);
    expect(find.byType(TextPreview), findsOneWidget);
    expect(find.textContaining('e|--0--3--5--|'), findsOneWidget);
    expect(find.byIcon(Icons.description_outlined), findsNothing);
  });

  testWidgets('hidden images: the text, never the image', (tester) async {
    await _home(
      tester,
      const [
        EventPage(id: 'p1', extension: 'jpg'),
        EventPage(id: 'p2', kind: PageKind.video, extension: 'mp4'),
      ],
      tabText: _riff,
      hideImages: true,
    );
    expect(find.textContaining('e|--0--3--5--|'), findsOneWidget);
    // The video is a badge on the text.
    expect(find.byIcon(Icons.play_arrow), findsOneWidget);
    expect(find.byType(Image), findsNothing);
  });

  testWidgets('a PDF previews its first page, rendered once', (tester) async {
    final library = await _home(tester, const [_pdf]);
    await _rendered(tester);
    final image = tester.widget<RawImage>(find.byType(RawImage));
    expect(image.image, isNotNull);
    // With the PDF badge.
    expect(find.byIcon(Icons.picture_as_pdf_outlined), findsOneWidget);
    expect(rendered, ['p1']);

    // Built again (scrolled back, say): from memory.
    await tester.pumpWidget(const SizedBox());
    await _show(tester, library);
    expect(find.byType(RawImage), findsOneWidget);
    expect(rendered, ['p1']);
  });

  testWidgets('a PDF that can\'t be rendered shows the text, then the icon', (
    tester,
  ) async {
    PdfPreviews.render = (library, event, page) async => null;
    await _home(tester, const [_pdf], tabText: _riff);
    await _rendered(tester);
    expect(find.byType(RawImage), findsNothing);
    expect(find.textContaining('e|--0--3--5--|'), findsOneWidget);
  });

  testWidgets('a link previews its title and host', (tester) async {
    await _home(tester, [
      EventPage.link(
        id: 'p1',
        url: Uri.parse('https://example.com/lesson'),
        title: 'Riff lesson',
      ),
    ]);
    expect(find.byType(LinkPreview), findsOneWidget);
    expect(find.text('Riff lesson'), findsOneWidget);
    expect(find.text('example.com'), findsOneWidget);
  });

  testWidgets('a recording alone keeps its icon', (tester) async {
    await _home(tester, const [
      EventPage(id: 'p1', kind: PageKind.audio, extension: 'mp3'),
    ]);
    expect(find.byIcon(Icons.music_note), findsOneWidget);
  });

  testWidgets('on a phone, the card\'s text and icons are a little smaller', (
    tester,
  ) async {
    addTearDown(tester.view.reset);
    tester.view.devicePixelRatio = 1;
    Future<(double?, double?, double?)> sizes(Size size) async {
      tester.view.physicalSize = size;
      await _home(tester, const [
        EventPage(id: 'p1', kind: PageKind.audio, extension: 'mp3'),
      ]);
      // The music note leaves the title the card's first text.
      final title = tester.widget<Text>(
        find
            .descendant(of: find.byType(Card), matching: find.byType(Text))
            .first,
      );
      return (
        tester.widget<Icon>(find.byIcon(Icons.music_note)).size,
        tester
            .widget<PopupMenuButton<Object?>>(
              find.byWidgetPredicate((w) => w is PopupMenuButton),
            )
            .iconSize,
        title.style?.fontSize,
      );
    }

    final (wideIcon, wideMore, wideTitle) = await sizes(const Size(1200, 900));
    final (icon, more, title) = await sizes(const Size(400, 800));
    expect(wideIcon, 48);
    expect(icon, 40);
    expect(wideMore, isNull);
    expect(more, 20);
    expect(title, wideTitle! - 1);
  });
}
