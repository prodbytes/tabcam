// The store screenshots: the real app's screens, signed in with a fake
// account, over made-up captures (made-up riffs, example.com addresses),
// rendered at each store's pixel sizes and written to tabcam_store/.
//
// Not part of `flutter test` (it isn't under test/): run it with
// `bash scripts/store-screenshots.sh`.

import 'dart:io';
import 'dart:math' as math;
import 'dart:ui' as ui;

import 'package:camera_platform_interface/camera_platform_interface.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:image/image.dart' as img;
import 'package:tabcam_app/auth/auth_service.dart';
import 'package:tabcam_app/cloud/cloud_sync.dart';
import 'package:tabcam_app/cloud/share_api.dart';
import 'package:tabcam_app/library/event_store_memory.dart';
import 'package:tabcam_app/library/library.dart';
import 'package:tabcam_app/main.dart';

import '../test/fake_camera.dart';
import '../test/fakes.dart';

/// Where the images go: the repository's tabcam_store/.
final String _store = '${Directory.current.parent.path}/tabcam_store';

/// A device the stores want screenshots of.
class _Device {
  const _Device(
    this.name,
    this.width,
    this.height,
    this.ratio,
    this.platform, {
    required this.top,
    required this.bottom,
    required this.dir,
    required this.prefix,
  });

  final String name;
  final int width, height;
  final double ratio;
  final TargetPlatform platform;

  /// The status bar's and the home indicator's heights, in logical pixels.
  final double top, bottom;

  /// The folder (under tabcam_store/) and the file names' prefix.
  final String dir, prefix;

  bool get ios => platform == TargetPlatform.iOS;
}

const _devices = [
  // Google Play: phone screenshots, 9:16.
  _Device(
    'Android phone',
    1080,
    1920,
    2.625,
    TargetPlatform.android,
    top: 24,
    bottom: 0,
    dir: 'android/en-US/images/phoneScreenshots',
    prefix: '',
  ),
  // App Store: the 6.9" iPhone (1320 x 2868), and the 13" iPad
  // (2064 x 2752): the app runs on iPads (TARGETED_DEVICE_FAMILY 1,2).
  _Device(
    'iPhone 6.9"',
    1320,
    2868,
    3,
    TargetPlatform.iOS,
    top: 62,
    bottom: 34,
    dir: 'ios/screenshots/en-US',
    prefix: 'iphone69_',
  ),
  _Device(
    'iPad 13"',
    2064,
    2752,
    2,
    TargetPlatform.iOS,
    top: 24,
    bottom: 20,
    dir: 'ios/screenshots/en-US',
    prefix: 'ipad13_',
  ),
];

/// Made-up riffs (never published songs), as the Text view shows them.
const _amberLane = '''
[Intro]
   Am          C           G
e|-----0-----|-----0-----|-----3-----|
B|---1---1---|---1---1---|---0---0---|
G|-2-------2-|-0-------0-|-0-------0-|
D|-----------|-----------|-----------|
A|-0---------|-3---------|-----------|
E|-----------|-----------|-3---------|

[Riff]
e|-------------------|-------------|
B|-------------------|-------------|
G|-------2-4-2-------|-------2-4-5-|
D|---2-4-------4-2---|---2-4-------|
A|-0-----------------|-0-----------|
E|-------------------|-------------|

[Verse]
   F           G           Em
e|-----1-----|-----3-----|-----0-----|
B|---1---1---|---0---0---|---0---0---|
G|-2-------2-|-0-------0-|-0-------0-|
D|-3---------|-----------|-2---------|
A|-----------|-2---------|-2---------|
E|-1---------|-3---------|-0---------|
''';

const _shuffle = '''
[Shuffle]
   A5                    D5
e|-----------------|-----------------|
B|-----------------|-----------------|
G|-----------------|-----------------|
D|-2--2--4--4--2--2|-----------------|
A|-0--0--0--0--0--0|-2--2--4--4--2--2|
E|-----------------|-0--0--0--0--0--0|
''';

const _etude = '''
[Etude No. 2]
   C                     G/B
e|-------0-------0---|-------0-------0---|
B|-----1---1---1---1-|-----0---0---0---0-|
G|---0-------0-------|---0-------0-------|
D|-------------------|-------------------|
A|-3-----------------|-2-----------------|
E|-------------------|-------------------|
''';

const _drill = '''
[Drill]
e|---------------|---------------|
B|---------------|---------------|
G|---------------|---------------|
D|-5-5-7-7-5-5---|-7-7-9-9-7-7---|
A|-3-3-5-5-3-3---|-5-5-7-7-5-5---|
E|---------------|---------------|
''';

const _warmup = '''
[Warm-up]
e|-----------------|---------1-2-3-4-|
B|-----------------|-1-2-3-4---------|
G|---------1-2-3-4-|-----------------|
D|-1-2-3-4---------|-----------------|
A|-----------------|-----------------|
E|-----------------|-----------------|
''';

const _arpeggio = '''
[Arpeggios]
   G                   C
e|-------3-------|-------0-------|
B|-----0---0-----|-----1---1-----|
G|---0-------0---|---0-------0---|
D|---------------|-2-----------2-|
A|---------------|-3-------------|
E|-3-------------|---------------|
''';

const _hammer = '''
[Hammer-ons]
e|-0h2-0h3-0h5---|-0h2-0h3-0h5---|
B|---------------|---------------|
G|-0h2-0h4-------|-0h2-0h4-------|
D|---------------|---------------|
A|---------------|---------------|
E|---------------|---------------|
''';

const _changes = '''
[Changes]
   G          C          D
e|-3---3---|-0---0---|-2---2---|
B|-0---0---|-1---1---|-3---3---|
G|-0---0---|-0---0---|-2---2---|
D|-0---0---|-2---2---|-0---0---|
A|-2---2---|-3---3---|---------|
E|-3---3---|---------|---------|
''';

const _mute = '''
[Groove]  P.M. throughout
e|---------------------|
B|---------------------|
G|---------------------|
D|---------------------|
A|-------3-3---5-5-3---|
E|-0-0-0-------------0-|
''';

const _slide = '''
[Lick]
e|-----------------------|
B|-----------5-8b10r8-5--|
G|-----5/7-----------7---|
D|-7-------------------7-|
A|-----------------------|
E|-----------------------|
''';

void main() {
  late FakeStillCamera camera;

  setUpAll(_loadFonts);
  setUp(() {
    CameraPlatform.instance = camera = FakeStillCamera();
    // Cam watches for nods with ML Kit, which isn't in tests: no faces.
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(
          const MethodChannel('google_mlkit_face_detector'),
          (call) async => null,
        );
  });

  testWidgets('store graphics: Play icon and feature graphic', (tester) async {
    final icon = await tester.runAsync(() async {
      final bytes = await File('assets/icon/icon.png').readAsBytes();
      final codec = await ui.instantiateImageCodec(bytes);
      return (await codec.getNextFrame()).image;
    });
    // The app icon at 512 x 512, as a 32-bit PNG (RGBA), as Play asks.
    await tester.runAsync(() async {
      final recorder = ui.PictureRecorder();
      Canvas(recorder).drawImageRect(
        icon!,
        const Rect.fromLTWH(0, 0, 1024, 1024),
        const Rect.fromLTWH(0, 0, 512, 512),
        Paint()..filterQuality = FilterQuality.high,
      );
      final image = await recorder.endRecording().toImage(512, 512);
      final png = await image.toByteData(format: ui.ImageByteFormat.png);
      await File('$_store/android/en-US/images/icon.png')
          .writeAsBytes(png!.buffer.asUint8List());
    });

    // The feature graphic, 1024 x 500, no alpha.
    tester.view
      ..physicalSize = const Size(1024, 500)
      ..devicePixelRatio = 1;
    addTearDown(tester.view.reset);
    final frame = GlobalKey();
    await tester.pumpWidget(
      RepaintBoundary(
        key: frame,
        child: _FeatureGraphic(icon: icon!),
      ),
    );
    await tester.pump();
    await _writeRgb(
      tester,
      tester.renderObject(find.byKey(frame)) as RenderRepaintBoundary,
      1,
      File('$_store/android/en-US/images/featureGraphic.png'),
    );
  });

  for (final device in _devices) {
    testWidgets('store screenshots: ${device.name}', (tester) async {
      final shots = _Shots(tester, device);
      await shots.start();
      try {
        // 1. The Text view: a page read into a text tab, ready to edit.
        await shots.home();
        await shots.openCapture('Amber Lane');
        await tester.tap(find.byKey(const Key('text')));
        await shots.settle();
        await shots.save(1);

        // 2. The scanned page, with the Tab filter (black on white).
        await tester.tap(find.byKey(const Key('files')));
        await shots.settle();
        await tester.tap(find.text('Page 1').first);
        await shots.settle(rounds: 30);
        await shots.save(2);

        // 3. Home: the grid of captures, newest first.
        await shots.home();
        await shots.save(3);

        // 4. Capture: Scan, or add a document, photos and videos, files
        // or a link.
        await tester.tap(find.text('Capture').last);
        await shots.settle();
        await shots.save(4);

        // 5. Cam: playing along, the tab under the camera one neckline
        // at a time.
        await shots.home();
        await shots.openCapture('Amber Lane');
        await tester.tap(find.byKey(const Key('cam')));
        await shots.settle(rounds: 20);
        await shots.save(5);

        // 6. Share with people, by email.
        await shots.home();
        await shots.openCapture('Amber Lane');
        await tester.tap(find.byTooltip('Share with people'));
        await shots.settle(rounds: 20);
        await shots.save(6);
      } finally {
        await shots.stop();
      }
      expect(camera.opened, isNotEmpty);
    });
  }
}

/// One device's screenshots: the app, its fakes, and the captures.
class _Shots {
  _Shots(this.tester, this.device);

  final WidgetTester tester;
  final _Device device;
  final _frame = GlobalKey();
  late final Library library;
  late final CloudSync sync;
  late final FakeShareApi _shares;
  DateTime _now = DateTime(2026, 10, 12, 18);

  Future<void> start() async {
    debugDefaultTargetPlatformOverride = device.platform;
    tester.view
      ..physicalSize = Size(device.width.toDouble(), device.height.toDouble())
      ..devicePixelRatio = device.ratio
      ..padding = FakeViewPadding(
        top: device.top * device.ratio,
        bottom: device.bottom * device.ratio,
      )
      ..viewPadding = FakeViewPadding(
        top: device.top * device.ratio,
        bottom: device.bottom * device.ratio,
      );
    library = Library(PlatformEventStore(), () => _now, (_) async => null);
    final auth = FakeAuth()
      ..signInWith(const AuthUser(id: 'ana', email: 'ana@example.com'));
    final shares = _shares = FakeShareApi(
      {},
      email: 'ana@example.com',
      identity: 'us-east-1:me',
    );
    sync = CloudSync(
      library: library,
      auth: auth,
      bucket: FakeBucket(),
      credentials: FakeCredentials(),
      shares: shares,
      period: const Duration(days: 1),
    );
    await tester.runAsync(() async {
      await library.load();
      sync.start();
      await Future<void>.delayed(const Duration(milliseconds: 100));
      await _captures();
      await Future<void>.delayed(const Duration(milliseconds: 100));
    });
    await tester.pumpWidget(
      RepaintBoundary(
        key: _frame,
        child: Directionality(
          textDirection: TextDirection.ltr,
          child: Stack(
            children: [
              TabCamApp(library: library, auth: auth, sync: sync),
              IgnorePointer(child: _StatusBar(device: device)),
            ],
          ),
        ),
      ),
    );
    await settle();
  }

  Future<void> stop() async {
    sync.dispose();
    debugDefaultTargetPlatformOverride = null;
    tester.view.reset();
  }

  /// The made-up captures, oldest first (Home shows the newest first).
  Future<void> _captures() async {
    Future<void> add(
      String title,
      String tab, {
      required int daysAgo,
      bool lesson = false,
      List<String> sharedWith = const [],
    }) async {
      _now = DateTime(2026, 10, 12, 18).subtract(Duration(days: daysAgo));
      final photo = await _pagePhoto(title, tab);
      var event = await library.create([photo]);
      event = await library.update(
        event.copyWith(title: title, tabText: tab.trim(), tabTextAuto: true),
      );
      if (lesson) {
        event = await library.addLink(
          event,
          Uri.parse('https://example.com/lessons/amber-lane'),
          title: 'Lesson: $title',
        );
      }
      for (final (i, email) in sharedWith.indexed) {
        (_shares.grantsBy['us-east-1:me/${event.id}'] ??= {})[email] = i == 0
            ? ShareRole.edit
            : ShareRole.read;
      }
    }

    await add('Palm-Mute Groove', _mute, daysAgo: 16);
    await add('Chord Changes: G C D', _changes, daysAgo: 14);
    await add('Hammer-on Practice', _hammer, daysAgo: 12);
    await add('Arpeggio Study in G', _arpeggio, daysAgo: 10);
    await add('Slide Lick in E', _slide, daysAgo: 9);
    await add('Power Chord Drill', _drill, daysAgo: 7);
    await add('Fingerpicking Etude No. 2', _etude, daysAgo: 5);
    await add('Blues Shuffle in A', _shuffle, daysAgo: 3);
    await add('Fretboard Warm-up', _warmup, daysAgo: 2);
    await add(
      'Amber Lane',
      _amberLane,
      daysAgo: 0,
      lesson: true,
      sharedWith: ['sam@example.com', 'lee@example.com'],
    );
  }

  /// Back to Home, nothing open.
  Future<void> home() async {
    final navigator = tester.state<NavigatorState>(
      find.byType(Navigator).first,
    );
    navigator.popUntil((route) => route.isFirst);
    await settle();
    final bar = find.byType(NavigationBar);
    await tester.tap(find.descendant(of: bar, matching: find.text('Home')));
    await settle();
  }

  Future<void> openCapture(String title) async {
    await tester.tap(find.text(title).first);
    await settle();
  }

  /// Lets pictures decode and filters run (real time), and frames show.
  Future<void> settle({int rounds = 10}) async {
    for (var i = 0; i < rounds; i++) {
      await tester.runAsync(
        () => Future<void>.delayed(const Duration(milliseconds: 60)),
      );
      await tester.pump(const Duration(milliseconds: 100));
    }
    await tester.runAsync(() async {
      for (final element in find.byType(Image).evaluate()) {
        final image = element.widget as Image;
        await precacheImage(
          image.image,
          element,
        ).timeout(const Duration(seconds: 5), onTimeout: () {});
      }
    });
    for (var i = 0; i < 5; i++) {
      await tester.pump(const Duration(milliseconds: 100));
    }
  }

  /// Writes the screen as `<prefix><n>.png`: RGB, no alpha, as both stores
  /// take them.
  Future<void> save(int n) async {
    await _writeRgb(
      tester,
      tester.renderObject(find.byKey(_frame)) as RenderRepaintBoundary,
      device.ratio,
      File('$_store/${device.dir}/${device.prefix}$n.png'),
    );
  }
}

/// Writes what [boundary] shows to [file] as an RGB PNG (no alpha, as both
/// stores take screenshots and Play its feature graphic).
Future<void> _writeRgb(
  WidgetTester tester,
  RenderRepaintBoundary boundary,
  double ratio,
  File file,
) async {
  await tester.runAsync(() async {
    final image = await boundary.toImage(pixelRatio: ratio);
    final data = await image.toByteData(format: ui.ImageByteFormat.rawRgba);
    final rgba = data!.buffer.asUint8List();
    final rgb = Uint8List(image.width * image.height * 3);
    for (var i = 0, j = 0; i < rgba.length; i += 4, j += 3) {
      rgb[j] = rgba[i];
      rgb[j + 1] = rgba[i + 1];
      rgb[j + 2] = rgba[i + 2];
    }
    final png = img.encodePng(
      img.Image.fromBytes(
        width: image.width,
        height: image.height,
        bytes: rgb.buffer,
        numChannels: 3,
      ),
      level: 6,
    );
    await file.parent.create(recursive: true);
    await file.writeAsBytes(png);
  });
}

/// Play's feature graphic: the icon, the name and what it does, on the
/// icon's dark background, with a scanned page of a made-up riff.
class _FeatureGraphic extends StatelessWidget {
  const _FeatureGraphic({required this.icon});

  final ui.Image icon;

  static const _background = Color(0xFF1E1A15);
  static const _cream = Color(0xFFFBF7EF);
  static const _amber = Color(0xFFE0A030);

  @override
  Widget build(BuildContext context) => Directionality(
    textDirection: TextDirection.ltr,
    child: ColoredBox(
      color: _background,
      child: Stack(
        children: [
          // A page of tab, tilted, running off the right edge.
          Positioned(
            right: -60,
            top: 40,
            child: Transform.rotate(
              angle: -0.08,
              child: Container(
                width: 420,
                padding: const EdgeInsets.fromLTRB(28, 24, 28, 24),
                decoration: BoxDecoration(
                  color: _cream,
                  borderRadius: BorderRadius.circular(6),
                  boxShadow: const [
                    BoxShadow(color: Colors.black54, blurRadius: 30),
                  ],
                ),
                child: Text(
                  _amberLane.trim().split('\n').take(15).join('\n'),
                  softWrap: false,
                  overflow: TextOverflow.clip,
                  style: const TextStyle(
                    fontFamily: 'RobotoMono',
                    fontSize: 15.5,
                    height: 1.3,
                    color: Color(0xFF26231F),
                  ),
                ),
              ),
            ),
          ),
          Positioned(
            left: 64,
            top: 0,
            bottom: 0,
            width: 520,
            child: Column(
              mainAxisAlignment: MainAxisAlignment.center,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                ClipRRect(
                  borderRadius: BorderRadius.circular(36),
                  child: RawImage(image: icon, width: 160, height: 160),
                ),
                const SizedBox(height: 28),
                const Text(
                  'TabCam',
                  style: TextStyle(
                    fontFamily: 'Roboto',
                    fontSize: 72,
                    fontWeight: FontWeight.w700,
                    color: _cream,
                    height: 1,
                  ),
                ),
                const SizedBox(height: 14),
                const Text(
                  'Scan guitar tabs into\neditable text',
                  style: TextStyle(
                    fontFamily: 'Roboto',
                    fontSize: 32,
                    fontWeight: FontWeight.w500,
                    color: _amber,
                    height: 1.2,
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    ),
  );
}

/// The phone's status bar: the time, the signal, Wi-Fi and the battery.
class _StatusBar extends StatelessWidget {
  const _StatusBar({required this.device});

  final _Device device;

  @override
  Widget build(BuildContext context) {
    final style = TextStyle(
      fontFamily: device.ios ? 'CupertinoSystemText' : 'Roboto',
      color: Colors.white,
      fontSize: 15,
      fontWeight: FontWeight.w600,
    );
    final ios = device.ios;
    return Align(
      alignment: Alignment.topCenter,
      child: SizedBox(
        height: device.top,
        child: Padding(
          padding: EdgeInsets.symmetric(horizontal: ios ? 36 : 16),
          child: Row(
            children: [
              Text(ios ? '9:41' : '12:30', style: style),
              const Spacer(),
              for (final icon in [
                Icons.signal_cellular_alt,
                Icons.wifi,
                Icons.battery_full,
              ])
                Padding(
                  padding: const EdgeInsets.only(left: 4),
                  child: Icon(icon, color: Colors.white, size: 17),
                ),
            ],
          ),
        ),
      ),
    );
  }
}

/// The camera, faked, with a picture in its preview: a guitar's neck.
class FakeStillCamera extends FakeCameraPlatform {
  @override
  Widget buildPreview(int cameraId) =>
      const CustomPaint(painter: _NeckPainter(), child: SizedBox.expand());
}

/// A guitar's neck, seen by the camera: a rosewood fretboard across the
/// picture, frets, dots and six strings, in a dim room.
class _NeckPainter extends CustomPainter {
  const _NeckPainter();

  @override
  void paint(Canvas canvas, Size size) {
    final w = size.width, h = size.height;
    canvas.clipRect(Offset.zero & size);
    canvas.drawRect(
      Offset.zero & size,
      Paint()
        ..shader = ui.Gradient.radial(
          Offset(w * 0.6, h * 0.4),
          math.max(w, h),
          [const Color(0xFF4A3B2C), const Color(0xFF120E0A)],
        ),
    );
    canvas.save();
    canvas.translate(w / 2, h / 2);
    canvas.rotate(-0.42);
    final length = math.sqrt(w * w + h * h) * 1.2;
    final width = math.min(w, h) * 0.42;
    final board = Rect.fromCenter(
      center: Offset.zero,
      width: length,
      height: width,
    );
    canvas.drawRect(board.inflate(6), Paint()..color = const Color(0xFF1A120C));
    canvas.drawRect(
      board,
      Paint()
        ..shader = ui.Gradient.linear(
          board.topCenter,
          board.bottomCenter,
          [
            const Color(0xFF5A3420),
            const Color(0xFF3B2214),
            const Color(0xFF52301D),
          ],
          [0, 0.5, 1],
        ),
    );
    // Frets, closer together up the neck; a dot between some.
    var x = -length / 2 + 20;
    var gap = width * 1.1;
    var fret = 0;
    final fretPaint = Paint()
      ..shader = ui.Gradient.linear(
        Offset(0, -width / 2),
        Offset(0, width / 2),
        [const Color(0xFFE8E4DA), const Color(0xFF8C8778)],
      );
    while (x < length / 2) {
      canvas.drawRect(
        Rect.fromLTWH(x, -width / 2, width * 0.035, width),
        fretPaint,
      );
      fret++;
      if ({3, 5, 7, 9}.contains(fret % 12)) {
        canvas.drawCircle(
          Offset(x + gap * 0.94 / 2, 0),
          width * 0.05,
          Paint()..color = const Color(0xFFEDE6D3),
        );
      }
      x += gap;
      gap *= 0.944;
    }
    // Strings: thicker towards the low E.
    for (var s = 0; s < 6; s++) {
      final y = -width / 2 + width * (s + 0.5) / 6;
      final thick = 1.2 + s * 0.6;
      canvas.drawRect(
        Rect.fromLTWH(-length / 2, y - thick / 2, length, thick),
        Paint()
          ..color = s < 3 ? const Color(0xFFDADADA) : const Color(0xFFC9A86A),
      );
    }
    canvas.restore();
  }

  @override
  bool shouldRepaint(_NeckPainter oldDelegate) => false;
}

/// A photo of a printed page of [tab], titled [title]: off-white paper,
/// lit unevenly (brighter at the top left), as a phone takes it.
Future<Uint8List> _pagePhoto(String title, String tab) async {
  const w = 1240, h = 1754;
  final recorder = ui.PictureRecorder();
  final canvas = Canvas(recorder);
  canvas.drawRect(
    const Rect.fromLTWH(0, 0, 1240, 1754),
    Paint()
      ..shader = ui.Gradient.radial(const Offset(200, 150), 2000, [
        const Color(0xFFF4EFE4),
        const Color(0xFFB9B0A0),
      ]),
  );
  void text(String s, Offset at, TextStyle style) {
    final builder = ui.ParagraphBuilder(ui.ParagraphStyle())
      ..pushStyle(style.getTextStyle())
      ..addText(s);
    final paragraph = builder.build()
      ..layout(const ui.ParagraphConstraints(width: 1200));
    canvas.drawParagraph(paragraph, at);
  }

  const ink = Color(0xFF26231F);
  text(
    title,
    const Offset(90, 100),
    const TextStyle(
      fontFamily: 'Roboto',
      fontSize: 64,
      fontWeight: FontWeight.w700,
      color: ink,
    ),
  );
  text(
    'Standard tuning  ·  92 bpm',
    const Offset(90, 180),
    const TextStyle(fontFamily: 'Roboto', fontSize: 28, color: ink),
  );
  text(
    tab.trim(),
    const Offset(90, 270),
    const TextStyle(
      fontFamily: 'RobotoMono',
      fontSize: 40,
      height: 1.35,
      color: ink,
    ),
  );
  final picture = recorder.endRecording();
  final image = await picture.toImage(w, h);
  final data = await image.toByteData(format: ui.ImageByteFormat.png);
  return data!.buffer.asUint8List();
}

/// Real fonts, not the test's boxes: Roboto and the Material icons from
/// the Flutter SDK, Roboto Mono from the app's assets; on iOS, San
/// Francisco from the Mac running the tests.
Future<void> _loadFonts() async {
  var dir = File(Platform.resolvedExecutable).parent;
  while (!Directory('${dir.path}/bin/cache/artifacts/material_fonts')
      .existsSync()) {
    if (dir.parent.path == dir.path) {
      throw StateError('Flutter SDK not found from $dir');
    }
    dir = dir.parent;
  }
  final fonts = '${dir.path}/bin/cache/artifacts/material_fonts';
  Future<ByteData> file(String path) async =>
      ByteData.sublistView(await File(path).readAsBytes());

  final roboto = FontLoader('Roboto');
  for (final weight in [
    'Thin',
    'Light',
    'Regular',
    'Medium',
    'Bold',
    'Black',
  ]) {
    roboto.addFont(file('$fonts/Roboto-$weight.ttf'));
  }
  await roboto.load();
  await (FontLoader(
    'MaterialIcons',
  )..addFont(file('$fonts/MaterialIcons-Regular.otf'))).load();
  // San Francisco, as iOS shows Material text (a variable font: its
  // weights come from it).
  const sf = '/System/Library/Fonts/SFNS.ttf';
  if (File(sf).existsSync()) {
    for (final family in ['CupertinoSystemText', 'CupertinoSystemDisplay']) {
      await (FontLoader(family)..addFont(file(sf))).load();
    }
  }
  await (FontLoader(
    'RobotoMono',
  )..addFont(rootBundle.load('assets/fonts/RobotoMono.ttf'))).load();
}
