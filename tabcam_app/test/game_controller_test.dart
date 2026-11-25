import 'dart:ui' as ui;

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:tabcam_app/screens/game_controller.dart';

void main() {
  /// A screen that keeps the key events reaching it, and a field.
  Widget screen(List<KeyEvent> reached) => MaterialApp(
    home: Focus(
      autofocus: true,
      onKeyEvent: (_, event) {
        reached.add(event);
        return KeyEventResult.handled;
      },
      child: const Scaffold(body: SizedBox.expand()),
    ),
  );

  /// The button [number] told on the channel, as Android's and iOS's code
  /// tells it.
  Future<void> told(WidgetTester tester, int number, bool down) async {
    await tester.binding.defaultBinaryMessenger.handlePlatformMessage(
      GameController.channel.name,
      GameController.channel.codec.encodeMethodCall(
        MethodCall('button', [number, down]),
      ),
      (_) {},
    );
    await tester.pump();
  }

  testWidgets('a button presses its key, as the keyboard does: once while '
      'held, the controller\'s', (tester) async {
    final reached = <KeyEvent>[];
    await tester.pumpWidget(screen(reached));

    GameController.press(0, down: true);
    await tester.pump();
    expect(reached, hasLength(1));
    final down = reached.single;
    expect(down, isA<KeyDownEvent>());
    expect(down.logicalKey, LogicalKeyboardKey.space);
    expect(down.character, ' ');
    expect(down.physicalKey, PhysicalKeyboardKey.gameButton1);
    expect(down.deviceType, ui.KeyEventDeviceType.gamepad);
    expect(
      HardwareKeyboard.instance.logicalKeysPressed,
      contains(LogicalKeyboardKey.space),
    );

    // Down again, held: nothing more (no repeat).
    GameController.press(0, down: true);
    await tester.pump();
    expect(reached, hasLength(1));

    GameController.press(0, down: false);
    await tester.pump();
    expect(reached, hasLength(2));
    expect(reached.last, isA<KeyUpEvent>());
    expect(reached.last.logicalKey, LogicalKeyboardKey.space);
    expect(HardwareKeyboard.instance.logicalKeysPressed, isEmpty);

    // Up again: nothing.
    GameController.press(0, down: false);
    await tester.pump();
    expect(reached, hasLength(2));
  });

  testWidgets('✕ Space, ○ 0, □ ., △ /, R1 ←, R2 →, the D-pad the arrows; '
      'the other buttons nothing', (tester) async {
    final reached = <KeyEvent>[];
    await tester.pumpWidget(screen(reached));
    const keys = {
      0: (LogicalKeyboardKey.space, ' '),
      1: (LogicalKeyboardKey.digit0, '0'),
      2: (LogicalKeyboardKey.period, '.'),
      3: (LogicalKeyboardKey.slash, '/'),
      5: (LogicalKeyboardKey.arrowLeft, null),
      7: (LogicalKeyboardKey.arrowRight, null),
      12: (LogicalKeyboardKey.arrowUp, null),
      13: (LogicalKeyboardKey.arrowDown, null),
      14: (LogicalKeyboardKey.arrowLeft, null),
      15: (LogicalKeyboardKey.arrowRight, null),
    };
    for (var number = 0; number <= 16; number++) {
      reached.clear();
      GameController.press(number, down: true);
      GameController.press(number, down: false);
      await tester.pump();
      final key = keys[number];
      if (key == null) {
        expect(reached, isEmpty, reason: 'button $number');
        continue;
      }
      expect(reached, hasLength(2), reason: 'button $number');
      expect(reached.first.logicalKey, key.$1, reason: 'button $number');
      expect(reached.first.character, key.$2, reason: 'button $number');
    }
  });

  testWidgets('the shortcuts take a button\'s key as the keyboard\'s', (
    tester,
  ) async {
    var slashes = 0;
    await tester.pumpWidget(
      MaterialApp(
        home: CallbackShortcuts(
          bindings: {
            const SingleActivator(LogicalKeyboardKey.slash): () => slashes++,
          },
          child: const Focus(autofocus: true, child: SizedBox.expand()),
        ),
      ),
    );
    GameController.press(3, down: true);
    GameController.press(3, down: false);
    await tester.pump();
    expect(slashes, 1);
  });

  testWidgets('the channel (Android, iOS): each button told presses its '
      'key; a press whose release never came counts as a new one', (
    tester,
  ) async {
    final reached = <KeyEvent>[];
    await tester.pumpWidget(screen(reached));
    GameController.start();
    addTearDown(() => GameController.channel.setMethodCallHandler(null));

    await told(tester, 1, true);
    expect(reached.map((e) => (e.runtimeType, e.logicalKey)), [
      (KeyDownEvent, LogicalKeyboardKey.digit0),
    ]);
    await told(tester, 1, true);
    expect(reached.skip(1).map((e) => (e.runtimeType, e.logicalKey)), [
      (KeyUpEvent, LogicalKeyboardKey.digit0),
      (KeyDownEvent, LogicalKeyboardKey.digit0),
    ]);
    await told(tester, 1, false);
    expect(reached.last, isA<KeyUpEvent>());
    expect(HardwareKeyboard.instance.logicalKeysPressed, isEmpty);

    // A button with no key (L1).
    reached.clear();
    await told(tester, 4, true);
    await told(tester, 4, false);
    expect(reached, isEmpty);
  });

  testWidgets('the buttons pressed each frame (the web): only the changes '
      'are keys', (tester) async {
    final reached = <KeyEvent>[];
    await tester.pumpWidget(screen(reached));
    (Type, LogicalKeyboardKey) of(KeyEvent e) => (e.runtimeType, e.logicalKey);

    GameController.buttons({0, 5});
    await tester.pump();
    expect(reached.map(of), [
      (KeyDownEvent, LogicalKeyboardKey.space),
      (KeyDownEvent, LogicalKeyboardKey.arrowLeft),
    ]);
    // Held: nothing new.
    GameController.buttons({0, 5});
    await tester.pump();
    expect(reached, hasLength(2));
    // R1 and the D-pad's ←: one key each, both ←.
    GameController.buttons({5, 14});
    await tester.pump();
    expect(reached.skip(2).map(of), [
      (KeyUpEvent, LogicalKeyboardKey.space),
      (KeyDownEvent, LogicalKeyboardKey.arrowLeft),
    ]);
    // None pressed (the controller gone): all let go.
    GameController.buttons({});
    await tester.pump();
    expect(reached.skip(4).map(of), [
      (KeyUpEvent, LogicalKeyboardKey.arrowLeft),
      (KeyUpEvent, LogicalKeyboardKey.arrowLeft),
    ]);
    expect(HardwareKeyboard.instance.physicalKeysPressed, isEmpty);
  });
}
