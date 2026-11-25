/// A game controller (a PS4's, or any the system knows as one) works as a
/// keyboard: its buttons press the keys of the app's shortcuts
/// ([keys_help.dart](keys_help.dart)), so each screen's keys work from it
/// as they do from the keyboard, wherever they would (the screen on top,
/// not while typing in a field): ✕ is the space bar, ○ the 0, □ the .,
/// △ the /, R1 ←, R2 → and the D-pad the arrows. Its other buttons do
/// nothing.
///
/// The system tells the buttons, each numbered as the web's standard
/// gamepad numbers it ([keys]): on Android and iOS the app's own code, on
/// the method channel `tabcam/controller` (`button`, with `[number,
/// down]`; on Android the D-pad comes as the arrow keys already), on the
/// web the browser's Gamepad API ([platform.watchControllers]).
library;

import 'dart:ui' as ui;

import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';

import 'game_controller_stub.dart'
    if (dart.library.js_interop) 'game_controller_web.dart'
    as platform;

abstract final class GameController {
  /// The channel Android's and iOS's code tell the buttons on.
  static const channel = MethodChannel('tabcam/controller');

  /// The key each button presses, by its number on the web's standard
  /// gamepad: 0 ✕, 1 ○, 2 □, 3 △, 5 R1, 7 R2, 12 to 15 the D-pad's ↑, ↓,
  /// ← and →. Not here, so pressing nothing: 4 L1, 6 L2, 8 Share, 9
  /// Options, 10 and 11 the sticks, 16 the PS button.
  static final keys = <int, LogicalKeyboardKey>{
    0: LogicalKeyboardKey.space,
    1: LogicalKeyboardKey.digit0,
    2: LogicalKeyboardKey.period,
    3: LogicalKeyboardKey.slash,
    5: LogicalKeyboardKey.arrowLeft,
    7: LogicalKeyboardKey.arrowRight,
    12: LogicalKeyboardKey.arrowUp,
    13: LogicalKeyboardKey.arrowDown,
    14: LogicalKeyboardKey.arrowLeft,
    15: LogicalKeyboardKey.arrowRight,
  };

  /// Listens to the controllers: the channel on Android and iOS, the
  /// browser's on the web. Once, at the app's start.
  static void start() {
    if (kIsWeb) {
      platform.watchControllers(buttons);
    } else {
      channel.setMethodCallHandler(_call);
    }
  }

  static Future<void> _call(MethodCall call) async {
    if (call.method != 'button') return;
    final [number as int, down as bool] = call.arguments as List<Object?>;
    // A press with the button still down here: its release was missed
    // (the app was away), so it's let go first, and the press counts.
    if (down) press(number, down: false);
    press(number, down: down);
  }

  /// The buttons [pressed] now, by number, on every controller: each
  /// button's key goes down or up where it changed ([press]).
  static void buttons(Set<int> pressed) {
    for (final number in keys.keys) {
      press(number, down: pressed.contains(number));
    }
  }

  /// The button [number] went [down] (or up): its key does, as a key
  /// event the app takes as the keyboard's, through its shortcuts and
  /// focus. The event is the controller's (its physical key the
  /// button's, `Game Button 1` for ✕; [KeyEvent.deviceType] a gamepad),
  /// its logical key the keyboard's. A button already down (or up) again,
  /// or one with no key, is nothing; held, it doesn't repeat.
  static void press(int number, {required bool down}) {
    final key = keys[number];
    if (key == null) return;
    final button = PhysicalKeyboardKey(
      PhysicalKeyboardKey.gameButton1.usbHidUsage + number,
    );
    final isDown = HardwareKeyboard.instance.lookUpLayout(button) != null;
    if (isDown == down) return;
    // A key that types (the space bar, 0, ., /) types its character.
    final types =
        (key.keyId & LogicalKeyboardKey.planeMask) ==
        LogicalKeyboardKey.unicodePlane;
    // The engine's own way in: it updates the keyboard's state and goes
    // through the focus and the shortcuts, as a key pressed does.
    ServicesBinding.instance.platformDispatcher.onKeyData?.call(
      ui.KeyData(
        timeStamp: Duration(
          microseconds: DateTime.now().microsecondsSinceEpoch,
        ),
        type: down ? ui.KeyEventType.down : ui.KeyEventType.up,
        physical: button.usbHidUsage,
        logical: key.keyId,
        character: down && types ? String.fromCharCode(key.keyId) : null,
        synthesized: true,
        deviceType: ui.KeyEventDeviceType.gamepad,
      ),
    );
  }
}
