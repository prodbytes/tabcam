@TestOn('browser')
library;

import 'dart:async';
import 'dart:js_interop';
import 'dart:js_interop_unsafe';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:tabcam_app/screens/game_controller.dart';
import 'package:tabcam_app/screens/game_controller_web.dart';
import 'package:web/web.dart' as web;

/// The browser's controllers read each frame
/// (`bash scripts/test-browser.sh test/web_game_controller_test.dart`),
/// with made-up controllers in place of the browser's list; and every
/// button's key event, as the web makes it (its ids, past 32 bits).
void main() {
  /// The controllers the browser lists ([web.Navigator.getGamepads]).
  var pads = <JSObject?>[];
  web.window.navigator.setProperty('getGamepads'.toJS, (() => pads.toJS).toJS);

  /// A connected controller with the buttons [pressed].
  JSObject pad(Set<int> pressed, {String mapping = 'standard'}) =>
      {
            'connected': true,
            'mapping': mapping,
            'buttons': [
              for (var i = 0; i < 17; i++)
                {'pressed': pressed.contains(i), 'value': 0},
            ],
          }.jsify()!
          as JSObject;

  /// After the next two frames: the reader's has run.
  Future<void> frames() async {
    for (var i = 0; i < 2; i++) {
      final frame = Completer<void>();
      web.window.requestAnimationFrame(((JSNumber _) => frame.complete()).toJS);
      await frame.future;
    }
  }

  test(
    'each frame, the buttons pressed on the standard controllers; with '
    'none left, none pressed, and no more frames until one connects',
    () async {
      final told = <Set<int>>[];
      pads = [
        pad({0, 5}),
        null,
        pad({3}, mapping: ''),
      ];
      watchControllers(told.add);
      await frames();
      expect(told.last, {0, 5});

      // Two controllers: their buttons together.
      pads = [
        pad({0}),
        pad({14}),
      ];
      await frames();
      expect(told.last, {0, 14});

      // None left: told once, then no frames.
      pads = [];
      await frames();
      expect(told.last, <int>{});
      final count = told.length;
      await frames();
      expect(told, hasLength(count));

      // One connects: read again.
      pads = [
        pad({7}),
      ];
      web.window.dispatchEvent(web.Event('gamepadconnected'));
      await frames();
      expect(told.last, {7});
      pads = [];
      await frames();
    },
  );

  testWidgets('every button presses its key on the web too', (tester) async {
    final reached = <KeyEvent>[];
    await tester.pumpWidget(
      MaterialApp(
        home: Focus(
          autofocus: true,
          onKeyEvent: (_, event) {
            reached.add(event);
            return KeyEventResult.handled;
          },
          child: const SizedBox.expand(),
        ),
      ),
    );
    for (final MapEntry(key: number, value: key)
        in GameController.keys.entries) {
      reached.clear();
      GameController.press(number, down: true);
      GameController.press(number, down: false);
      await tester.pump();
      expect(reached.map((e) => (e.runtimeType, e.logicalKey)), [
        (KeyDownEvent, key),
        (KeyUpEvent, key),
      ], reason: 'button $number');
    }
    expect(reached.first.character, isNull); // The D-pad's → types nothing.
  });
}
