@TestOn('browser')
library;

import 'package:flutter_test/flutter_test.dart';
import 'package:tabcam_app/sound/ding.dart';

/// Rescan's ding through Web Audio, in a real browser
/// (`bash scripts/test-browser.sh`: Chrome with sound allowed without a
/// tap, standing in for the tap that wakes it): woken, it plays, and again
/// after it went back to sleep.
void main() {
  test('the ding plays, and plays again', () async {
    primeDing();
    expect(await playDing(), isTrue);
    // It ends (700 ms) and the sound sleeps; the next one wakes it.
    await Future<void>.delayed(const Duration(seconds: 1));
    expect(await playDing(), isTrue);
  });
}
