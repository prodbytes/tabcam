import 'package:cross_file/cross_file.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:plugin_platform_interface/plugin_platform_interface.dart';
import 'package:tabscan_app/capture/media.dart';
import 'package:tabscan_app/cloud/cloud_sync.dart';
import 'package:tabscan_app/l10n/app_localizations_en.dart';
import 'package:tabscan_app/library/capture_event.dart';
import 'package:tabscan_app/library/event_store_memory.dart';
import 'package:tabscan_app/library/library.dart';
import 'package:tabscan_app/screens/audio_page.dart';
import 'package:tabscan_app/screens/home_screen.dart';
import 'package:tabscan_app/screens/link_page.dart';
import 'package:tabscan_app/screens/pdf_page.dart';
import 'package:url_launcher_platform_interface/link.dart';
import 'package:url_launcher_platform_interface/url_launcher_platform_interface.dart';

/// Records how the app opens URLs, opening none; [inApp] says whether a
/// browser inside the app is there.
class _FakeLauncher extends Fake
    with MockPlatformInterfaceMixin
    implements UrlLauncherPlatform {
  _FakeLauncher({this.inApp = true});

  final bool inApp;
  final modes = <PreferredLaunchMode>[];

  @override
  LinkDelegate? get linkDelegate => null;

  @override
  Future<bool> launchUrl(String url, LaunchOptions options) async {
    modes.add(options.mode);
    return inApp || options.mode != PreferredLaunchMode.inAppBrowserView;
  }
}

final _event = CaptureEvent(
  id: 'e1',
  title: 'Riff',
  created: DateTime(2026, 10, 11),
  pages: [
    const EventPage(id: 'p1', extension: 'jpg'),
    const EventPage(id: 'p2', kind: PageKind.audio, extension: 'mp3'),
    const EventPage(id: 'p3', kind: PageKind.pdf, extension: 'pdf'),
    EventPage.link(id: 'p4', url: Uri.parse('https://example.com/lesson')),
  ],
);

void main() {
  test('recordings and PDFs are picked as pages; other files are not', () {
    expect(Media.of(XFile('a/riff.MP3'))!.kind, PageKind.audio);
    expect(Media.of(XFile('a/riff.m4a'))!.kind, PageKind.audio);
    expect(Media.of(XFile('a/tab.pdf'))!.kind, PageKind.pdf);
    final byMime = Media.of(XFile('a/blob', mimeType: 'application/pdf'))!;
    expect((byMime.kind, byMime.extension), (PageKind.pdf, 'pdf'));
    expect(Media.of(XFile('a/notes.txt')), isNull);
    expect(Media.extensions, containsAll(['jpg', 'mp4', 'mp3', 'pdf']));
  });

  test('recordings and PDFs keep their kind, and their MIME type', () {
    for (final page in _event.pages.where((p) => p.hasFile)) {
      final back = EventPage.fromJson(page.toJson());
      expect((back.kind, back.extension), (page.kind, page.extension));
    }
    expect(_event.pages[1].mimeType, 'audio/mpeg');
    expect(CloudSync.contentTypeOf(_event.pages[2]), 'application/pdf');
    // A kind from a newer app shows as an image, as before kinds.
    final unknown = EventPage.fromJson({'id': 'x', 'kind': 'hologram'});
    expect(unknown.kind, PageKind.image);
  });

  test('an event counts its recordings and PDFs', () {
    expect(
      contentsOf(_event, AppLocalizationsEn()),
      '1 page, 1 recording, 1 PDF, 1 link',
    );
  });

  testWidgets('a recording shows a play button', (tester) async {
    final library = Library(PlatformEventStore(), null, (_) async => null);
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: AudioPage(
            library: library,
            event: _event,
            page: _event.pages[1],
          ),
        ),
      ),
    );
    expect(find.text('Recording'), findsOneWidget);
    expect(find.byTooltip('Play'), findsOneWidget);
  });

  testWidgets('a PDF that can\'t be read says so', (tester) async {
    // The store has no file for it.
    final library = Library(PlatformEventStore(), null, (_) async => null);
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: PdfPage(library: library, event: _event, page: _event.pages[2]),
        ),
      ),
    );
    await tester.runAsync(() => Future<void>.delayed(Duration.zero));
    await tester.pump();
    expect(find.text('This PDF can\'t be shown here'), findsOneWidget);
  });

  Future<void> tapOpen(WidgetTester tester) async {
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(body: LinkPage(page: _event.pages[3])),
      ),
    );
    await tester.tap(find.text('Open'));
    await tester.pumpAndSettle();
  }

  testWidgets('Open shows a link in a browser inside the app', (tester) async {
    final launcher = _FakeLauncher();
    UrlLauncherPlatform.instance = launcher;
    await tapOpen(tester);
    expect(launcher.modes, [PreferredLaunchMode.inAppBrowserView]);
  });

  testWidgets('without a browser inside the app, Open uses the browser', (
    tester,
  ) async {
    final launcher = _FakeLauncher(inApp: false);
    UrlLauncherPlatform.instance = launcher;
    await tapOpen(tester);
    expect(launcher.modes, [
      PreferredLaunchMode.inAppBrowserView,
      PreferredLaunchMode.externalApplication,
    ]);
    expect(find.textContaining('Couldn\'t open'), findsNothing);
  });
}
