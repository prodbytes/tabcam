import 'package:flutter_test/flutter_test.dart';
import 'package:tabcam_app/export/capture_link.dart';
import 'package:tabcam_app/export/incoming_links.dart';
import 'package:flutter/widgets.dart';
import 'package:tabcam_app/library/capture_event.dart';
import 'package:tabcam_app/processing/page_filter.dart';

void main() {
  final event = CaptureEvent(
    id: 'abc123',
    title: 'Made-up riff',
    artist: 'Nobody',
    created: DateTime.utc(2026, 10, 10),
    pages: [
      const EventPage(id: 'p1'),
      const EventPage(id: 'p2', filter: PageFilter.original, extension: 'jpg'),
      EventPage.link(id: 'l1', url: Uri.parse('https://example.com/lesson')),
      const EventPage(id: 'v1', kind: PageKind.video, extension: 'mp4'),
    ],
    tabText: 'e|--0--3--|\nB|--1-----|\n',
  );

  group('CaptureLink', () {
    test('names the capture by its ID only', () {
      final link = CaptureLink.of(
        event,
        app: Uri.parse('https://tabcam.nu01.com/app/'),
      );
      expect(link.toString(), 'https://tabcam.nu01.com/app/?c=abc123');
      expect(CaptureLink.idIn(link), 'abc123');
    });

    test("a file's link adds its ID, found again by fileIn", () {
      final link = CaptureLink.of(
        event,
        file: event.pages.first,
        app: Uri.parse('https://tabcam.nu01.com/app/'),
      );
      expect(link.queryParameters['c'], 'abc123');
      expect(link.queryParameters['f'], event.pages.first.id);
      expect(CaptureLink.fileIn(link), event.pages.first.id);
      expect(CaptureLink.fileIn(Uri.parse('https://x/app/?c=abc123')), isNull);
      expect(
        CaptureLink.fileIn(Uri.parse('https://x/app/?c=abc123&f=../x')),
        isNull,
      );
    });

    test('finds no ID in other links, or a bad one', () {
      expect(
        CaptureLink.idIn(Uri.parse('https://tabcam.nu01.com/app/')),
        isNull,
      );
      expect(
        CaptureLink.idIn(Uri.parse('https://tabcam.nu01.com/app/?c=../x')),
        isNull,
      );
    });
  });

  testWidgets('a capture link pushed to the app is kept for Home', (
    tester,
  ) async {
    final links = IncomingLinks.instance;
    links.take();
    var told = 0;
    void tell() => told++;
    links.addListener(tell);
    addTearDown(() => links.removeListener(tell));

    final link = Uri.parse('https://tabcam.nu01.com/app/?c=abc123');
    expect(
      await links.didPushRouteInformation(RouteInformation(uri: link)),
      isTrue,
    );
    expect(told, 1);
    expect(links.take(), link);
    expect(links.take(), isNull);
    // Other routes are left to the app.
    expect(
      await links.didPushRouteInformation(
        RouteInformation(uri: Uri.parse('/settings')),
      ),
      isFalse,
    );
  });

  test('shares and the owner survive the cloud copy', () {
    final shared = event.copyWith(
      owner: 'us-east-1:me',
      shares: const [EventShare('ana@example.com', readOnly: true)],
      sharedBy: 'someone@example.com',
    );
    final back = CaptureEvent.fromJson(shared.toJson(local: false));
    expect(back.owner, 'us-east-1:me');
    expect(back.shares, shared.shares);
    expect(back.sharedBy, isNull);
  });
}
