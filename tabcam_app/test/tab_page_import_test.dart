import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:pdfrx/pdfrx.dart';
import 'package:tabcam_app/import/tab_page.dart';
import 'package:tabcam_app/import/tab_page_import.dart';
import 'package:tabcam_app/import/tab_page_pdf.dart';
import 'package:tabcam_app/library/capture_event.dart';
import 'package:tabcam_app/library/event_store_memory.dart';
import 'package:tabcam_app/library/library.dart';
import 'package:tabcam_app/recognition/pdf_reader.dart';
import 'package:tabcam_app/recognition/tab_layout.dart';

// Made-up riffs: tests never use published songs' tabs.
const _riff = [
  'e|-0-----3-|',
  'B|-1-----0-|',
  'G|-2-----0-|',
  'D|-2-----0-|',
  'A|-0-----2-|',
  'E|-------3-|',
];

final _ug = Uri.parse(
  'https://tabs.ultimate-guitar.com/tab/nobody/made-up-riff-tabs-1',
);

/// A page as Ultimate Guitar serves it: the tab in the page's data,
/// HTML-escaped in an attribute.
String _ugPage() {
  final data = {
    'store': {
      'page': {
        'data': {
          'tab': {'song_name': 'Made Up Riff', 'artist_name': 'Nobody'},
          'tab_view': {
            'wiki_tab': {
              'content':
                  '[Intro]\r\n[ch]Am[/ch]   [ch]G[/ch]\r\n'
                  '[tab]${_riff.join('\r\n')}[/tab]\r\n',
            },
          },
        },
      },
    },
  };
  final escaped = const HtmlEscape(HtmlEscapeMode.attribute)
      .convert(jsonEncode(data));
  return '<html><head><title>MADE UP RIFF TAB</title></head><body>'
      '<div class="js-store" data-content="$escaped"></div></body></html>';
}

void main() {
  group('tab sites', () {
    test('known sites and their subdomains', () {
      expect(tabSiteOf(_ug)?.name, 'Ultimate Guitar');
      expect(
        tabSiteOf(Uri.parse('https://www.cifraclub.com.br/x/y/'))?.name,
        'Cifra Club',
      );
      expect(
        tabSiteOf(Uri.parse('http://classtab.org/x.txt'))?.name,
        'Classtab',
      );
    });

    test('other sites, look-alikes and other schemes are not', () {
      for (final url in [
        'https://youtu.be/abc',
        'https://notultimate-guitar.com/tab/x',
        'https://ultimate-guitar.com.example.com/tab/x',
        'ftp://ultimate-guitar.com/x',
      ]) {
        expect(tabSiteOf(Uri.parse(url)), isNull, reason: url);
      }
    });
  });

  group('a tab site\'s page', () {
    final site = tabSiteOf(_ug)!;

    test('Ultimate Guitar: the tab from the page\'s data', () {
      final page = parseTabPage(_ugPage(), _ug, site)!;
      expect(page.title, 'Made Up Riff by Nobody');
      expect(page.text.split('\n'), ['[Intro]', 'Am   G', ..._riff]);
    });

    test('other sites: their <pre> blocks, tags dropped, entities read', () {
      const html =
          '<html><head><meta property="og:title" content="Riff &amp; Song">'
          '</head><body><pre class="x"><b>Am</b>    G&nbsp;&#47;B\n'
          'e|-0-----3-|<br>B|-1-----0-|\n</pre><pre>one line</pre></body>';
      final page = parseTabPage(html, _ug, site)!;
      expect(page.title, 'Riff & Song');
      expect(page.text, 'Am    G /B\ne|-0-----3-|\nB|-1-----0-|');
    });

    test('a plain-text page is the tab', () {
      final page = parseTabPage(
        '${_riff.join('\r\n')}\r\n\r\n\r\n',
        _ug,
        site,
        contentType: 'text/plain; charset=utf-8',
      )!;
      expect(page.text, _riff.join('\n'));
    });

    test('a page drawn by scripts has no tab', () {
      expect(
        parseTabPage(
          '<html><body><div id="app"></div></body></html>',
          _ug,
          site,
        ),
        isNull,
      );
    });
  });

  test('printed as a PDF, its text reads as the tab', () async {
    final page = TabPage(
      url: _ug,
      site: tabSiteOf(_ug)!,
      title: 'Made Up Riff by Nobody',
      text: ['Intro', ..._riff].join('\n'),
    );
    final bytes = await tabPagePdf(page, printed: DateTime(2026, 10, 16));
    expect(String.fromCharCodes(bytes.take(5)), '%PDF-');
    String? tab;
    try {
      await pdfrxInitialize(tmpPath: Directory.systemTemp.path);
      final pdf = await PdfDocument.openData(bytes);
      final raw = (await pdf.pages.single.loadText())!;
      tab = asciiTab(
        pdfLines(raw.fullText, [
          for (final r in raw.charRects)
            (left: r.left, top: r.top, right: r.right, bottom: r.bottom),
        ]),
      );
      await pdf.dispose();
    } on Object catch (e) {
      markTestSkipped('PDFium isn\'t available here: $e');
      return;
    }
    expect(tab, contains(_riff.join('\n')));
  });

  group('importing a link', () {
    late Library library;
    late CaptureEvent event;
    late List<Uri> fetched;
    setUp(() async {
      library = Library(PlatformEventStore(), null, (_) async => null);
      await library.load();
      event = await library.create(const []);
      fetched = [];
    });

    TabPageImporter importer(http.Response Function() answer) =>
        TabPageImporter(
          client: MockClient((request) async {
            fetched.add(request.url);
            return answer();
          }),
          onDevice: true,
        );

    test('a tab site\'s page is added as a PDF, named after it', () async {
      final done = await importer(
        () => http.Response(
          _ugPage(),
          200,
          headers: {'content-type': 'text/html; charset=utf-8'},
        ),
      ).addTo(library, event, _ug);
      expect(done!.outcome, TabImportOutcome.imported);
      expect(fetched, [_ug]);
      final pdf = library.byId(event.id)!.pages.single;
      expect(pdf.kind, PageKind.pdf);
      expect(pdf.title, 'Made Up Riff by Nobody');
    });

    test('any other link is left alone: nothing fetched', () async {
      final done = await importer(() => http.Response('', 200))
          .addTo(library, event, Uri.parse('https://youtu.be/abc'));
      expect(done, isNull);
      expect(fetched, isEmpty);
    });

    test(
      'a page that won\'t come (a bot check) fails, adding nothing',
      () async {
        final done = await importer(
          () => http.Response('<html>Just a moment...</html>', 403),
        ).addTo(library, event, _ug);
        expect(done!.outcome, TabImportOutcome.failed);
        expect(library.byId(event.id)!.pages, isEmpty);
      },
    );

    test("a reader's print is their own, as the link is", () async {
      await library.applyRemote(
        event.copyWith(sharedBy: 'julio@example.com', readOnly: true),
      );
      final shared = await library.addLink(library.byId(event.id)!, _ug);
      final done = await importer(
        () => http.Response(
          _ugPage(),
          200,
          headers: {'content-type': 'text/html; charset=utf-8'},
        ),
      ).addTo(library, shared, _ug);
      expect(done!.outcome, TabImportOutcome.imported);
      final now = library.byId(event.id)!;
      expect(now.pages, isEmpty);
      expect(now.myContribution!.pages.map((p) => p.kind), [
        PageKind.link,
        PageKind.pdf,
      ]);
    });

    test('on the web, without Premium, nothing is fetched', () async {
      final done = await TabPageImporter(
        client: MockClient((request) async {
          fetched.add(request.url);
          return http.Response(_ugPage(), 200);
        }),
        onDevice: false,
      ).addTo(library, event, _ug);
      expect(done!.outcome, TabImportOutcome.needsPremium);
      expect(fetched, isEmpty);
    });
  });
}
