import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:tabscan_app/screens/mono_font.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  test('a staff\'s strings of the same length end together', () async {
    // The font the app ships, loaded as the app loads it.
    final loader = FontLoader(monoFont)
      ..addFont(rootBundle.load('assets/fonts/RobotoMono.ttf'));
    await loader.load();

    double width(String line) {
      final painter = TextPainter(
        text: TextSpan(
          text: line,
          style: const TextStyle(fontFamily: monoFont, fontSize: 15),
        ),
        textDirection: TextDirection.ltr,
      )..layout();
      return painter.width;
    }

    // A made-up riff: digits, letters, bars and dashes all one width.
    const staff = [
      'e|--0--3--5--7-----|',
      'B|-----------8--10-|',
      'G|--h--p--/--\\--~--|',
      'D|-----------------|',
    ];
    final widths = staff.map(width).toSet();
    expect(widths, hasLength(1));
  });
}
