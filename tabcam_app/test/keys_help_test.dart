import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:tabcam_app/l10n/app_localizations.dart';
import 'package:tabcam_app/screens/keys_help.dart';

void main() {
  /// A screen with the button in its app bar, a field, and a count of the
  /// keys that reach the screen (Cam turns its tab on them).
  Widget screen(KeysScreen kind, {required List<KeyEvent> reached}) =>
      MaterialApp(
        localizationsDelegates: AppLocalizations.localizationsDelegates,
        supportedLocales: AppLocalizations.supportedLocales,
        home: Focus(
          autofocus: true,
          onKeyEvent: (_, event) {
            reached.add(event);
            return KeyEventResult.handled;
          },
          child: Scaffold(
            appBar: AppBar(actions: [KeysHelpButton(screen: kind)]),
            body: const TextField(key: Key('field')),
          ),
        ),
      );

  final overlay = find.byKey(const Key('keys-help-overlay'));

  testWidgets('the button opens the overlay; H, Esc and Close shut it', (
    tester,
  ) async {
    final reached = <KeyEvent>[];
    await tester.pumpWidget(screen(KeysScreen.player, reached: reached));
    expect(find.byTooltip('Keyboard shortcuts (H)'), findsOneWidget);
    await tester.tap(find.byKey(const Key('keys-help')));
    await tester.pumpAndSettle();
    expect(overlay, findsOneWidget);
    expect(find.text('Keyboard shortcuts'), findsOneWidget);
    expect(find.text('Play or pause the song'), findsOneWidget);
    expect(find.text('Back to the start, with the count-in'), findsOneWidget);
    // Not Cam's nor the editor's.
    expect(find.text('Takes'), findsNothing);
    expect(find.text('Play or pause the preview'), findsNothing);

    await tester.sendKeyEvent(LogicalKeyboardKey.keyH);
    await tester.pumpAndSettle();
    expect(overlay, findsNothing);

    await tester.sendKeyEvent(LogicalKeyboardKey.keyH);
    await tester.pumpAndSettle();
    expect(overlay, findsOneWidget);
    await tester.sendKeyEvent(LogicalKeyboardKey.escape);
    await tester.pumpAndSettle();
    expect(overlay, findsNothing);

    await tester.sendKeyEvent(LogicalKeyboardKey.keyH);
    await tester.pumpAndSettle();
    await tester.tap(find.text('Close'));
    await tester.pumpAndSettle();
    expect(overlay, findsNothing);
    // H never reached the screen (a key down: the screens act on those).
    expect(
      reached.where(
        (e) => e is KeyDownEvent && e.logicalKey == LogicalKeyboardKey.keyH,
      ),
      isEmpty,
    );
  });

  testWidgets('H types in a field, and does nothing with Ctrl, ⌘ or Alt', (
    tester,
  ) async {
    final reached = <KeyEvent>[];
    await tester.pumpWidget(screen(KeysScreen.player, reached: reached));
    await tester.tap(find.byKey(const Key('field')));
    await tester.pump();
    await tester.sendKeyEvent(LogicalKeyboardKey.keyH);
    await tester.pumpAndSettle();
    expect(overlay, findsNothing);
    // Out of the field.
    FocusManager.instance.primaryFocus?.unfocus();
    await tester.pump();
    for (final modifier in [
      LogicalKeyboardKey.controlLeft,
      LogicalKeyboardKey.metaLeft,
      LogicalKeyboardKey.altLeft,
    ]) {
      await tester.sendKeyDownEvent(modifier);
      await tester.sendKeyEvent(LogicalKeyboardKey.keyH);
      await tester.sendKeyUpEvent(modifier);
      await tester.pumpAndSettle();
      expect(overlay, findsNothing);
    }
  });

  testWidgets('lists each screen\'s keys', (tester) async {
    final reached = <KeyEvent>[];
    await tester.pumpWidget(screen(KeysScreen.cam, reached: reached));
    await tester.sendKeyEvent(LogicalKeyboardKey.keyH);
    await tester.pumpAndSettle();
    for (final text in [
      'Turning the tab',
      'Next phrase (a page-turner pedal too)',
      'Takes',
      'Play or pause the song',
      'Show or hide these shortcuts',
    ]) {
      expect(find.text(text), findsOneWidget, reason: text);
    }
    await tester.sendKeyEvent(LogicalKeyboardKey.keyH);
    await tester.pumpAndSettle();

    await tester.pumpWidget(screen(KeysScreen.videoEdit, reached: reached));
    await tester.pumpAndSettle();
    await tester.sendKeyEvent(LogicalKeyboardKey.keyH);
    await tester.pumpAndSettle();
    expect(find.text('Play or pause the preview'), findsOneWidget);
    expect(find.text('Shift + ←'), findsOneWidget);
    expect(find.text('Takes'), findsNothing);
    expect(find.text('Play or pause the song'), findsNothing);
  });

  testWidgets('a phone has the key but no button', (tester) async {
    tester.view.physicalSize = const Size(360, 740);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);
    debugDefaultTargetPlatformOverride = TargetPlatform.android;
    try {
      final reached = <KeyEvent>[];
      await tester.pumpWidget(screen(KeysScreen.cam, reached: reached));
      expect(find.byKey(const Key('keys-help')), findsNothing);
      await tester.sendKeyEvent(LogicalKeyboardKey.keyH);
      await tester.pumpAndSettle();
      expect(overlay, findsOneWidget);
      expect(tester.takeException(), isNull);
    } finally {
      debugDefaultTargetPlatformOverride = null;
    }
  });

  testWidgets('fits at the largest text size', (tester) async {
    tester.view.physicalSize = const Size(400, 700);
    tester.view.devicePixelRatio = 1;
    tester.platformDispatcher.textScaleFactorTestValue = 2;
    addTearDown(tester.view.reset);
    addTearDown(tester.platformDispatcher.clearTextScaleFactorTestValue);
    final reached = <KeyEvent>[];
    await tester.pumpWidget(screen(KeysScreen.cam, reached: reached));
    await tester.sendKeyEvent(LogicalKeyboardKey.keyH);
    await tester.pumpAndSettle();
    expect(overlay, findsOneWidget);
    expect(tester.takeException(), isNull);
  });
}
