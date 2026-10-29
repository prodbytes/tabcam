import 'package:flutter/material.dart';

import '../l10n/language.dart';
import 'mono_font.dart';

/// A quick sheet of tab notation, at the bottom of the Text view's
/// play-along sidebar: how a hammer-on, a pull-off, a slide, a bend,
/// vibrato and a ghost note are written, each as it looks in the tab (in the tab's font) and what
/// it is. For the sidebar's dark background.
class NotationSheet extends StatelessWidget {
  const NotationSheet({super.key});

  @override
  Widget build(BuildContext context) {
    final l10n = context.l10n;
    final rows = [
      ('5h7', l10n.textViewNotationHammerOn),
      ('7p5', l10n.textViewNotationPullOff),
      ('5/7 7\\5', l10n.textViewNotationSlide),
      ('7b9 r7', l10n.textViewNotationBend),
      ('7~', l10n.textViewNotationVibrato),
      ('(5)', l10n.textViewNotationGhost),
    ];
    return Padding(
      key: const Key('text-notation'),
      padding: const EdgeInsets.fromLTRB(16, 8, 16, 12),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            l10n.textViewNotation,
            style: const TextStyle(color: Colors.white54, fontSize: 12),
          ),
          const SizedBox(height: 4),
          for (final (symbol, meaning) in rows)
            Padding(
              padding: const EdgeInsets.only(top: 2),
              child: Row(
                crossAxisAlignment: CrossAxisAlignment.baseline,
                textBaseline: TextBaseline.alphabetic,
                children: [
                  SizedBox(
                    width: 64,
                    child: Text(
                      symbol,
                      style: const TextStyle(
                        color: Colors.white,
                        fontFamily: monoFont,
                        fontSize: 12,
                      ),
                    ),
                  ),
                  Expanded(
                    child: Text(
                      meaning,
                      style: const TextStyle(
                        color: Colors.white70,
                        fontSize: 11,
                      ),
                    ),
                  ),
                ],
              ),
            ),
        ],
      ),
    );
  }
}
