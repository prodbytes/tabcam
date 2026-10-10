import 'dart:convert';
import 'dart:typed_data';

import 'package:archive/archive.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:tabscan_app/export/capture_link.dart';
import 'package:tabscan_app/export/exporter.dart';
import 'package:tabscan_app/export/incoming_links.dart';
import 'package:flutter/widgets.dart';
import 'package:tabscan_app/library/capture_event.dart';
import 'package:tabscan_app/processing/page_filter.dart';

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
        app: Uri.parse('https://tabscan.nu01.com/app/'),
      );
      expect(link.toString(), 'https://tabscan.nu01.com/app/?c=abc123');
      expect(CaptureLink.idIn(link), 'abc123');
    });

    test('finds no ID in other links, or a bad one', () {
      expect(
        CaptureLink.idIn(Uri.parse('https://tabscan.nu01.com/app/')),
        isNull,
      );
      expect(
        CaptureLink.idIn(Uri.parse('https://tabscan.nu01.com/app/?c=../x')),
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

    final link = Uri.parse('https://tabscan.nu01.com/app/?c=abc123');
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

  test('Files is a zip of every file, the text tab and the links', () async {
    final bytes = await Exporter.zip(event, [
      Uint8List.fromList([1]),
      Uint8List.fromList([2, 2]),
      Uint8List.fromList([3, 3, 3]),
    ]);
    final archive = ZipDecoder().decodeBytes(bytes);
    String text(String name) =>
        utf8.decode(archive.findFile(name)!.readBytes()!);
    expect(
      [for (final f in archive.files) f.name],
      [
        'Made-up riff - Nobody 1.png',
        'Made-up riff - Nobody 2.jpg',
        'Made-up riff - Nobody 3.mp4',
        'tab.txt',
        'links.txt',
      ],
    );
    expect(archive.findFile('Made-up riff - Nobody 3.mp4')!.readBytes(), [
      3,
      3,
      3,
    ]);
    expect(text('tab.txt'), 'e|--0--3--|\nB|--1-----|\n');
    expect(text('links.txt'), 'https://example.com/lesson\n');
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
