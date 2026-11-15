import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
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
        app: Uri.parse('https://tabs.cam/app/'),
      );
      expect(link.toString(), 'https://tabs.cam/app/?c=abc123');
      expect(CaptureLink.idIn(link), 'abc123');
    });

    test("a file's link adds its ID, found again by fileIn", () {
      final link = CaptureLink.of(
        event,
        file: event.pages.first,
        app: Uri.parse('https://tabs.cam/app/'),
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

    test('with its key, the short link: the key alone', () {
      final keyed = event.copyWith(linkKey: 'Ab3dEf9hJk2L');
      final site = Uri.parse('https://tabs.cam/app/');
      final link = CaptureLink.of(keyed, app: site);
      expect(link.toString(), 'https://tabs.cam/s/Ab3dEf9hJk2L');
      expect(CaptureLink.isShort(link), isTrue);
      // A file's adds its ID.
      expect(
        CaptureLink.of(keyed, file: event.pages.first, app: site).toString(),
        'https://tabs.cam/s/Ab3dEf9hJk2L?f=p1',
      );
      // The full link it stands for.
      expect(
        CaptureLink.full(keyed, app: site).toString(),
        'https://tabs.cam/app/?c=abc123&k=Ab3dEf9hJk2L',
      );
      // A site that doesn't answer short links (a local build): the full one.
      final local = Uri.parse('https://local.tabcam.nu01.com:2443/app/');
      expect(
        CaptureLink.of(keyed, app: local),
        CaptureLink.full(keyed, app: local),
      );
      expect(CaptureLink.isShort(CaptureLink.full(keyed, app: site)), isFalse);
      expect(
        CaptureLink.isShort(Uri.parse('https://tabs.cam/s/short')),
        isFalse,
      );
    });

    test('a short link resolves to the full one, by the redirect', () async {
      final asked = <http.BaseRequest>[];
      final client = MockClient.streaming((request, _) async {
        asked.add(request);
        final known = request.url.path == '/s/Ab3dEf9hJk2L';
        return http.StreamedResponse(
          const Stream.empty(),
          302,
          headers: {
            'location': known ? '/app/?c=abc123&k=Ab3dEf9hJk2L&f=p1' : '/app/',
          },
        );
      });
      expect(
        await CaptureLink.resolve(
          Uri.parse('https://rc.tabs.cam/s/Ab3dEf9hJk2L?f=p1'),
          client: client,
        ),
        Uri.parse('https://rc.tabs.cam/app/?c=abc123&k=Ab3dEf9hJk2L&f=p1'),
      );
      expect(asked.single.followRedirects, isFalse);
      // Android hands the path alone: the stage's site is asked.
      expect(
        (await CaptureLink.resolve(
          Uri.parse('/s/Ab3dEf9hJk2L'),
          client: client,
        ))?.host,
        'tabs.cam',
      );
      // An unknown one goes to the app: nothing to open.
      expect(
        await CaptureLink.resolve(
          Uri.parse('https://tabs.cam/s/Zz3dEf9hJk2L'),
          client: client,
        ),
        isNull,
      );
      // Offline: nothing.
      expect(
        await CaptureLink.resolve(
          Uri.parse('https://tabs.cam/s/Ab3dEf9hJk2L'),
          client: MockClient((_) => throw http.ClientException('offline')),
        ),
        isNull,
      );
    });

    test('a new link key is 12 letters and digits, an old one still a key', () {
      final key = newLinkKey();
      expect(key, matches(RegExp(r'^[A-Za-z0-9]{12}$')));
      expect(isShortLinkKey(key), isTrue);
      expect(newLinkKey(), isNot(key));
      const old = 'riffkey-0123456789abcdefghijklmn';
      expect(isLinkKey(old), isTrue);
      expect(isShortLinkKey(old), isFalse);
      expect(isLinkKey('short'), isFalse);
    });

    test('finds no ID in other links, or a bad one', () {
      expect(
        CaptureLink.idIn(Uri.parse('https://tabs.cam/app/')),
        isNull,
      );
      expect(
        CaptureLink.idIn(Uri.parse('https://tabs.cam/app/?c=../x')),
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

    final link = Uri.parse('https://tabs.cam/app/?c=abc123');
    expect(
      await links.didPushRouteInformation(RouteInformation(uri: link)),
      isTrue,
    );
    expect(told, 1);
    expect(links.take(), link);
    expect(links.take(), isNull);
    // A short link: kept once resolved to the full one.
    final full = Uri.parse('https://tabs.cam/app/?c=abc123&k=Ab3dEf9hJk2L');
    final resolve = links.resolve;
    addTearDown(() => links.resolve = resolve);
    links.resolve = (short) async =>
        short.path == '/s/Ab3dEf9hJk2L' ? full : null;
    expect(
      await links.didPushRouteInformation(
        RouteInformation(uri: Uri.parse('https://tabs.cam/s/Ab3dEf9hJk2L')),
      ),
      isTrue,
    );
    await tester.pump();
    expect(told, 2);
    expect(links.take(), full);
    // One that resolves to nothing: nothing waits.
    await links.didPushRouteInformation(
      RouteInformation(uri: Uri.parse('https://tabs.cam/s/Zz3dEf9hJk2L')),
    );
    await tester.pump();
    expect(told, 2);
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
