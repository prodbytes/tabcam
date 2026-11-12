import 'dart:math';
import 'dart:ui' as ui;

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter/scheduler.dart';
import 'package:video_player/video_player.dart';

import '../screens/mono_font.dart';
import 'render_plan.dart';

/// How wide a band is drawn, in pixels; the video scales it to its own
/// width.
const int bandWidth = 1280;

/// A layer's look drawn once ([picture], [size] pixels): painted, scaled,
/// over the preview ([EditLayers]), and made a PNG for Download
/// ([layerImages]), so both are the same drawing.
class LayerPicture {
  LayerPicture(this.picture, this.size);

  final ui.Picture picture;
  final Size size;

  /// It as a PNG.
  Future<Uint8List> png() async {
    final image = await picture.toImage(
      size.width.round(),
      size.height.round(),
    );
    try {
      final png = await image.toByteData(format: ui.ImageByteFormat.png);
      return png!.buffer.asUint8List();
    } finally {
      image.dispose();
    }
  }

  void dispose() => picture.dispose();
}

/// [look] drawn ([LayerPicture]).
LayerPicture layerPicture(LayerLook look) => switch (look) {
  BandLook(:final line) => bandPicture(line),
};

/// [neckline] drawn as a band to put along the bottom of a take: white
/// monospaced text on a dark, see-through background, as wide as
/// [width], its text as big as fits (a long staff gets smaller).
LayerPicture bandPicture(String neckline, {int width = bandWidth}) {
  final pad = width / 64;
  TextPainter painter(double size) => TextPainter(
    text: TextSpan(
      text: neckline,
      style: TextStyle(
        fontFamily: monoFont,
        fontSize: size,
        height: 1.2,
        color: Colors.white,
      ),
    ),
    textDirection: TextDirection.ltr,
  )..layout();
  // Measured at 100, then sized to fit (never bigger than width / 48, so
  // a six-string staff takes about a third of a landscape take).
  final probe = painter(100);
  final fit = probe.width <= 0 ? 100.0 : 100 * (width - 2 * pad) / probe.width;
  probe.dispose();
  final text = painter(min(fit, width / 48));
  final height = (text.height + 2 * pad).ceil();
  final recorder = ui.PictureRecorder();
  final canvas = Canvas(recorder);
  canvas.drawRect(
    Rect.fromLTWH(0, 0, width.toDouble(), height.toDouble()),
    Paint()..color = const Color(0xB3000000),
  );
  text.paint(canvas, Offset((width - text.width) / 2, pad));
  text.dispose();
  return LayerPicture(
    recorder.endRecording(),
    Size(width.toDouble(), height.toDouble()),
  );
}

/// [neckline]'s band ([bandPicture]) as a PNG.
Future<Uint8List> renderBand(String neckline, {int width = bandWidth}) async {
  final band = bandPicture(neckline, width: width);
  try {
    return await band.png();
  } finally {
    band.dispose();
  }
}

/// The images of [plan]'s layers, for Download's renderers: one PNG per
/// look, as [RenderPlan.looks] orders them.
Future<List<Uint8List>> layerImages(RenderPlan plan) async => [
  for (final look in plan.looks) await _png(look),
];

Future<Uint8List> _png(LayerLook look) async {
  final picture = layerPicture(look);
  try {
    return await picture.png();
  } finally {
    picture.dispose();
  }
}

/// The layers' pictures, each look drawn once while it's used.
class LayerPictures {
  final _pictures = <LayerLook, LayerPicture>{};

  LayerPicture of(LayerLook look) => _pictures[look] ??= layerPicture(look);

  /// Lets go of those [looks] no longer has.
  void keepOnly(Iterable<LayerLook> looks) {
    final kept = looks.toSet();
    _pictures.removeWhere((look, picture) {
      if (kept.contains(look)) return false;
      picture.dispose();
      return true;
    });
  }

  void dispose() {
    for (final picture in _pictures.values) {
      picture.dispose();
    }
    _pictures.clear();
  }
}

/// Paints [layers] as they are at [at] (in the output: 0 is the kept
/// part's start) over a frame its size, as Download draws them: each
/// where its anchor puts it ([PlanLayer.rectIn]), as opaque as it is
/// then ([PlanLayer.alphaAt]).
class EditLayersPainter extends CustomPainter {
  EditLayersPainter(this.layers, this.at, this.pictures) : super(repaint: at);

  final List<PlanLayer> layers;
  final ValueListenable<Duration> at;
  final LayerPictures pictures;

  @override
  void paint(Canvas canvas, Size size) {
    paintLayers(canvas, size, layers, at.value, pictures);
  }

  @override
  bool shouldRepaint(EditLayersPainter old) =>
      !listEquals(old.layers, layers) || old.at != at;
}

/// [layers] at [at] painted on [canvas], over a frame [size] big.
void paintLayers(
  Canvas canvas,
  Size size,
  List<PlanLayer> layers,
  Duration at,
  LayerPictures pictures,
) {
  for (final layer in layers) {
    final alpha = layer.alphaAt(at);
    if (alpha <= 0) continue;
    final picture = pictures.of(layer.look);
    final rect = layer.rectIn(size, picture.size);
    if (rect.isEmpty) continue;
    if (alpha < 1) {
      canvas.saveLayer(rect, Paint()..color = Color.fromRGBO(0, 0, 0, alpha));
    } else {
      canvas.save();
    }
    canvas.translate(rect.left, rect.top);
    canvas.scale(
      rect.width / picture.size.width,
      rect.height / picture.size.height,
    );
    canvas.drawPicture(picture.picture);
    canvas.restore();
  }
}

/// [layers] over [video], as Download draws them: fill the box the video
/// is shown in (its shape), and let taps through. They follow where the
/// video is ([start], the kept part's start in it, being 0 in the
/// output): between the player's reports (every tenth of a second or
/// so), its place is carried on by the frame clock while it plays, so
/// fades and bands change smoothly; on a seek or a pause it's where the
/// player says. Nothing runs while it's paused.
class EditLayers extends StatefulWidget {
  const EditLayers({
    super.key,
    required this.video,
    required this.layers,
    this.start = Duration.zero,
  });

  final VideoPlayerController video;
  final List<PlanLayer> layers;
  final Duration start;

  @override
  State<EditLayers> createState() => _EditLayersState();
}

class _EditLayersState extends State<EditLayers>
    with SingleTickerProviderStateMixin {
  final _pictures = LayerPictures();
  final _at = ValueNotifier(Duration.zero);
  late final Ticker _ticker = createTicker(_onTick);

  /// Where the player last said it was, and the frame clock then.
  Duration _reported = Duration.zero;
  Duration _reportedAt = Duration.zero;
  Duration _now = Duration.zero;

  /// How far past the player's last report it's carried on, at most (a
  /// player that stops reporting doesn't run away).
  static const _ahead = Duration(milliseconds: 400);

  @override
  void initState() {
    super.initState();
    widget.video.addListener(_onVideo);
    _onVideo();
  }

  @override
  void didUpdateWidget(EditLayers old) {
    super.didUpdateWidget(old);
    if (!identical(old.video, widget.video)) {
      old.video.removeListener(_onVideo);
      widget.video.addListener(_onVideo);
    }
    if (!listEquals(old.layers, widget.layers)) {
      _pictures.keepOnly(widget.layers.map((l) => l.look));
    }
    if (old.start != widget.start) _show(_reported);
  }

  /// The player changed: a new place (its report, or a seek) is the
  /// frame clock's new start. Anything else it says (its volume, its
  /// buffering) leaves the clock carrying on from the last place it
  /// reported, else the layers would fall back to it on each.
  void _onVideo() {
    final value = widget.video.value;
    final moved = value.position != _reported;
    if (moved) {
      _reported = value.position;
      _reportedAt = _now;
    }
    if (value.isPlaying && !_ticker.isActive) {
      _now = Duration.zero;
      _reportedAt = Duration.zero;
      _ticker.start();
    } else if (!value.isPlaying && _ticker.isActive) {
      _ticker.stop();
    }
    // Playing, the next frame shows it; paused, where the player says.
    if (moved || !_ticker.isActive) _show(_reported);
  }

  void _onTick(Duration elapsed) {
    _now = elapsed;
    final value = widget.video.value;
    var since = elapsed - _reportedAt;
    if (since > _ahead) since = _ahead;
    _show(_reported + since * value.playbackSpeed);
  }

  /// Shows the layers as they are at [position] in the video.
  void _show(Duration position) => _at.value = position - widget.start;

  @override
  void dispose() {
    widget.video.removeListener(_onVideo);
    _ticker.dispose();
    _at.dispose();
    _pictures.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => IgnorePointer(
    child: CustomPaint(
      key: const Key('edit-layers'),
      size: Size.infinite,
      painter: EditLayersPainter(widget.layers, _at, _pictures),
    ),
  );
}
