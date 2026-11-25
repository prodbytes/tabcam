/// The browser's game controllers (its Gamepad API), for
/// [GameController](game_controller.dart).
library;

import 'dart:js_interop';

import 'package:web/web.dart' as web;

/// Watches the browser's controllers: while one is connected, each frame
/// tells [buttons] the buttons pressed on them (by their number on the
/// standard gamepad; a controller the browser doesn't map to it is left
/// out, as its numbers would be other buttons). The browser tells of a
/// controller at its first press (or when it's connected, one already
/// used on the page); with none left, [buttons] is told none is pressed,
/// and the frames stop until the next.
void watchControllers(void Function(Set<int> pressed) buttons) {
  var reading = false;
  late final JSFunction frame;
  void read(JSNumber _) {
    final pressed = <int>{};
    var connected = false;
    for (final pad in web.window.navigator.getGamepads().toDart) {
      if (pad == null || !pad.connected || pad.mapping != 'standard') {
        continue;
      }
      connected = true;
      final pads = pad.buttons.toDart;
      for (var i = 0; i < pads.length; i++) {
        if (pads[i].pressed) pressed.add(i);
      }
    }
    buttons(pressed);
    reading = connected;
    if (reading) web.window.requestAnimationFrame(frame);
  }

  frame = read.toJS;
  void begin() {
    if (reading) return;
    reading = true;
    web.window.requestAnimationFrame(frame);
  }

  web.window.addEventListener(
    'gamepadconnected',
    ((web.Event _) => begin()).toJS,
  );
  // One connected already (the page reloaded): the browser lists it, but
  // may not tell of it again.
  begin();
}
