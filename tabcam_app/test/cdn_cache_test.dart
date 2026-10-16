import 'dart:io';
import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:tabcam_app/cloud/cdn.dart';
import 'package:tabcam_app/cloud/http_cache.dart';
import 'package:tabcam_app/cloud/http_cache_store_io.dart';
import 'package:tabcam_app/cloud/s3.dart';
import 'package:tabcam_app/cloud/sigv4.dart';

const _owner = 'us-east-1:11111111-1111-1111-1111-111111111111';
final _site = Uri.parse('https://tabcam.nu01.com');

CdnGrant _grant({String prefix = '$_owner/', DateTime? until}) => CdnGrant(
  prefix: prefix,
  expiration: until ?? DateTime.utc(2026, 10, 17, 1),
  hosts: const {
    'tabcam.nu01.com': 'Policy=p&Signature=s&Key-Pair-Id=K',
    'rc.tabcam.nu01.com': 'Policy=rc&Signature=rs&Key-Pair-Id=K',
  },
);

AwsCredentials _creds([CdnGrant? cdn]) => AwsCredentials(
  accessKeyId: 'AKID',
  secretAccessKey: 'secret',
  sessionToken: 'token',
  cdn: cdn,
);

void main() {
  group('CdnGrant', () {
    final now = DateTime.utc(2026, 10, 17);

    test('signs only its own folder, on a site it names, while it lasts', () {
      final grant = _grant();
      expect(
        grant.urlOf('$_owner/events/e1/p1.jpg', _site, now).toString(),
        'https://tabcam.nu01.com/$_owner/events/e1/p1.jpg'
        '?Policy=p&Signature=s&Key-Pair-Id=K',
      );
      expect(
        grant
            .urlOf(
              '$_owner/events/e1/p1.jpg',
              Uri.parse('https://rc.tabcam.nu01.com'),
              now,
            )
            ?.query,
        'Policy=rc&Signature=rs&Key-Pair-Id=K',
      );
      // Another folder, another site, an expired or nearly expired grant.
      expect(
        grant.urlOf('us-east-1:other/events/e1/p1.jpg', _site, now),
        isNull,
      );
      expect(
        grant.urlOf('$_owner/x', Uri.parse('https://example.com'), now),
        isNull,
      );
      expect(
        _grant(until: now.add(const Duration(seconds: 30)))
            .urlOf('$_owner/x', _site, now),
        isNull,
      );
      // A key that would need encoding is read from S3.
      expect(grant.urlOf('$_owner/events/e 1/p?.jpg', _site, now), isNull);
    });

    test('parses the share API\'s, and nothing else', () {
      final grant = CdnGrant.fromJson({
        'prefix': '$_owner/events/abc/',
        'expiration': 1792200000,
        'hosts': {'tabcam.nu01.com': 'Policy=a'},
      })!;
      expect(grant.prefix, '$_owner/events/abc/');
      expect(grant.expiration.millisecondsSinceEpoch, 1792200000 * 1000);
      expect(grant.hosts, {'tabcam.nu01.com': 'Policy=a'});
      expect(CdnGrant.fromJson(null), isNull);
      expect(
        CdnGrant.fromJson({'prefix': _owner, 'expiration': 1, 'hosts': {}}),
        isNull,
      );
    });
  });

  group('CacheControl', () {
    test('immutable files are fresh for their max-age, JSON never', () {
      final page = CacheControl.parse('public, max-age=31536000, immutable');
      expect(page.freshFor, const Duration(days: 365));
      expect(page.immutable, isTrue);
      expect(CacheControl.parse('no-cache').freshFor, Duration.zero);
      expect(
        CacheControl.parse('no-cache, max-age=60').freshFor,
        Duration.zero,
      );
      expect(CacheControl.parse(null).freshFor, Duration.zero);
      expect(CacheControl.parse('No-Store').noStore, isTrue);
    });
  });

  group('HttpCache', () {
    late DateTime now;
    late List<http.BaseRequest> sent;
    late MemoryHttpCacheStore store;
    late http.Response Function(http.BaseRequest) answer;

    HttpCache cache() => HttpCache(
      store: store,
      now: () => now,
      client: MockClient((request) async {
        sent.add(request);
        return answer(request);
      }),
    );

    setUp(() {
      now = DateTime.utc(2026, 10, 17);
      sent = [];
      store = MemoryHttpCacheStore();
    });

    final url = Uri.parse('https://tabcam.nu01.com/k?Policy=1');

    Future<void> settle() => Future<void>.delayed(Duration.zero);

    test('a fresh copy is used without asking, until its max-age', () async {
      answer = (_) => http.Response.bytes(
        [1, 2],
        200,
        headers: {
          'cache-control': 'public, max-age=60',
          'etag': '"e1"',
          'age': '10',
        },
      );
      final c = cache();
      expect(await c.get(url, 'k'), [1, 2]);
      await settle();
      now = now.add(const Duration(seconds: 49));
      // Another hour's signature: the same object.
      expect(await c.get(url.replace(query: 'Policy=2'), 'k'), [1, 2]);
      expect(sent, hasLength(1));
      // 10 s in CloudFront + 50 here: stale, revalidated.
      now = now.add(const Duration(seconds: 1));
      answer = (_) => http.Response('', 304, headers: {'age': '0'});
      expect(await c.get(url, 'k'), [1, 2]);
      expect(sent.last.headers['if-none-match'], '"e1"');
    });

    test('no-cache is kept, and always revalidated by its ETag', () async {
      answer = (_) => http.Response.bytes(
        [7],
        200,
        headers: {'cache-control': 'no-cache', 'etag': '"v1"'},
      );
      final c = cache();
      expect(await c.get(url, 'event.json'), [7]);
      await settle();
      answer = (_) => http.Response('', 304);
      expect(await c.get(url, 'event.json'), [7]);
      expect(sent, hasLength(2));
      expect(sent.last.headers['if-none-match'], '"v1"');
      // Changed: the new body, kept in its place.
      answer = (_) => http.Response.bytes(
        [8],
        200,
        headers: {'cache-control': 'no-cache', 'etag': '"v2"'},
      );
      expect(await c.get(url, 'event.json'), [8]);
      await settle();
      expect(store.entries['event.json']!.etag, '"v2"');
    });

    test('no-store and errors are never kept', () async {
      answer = (_) =>
          http.Response.bytes([1], 200, headers: {'cache-control': 'no-store'});
      final c = cache();
      await c.get(url, 'k');
      await settle();
      expect(store.entries, isEmpty);
      answer = (_) => http.Response('denied', 403);
      expect(() => c.get(url, 'j'), throwsA(isA<HttpCacheException>()));
    });

    test(
      'a streamed body is kept as it passes, then served from the cache',
      () async {
        answer = (_) => http.Response.bytes(
          [1, 2, 3],
          200,
          headers: {
            'cache-control': 'public, max-age=31536000, immutable',
            'content-length': '3',
          },
        );
        final c = cache();
        expect(
          await (await c.getStream(url, 'v.mp4')).expand((b) => b).toList(),
          [1, 2, 3],
        );
        await settle();
        expect(
          await (await c.getStream(url, 'v.mp4')).expand((b) => b).toList(),
          [1, 2, 3],
        );
        expect(sent, hasLength(1));
      },
    );

    test('bodies over the limit pass through, unkept', () async {
      answer = (_) => http.Response.bytes(
        List.filled(10, 1),
        200,
        headers: {
          'cache-control': 'public, max-age=60',
          'content-length': '10',
        },
      );
      final c = HttpCache(
        store: store,
        now: () => now,
        maxEntryBytes: 5,
        client: MockClient((r) async => answer(r)),
      );
      await (await c.getStream(url, 'big')).drain<void>();
      await c.get(url, 'big2');
      await settle();
      expect(store.entries, isEmpty);
    });

    test(
      'the memory store drops the least recently used past its limit',
      () async {
        final small = MemoryHttpCacheStore(maxBytes: 4);
        CachedResponse entry(int n) =>
            CachedResponse(body: Uint8List(n), storedAt: now);
        await small.write('a', entry(2));
        await small.write('b', entry(2));
        await small.read('a');
        await small.write('c', entry(2));
        expect(small.entries.keys, ['a', 'c']);
      },
    );
  });

  test('the file store keeps headers and body, and trims the oldest', () async {
    final dir = await Directory.systemTemp.createTemp('tabcam-cache');
    addTearDown(() => dir.delete(recursive: true));
    final store = PlatformHttpCacheStore(maxBytes: 5, dir: dir);
    final at = DateTime.utc(2026, 10, 17);
    await store.write(
      'a',
      CachedResponse(
        body: Uint8List.fromList([1, 2, 3]),
        storedAt: at,
        etag: '"a"',
        cacheControl: 'no-cache',
      ),
    );
    final a = (await store.read('a'))!;
    expect(a.body, [1, 2, 3]);
    expect(a.etag, '"a"');
    expect(a.storedAt, at);
    await Future<void>.delayed(const Duration(milliseconds: 20));
    await store.write('b', CachedResponse(body: Uint8List(3), storedAt: at));
    expect(await store.read('a'), isNull);
    expect(await store.read('b'), isNotNull);
    await store.clear();
    expect(await store.read('b'), isNull);
  });

  group('S3Bucket through CloudFront', () {
    late List<http.BaseRequest> sent;
    late http.Response Function(http.BaseRequest) answer;

    S3Bucket bucket({Uri? site}) => S3Bucket(
      bucket: 'b',
      region: 'us-east-1',
      now: () => DateTime.utc(2026, 10, 17),
      cdnSite: site,
      cache: site == null
          ? null
          : HttpCache(
              store: MemoryHttpCacheStore(),
              now: () => DateTime.utc(2026, 10, 17),
              client: MockClient((r) async {
                sent.add(r);
                return answer(r);
              }),
            ),
      client: MockClient((r) async {
        sent.add(r);
        return answer(r);
      }),
    );

    setUp(() => sent = []);

    test(
      'a granted key is read from the site, unsigned, then cached',
      () async {
        answer = (_) => http.Response.bytes(
          [4, 2],
          200,
          headers: {'cache-control': 'public, max-age=31536000, immutable'},
        );
        final b = bucket(site: _site);
        final key = '$_owner/events/e1/p1.jpg';
        expect(await b.get(key, credentials: _creds(_grant())), [4, 2]);
        expect(sent.single.url.host, 'tabcam.nu01.com');
        expect(sent.single.url.path, '/$key');
        expect(sent.single.headers['authorization'], isNull);
        await Future<void>.delayed(Duration.zero);
        expect(await b.get(key, credentials: _creds(_grant())), [4, 2]);
        expect(sent, hasLength(1));
      },
    );

    test(
      'without a grant, or a site, or when CloudFront says no: S3',
      () async {
        answer = (r) => r.url.host == 'tabcam.nu01.com'
            ? http.Response('', 403)
            : http.Response.bytes([9], 200);
        final key = '$_owner/events/e1/event.json';
        expect(await bucket().get(key, credentials: _creds(_grant())), [9]);
        expect(sent.single.url.host, 'b.s3.us-east-1.amazonaws.com');
        sent.clear();
        expect(await bucket(site: _site).get(key, credentials: _creds()), [9]);
        expect(sent.single.url.host, 'b.s3.us-east-1.amazonaws.com');
        sent.clear();
        expect(
          await bucket(site: _site).get(key, credentials: _creds(_grant())),
          [9],
        );
        expect(sent.map((r) => r.url.host), [
          'tabcam.nu01.com',
          'b.s3.us-east-1.amazonaws.com',
        ]);
      },
    );

    test(
      'uploads say how to cache them: pages a year, JSON revalidated',
      () async {
        answer = (_) => http.Response('', 200);
        final b = bucket();
        await b.put(
          '$_owner/events/e1/p1.jpg',
          Uint8List(1),
          contentType: 'image/jpeg',
          credentials: _creds(),
        );
        await b.put(
          '$_owner/events/e1/event.json',
          Uint8List(1),
          contentType: 'application/json',
          credentials: _creds(),
        );
        expect(
          sent[0].headers['cache-control'],
          'public, max-age=31536000, immutable',
        );
        expect(sent[1].headers['cache-control'], 'no-cache');
        // Signed: S3 keeps it as the object's Cache-Control.
        expect(sent[0].headers['authorization'], contains('cache-control'));
      },
    );
  });
}
