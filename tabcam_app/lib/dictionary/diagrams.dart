/// The dictionary's pictures: a chord diagram (a voicing on the fretboard
/// seen from the front, as chord books draw it) and a scale's fretboard
/// (the neck seen from above, every note of the scale on it).
library;

import 'package:flutter/material.dart';

import '../l10n/language.dart';
import 'music_theory.dart';
import 'voicings.dart';

/// One voicing of [chord], strings left (low E) to right, frets down
/// from the nut (or from the fret labelled at the left), its root notes
/// in the theme's primary colour, each string's note under it.
class ChordDiagram extends StatelessWidget {
  const ChordDiagram({
    super.key,
    required this.chord,
    required this.voicing,
    this.width = 96,
  });

  final Chord chord;
  final Voicing voicing;
  final double width;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final l10n = context.l10n;
    final base = voicing.baseFret;
    return Column(
      key: const Key('chord-diagram'),
      mainAxisSize: MainAxisSize.min,
      children: [
        CustomPaint(
          size: Size(width, width * 1.3),
          painter: _ChordPainter(
            chord: chord,
            voicing: voicing,
            fretLabel: base > 1 ? l10n.dictionaryFret(base) : null,
            line: scheme.onSurface,
            muted: scheme.onSurfaceVariant,
            root: scheme.primary,
            onRoot: scheme.onPrimary,
          ),
        ),
        const SizedBox(height: 2),
        Text(
          voicing.label,
          style: Theme.of(context).textTheme.labelSmall?.copyWith(
            color: scheme.onSurfaceVariant,
            fontFeatures: const [FontFeature.tabularFigures()],
          ),
        ),
      ],
    );
  }
}

class _ChordPainter extends CustomPainter {
  const _ChordPainter({
    required this.chord,
    required this.voicing,
    required this.fretLabel,
    required this.line,
    required this.muted,
    required this.root,
    required this.onRoot,
  });

  final Chord chord;
  final Voicing voicing;
  final String? fretLabel;
  final Color line;
  final Color muted;
  final Color root;
  final Color onRoot;

  static const _fretsShown = 5;

  @override
  void paint(Canvas canvas, Size size) {
    final left = size.width * 0.24;
    final right = size.width * 0.95;
    final top = size.height * 0.14;
    final bottom = size.height * 0.84;
    final gapX = (right - left) / 5;
    final gapY = (bottom - top) / _fretsShown;
    final base = voicing.baseFret;
    final nut = base == 1;
    final stroke = Paint()
      ..color = line
      ..strokeWidth = 1
      ..style = PaintingStyle.stroke;

    // The nut, or the first fret line, then the frets.
    for (var f = 0; f <= _fretsShown; f++) {
      final y = top + f * gapY;
      canvas.drawLine(
        Offset(left, y),
        Offset(right, y),
        f == 0 && nut
            ? (Paint()
                ..color = line
                ..strokeWidth = 3.5)
            : stroke,
      );
    }
    for (var s = 0; s < 6; s++) {
      final x = left + s * gapX;
      canvas.drawLine(Offset(x, top), Offset(x, bottom), stroke);
    }
    if (fretLabel case final label?) {
      _text(
        canvas,
        label,
        Offset(left - gapX * 0.3 - 3, top + gapY / 2),
        color: muted,
        size: size.width * 0.1,
        align: TextAlign.right,
      );
    }

    // A barre: a bar from its first string to the last.
    final frets = voicing.frets;
    if (voicing.barreFrom case final from?) {
      final y = top + (voicing.lowestFret - base + 0.5) * gapY;
      final r = gapX * 0.3;
      canvas.drawRRect(
        RRect.fromLTRBR(
          left + from * gapX - r,
          y - r,
          left + 5 * gapX + r,
          y + r,
          Radius.circular(r),
        ),
        Paint()..color = line,
      );
    }

    // Each string: a mark above the nut (open, not played) or a dot.
    final markSize = size.width * 0.11;
    for (var s = 0; s < 6; s++) {
      final x = left + s * gapX;
      final f = frets[s];
      final pc = f == null ? null : (standardTuning[s] + f) % 12;
      final isRoot = pc == chord.root.pitchClass;
      if (f == null) {
        _text(
          canvas,
          '×',
          Offset(x, top - markSize * 0.75),
          color: muted,
          size: markSize * 1.2,
        );
      } else if (f == 0) {
        canvas.drawCircle(
          Offset(x, top - markSize * 0.75),
          gapX * 0.22,
          Paint()
            ..color = isRoot ? root : line
            ..style = PaintingStyle.stroke
            ..strokeWidth = isRoot ? 2 : 1.2,
        );
      } else {
        final y = top + (f - base + 0.5) * gapY;
        final r = gapX * 0.34;
        canvas.drawCircle(
          Offset(x, y),
          r,
          Paint()..color = isRoot ? root : line,
        );
      }
      // The note under the string.
      if (pc != null) {
        _text(
          canvas,
          chord.spell(pc)?.name ?? Note.of(pc).name,
          Offset(x, bottom + (size.height - bottom) / 2),
          color: isRoot ? root : muted,
          size: size.width * 0.1,
          bold: isRoot,
        );
      }
    }
  }

  void _text(
    Canvas canvas,
    String text,
    Offset center, {
    required Color color,
    required double size,
    bool bold = false,
    TextAlign align = TextAlign.center,
  }) {
    final painter = TextPainter(
      text: TextSpan(
        text: text,
        style: TextStyle(
          color: color,
          fontSize: size,
          fontWeight: bold ? FontWeight.w700 : FontWeight.w500,
        ),
      ),
      textDirection: TextDirection.ltr,
    )..layout();
    final dx = switch (align) {
      TextAlign.right => center.dx - painter.width,
      _ => center.dx - painter.width / 2,
    };
    painter.paint(canvas, Offset(dx, center.dy - painter.height / 2));
  }

  @override
  bool shouldRepaint(_ChordPainter old) =>
      old.voicing.frets != voicing.frets ||
      old.chord != chord ||
      old.line != line ||
      old.root != root;
}

/// The neck up to the twelfth fret, high E at the top, with every note of
/// [scale] on it (the roots in the theme's primary colour), the open
/// strings before the nut and the fret numbers under it.
class ScaleFretboard extends StatelessWidget {
  const ScaleFretboard({super.key, required this.scale});

  final Scale scale;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return LayoutBuilder(
      key: const Key('scale-fretboard'),
      builder: (context, constraints) {
        final width = constraints.maxWidth.isFinite
            ? constraints.maxWidth
            : 360.0;
        return CustomPaint(
          size: Size(width, width * 0.42),
          painter: _FretboardPainter(
            scale: scale,
            line: scheme.onSurface,
            muted: scheme.onSurfaceVariant,
            note: scheme.surfaceContainerHighest,
            onNote: scheme.onSurface,
            root: scheme.primary,
            onRoot: scheme.onPrimary,
          ),
        );
      },
    );
  }
}

class _FretboardPainter extends CustomPainter {
  const _FretboardPainter({
    required this.scale,
    required this.line,
    required this.muted,
    required this.note,
    required this.onNote,
    required this.root,
    required this.onRoot,
  });

  final Scale scale;
  final Color line;
  final Color muted;
  final Color note;
  final Color onNote;
  final Color root;
  final Color onRoot;

  static const _frets = 12;

  @override
  void paint(Canvas canvas, Size size) {
    // Column 0 is the open strings, before the nut.
    final columns = _frets + 1;
    final gapX = size.width / columns;
    final top = size.height * 0.08;
    final bottom = size.height * 0.82;
    final gapY = (bottom - top) / 5;
    final nutX = gapX;
    final stroke = Paint()
      ..color = line
      ..strokeWidth = 1
      ..style = PaintingStyle.stroke;

    canvas.drawLine(
      Offset(nutX, top),
      Offset(nutX, bottom),
      Paint()
        ..color = line
        ..strokeWidth = 3,
    );
    for (var f = 2; f <= _frets + 1; f++) {
      final x = f * gapX;
      canvas.drawLine(Offset(x, top), Offset(x, bottom), stroke);
    }
    // Fret markers, under the strings.
    for (final f in const [3, 5, 7, 9, 12]) {
      final x = (f + 0.5) * gapX;
      final marker = Paint()..color = muted.withValues(alpha: 0.25);
      if (f == 12) {
        canvas.drawCircle(Offset(x, top + gapY * 1.5), gapY * 0.18, marker);
        canvas.drawCircle(Offset(x, top + gapY * 3.5), gapY * 0.18, marker);
      } else {
        canvas.drawCircle(Offset(x, (top + bottom) / 2), gapY * 0.18, marker);
      }
    }
    for (var s = 0; s < 6; s++) {
      final y = top + s * gapY;
      canvas.drawLine(Offset(0, y), Offset(size.width, y), stroke);
    }
    // Fret numbers.
    final small = size.width / 42;
    for (var f = 1; f <= _frets; f++) {
      _text(
        canvas,
        '$f',
        Offset((f + 0.5) * gapX, bottom + (size.height - bottom) / 2),
        color: muted,
        size: small,
      );
    }
    // The notes: string 0 at the top is the high E.
    final r = (gapY < gapX ? gapY : gapX) * 0.42;
    for (var s = 0; s < 6; s++) {
      final y = top + s * gapY;
      final open = standardTuning[5 - s];
      for (var f = 0; f <= _frets; f++) {
        final pc = (open + f) % 12;
        final spelled = scale.spell(pc);
        if (spelled == null) continue;
        final isRoot = pc == scale.root.pitchClass;
        final x = (f + 0.5) * gapX;
        canvas.drawCircle(
          Offset(x, y),
          r,
          Paint()..color = isRoot ? root : note,
        );
        if (!isRoot) {
          canvas.drawCircle(
            Offset(x, y),
            r,
            Paint()
              ..color = line.withValues(alpha: 0.5)
              ..style = PaintingStyle.stroke
              ..strokeWidth = 0.8,
          );
        }
        _text(
          canvas,
          spelled.name,
          Offset(x, y),
          color: isRoot ? onRoot : onNote,
          size: r * (spelled.name.length > 1 ? 0.95 : 1.15),
          bold: isRoot,
        );
      }
    }
  }

  void _text(
    Canvas canvas,
    String text,
    Offset center, {
    required Color color,
    required double size,
    bool bold = false,
  }) {
    final painter = TextPainter(
      text: TextSpan(
        text: text,
        style: TextStyle(
          color: color,
          fontSize: size,
          fontWeight: bold ? FontWeight.w700 : FontWeight.w500,
        ),
      ),
      textDirection: TextDirection.ltr,
    )..layout();
    painter.paint(
      canvas,
      Offset(center.dx - painter.width / 2, center.dy - painter.height / 2),
    );
  }

  @override
  bool shouldRepaint(_FretboardPainter old) =>
      old.scale.root != scale.root ||
      old.scale.type.key != scale.type.key ||
      old.line != line ||
      old.root != root;
}
