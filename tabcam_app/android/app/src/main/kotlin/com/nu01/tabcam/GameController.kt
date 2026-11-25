package com.nu01.tabcam

import android.view.KeyEvent
import io.flutter.plugin.common.BinaryMessenger
import io.flutter.plugin.common.MethodChannel

/**
 * A game controller's buttons (a PS4's, or any Android takes as a
 * gamepad), for lib/screens/game_controller.dart, which presses the key
 * each stands for. [MainActivity] hands its key events here before
 * Flutter sees them: a gamepad button's is told on the channel
 * `tabcam/controller` (`button`, with `[number, down]`, the button
 * numbered as on the web's standard gamepad) and goes no further (Flutter
 * would take an unknown button as any key). A button held doesn't repeat.
 * The D-pad isn't a button here: Android sends it as the arrow keys,
 * which reach Flutter as they are.
 */
class GameController(messenger: BinaryMessenger) {
    private val channel = MethodChannel(messenger, "tabcam/controller")

    /** Whether [event] was a gamepad button's: told (or, with no number, dropped). */
    fun onKey(event: KeyEvent): Boolean {
        if (!KeyEvent.isGamepadButton(event.keyCode)) return false
        val number = standard[event.keyCode]
        val down = event.action == KeyEvent.ACTION_DOWN
        if (number != null && (down && event.repeatCount == 0 || event.action == KeyEvent.ACTION_UP)) {
            channel.invokeMethod("button", listOf(number, down))
        }
        return true
    }

    private companion object {
        /** Android's buttons by their number on the web's standard gamepad. */
        val standard = mapOf(
            KeyEvent.KEYCODE_BUTTON_A to 0, // ✕
            KeyEvent.KEYCODE_BUTTON_B to 1, // ○
            KeyEvent.KEYCODE_BUTTON_X to 2, // □
            KeyEvent.KEYCODE_BUTTON_Y to 3, // △
            KeyEvent.KEYCODE_BUTTON_L1 to 4,
            KeyEvent.KEYCODE_BUTTON_R1 to 5,
            KeyEvent.KEYCODE_BUTTON_L2 to 6,
            KeyEvent.KEYCODE_BUTTON_R2 to 7,
            KeyEvent.KEYCODE_BUTTON_SELECT to 8, // Share
            KeyEvent.KEYCODE_BUTTON_START to 9, // Options
            KeyEvent.KEYCODE_BUTTON_THUMBL to 10,
            KeyEvent.KEYCODE_BUTTON_THUMBR to 11,
            KeyEvent.KEYCODE_BUTTON_MODE to 16, // PS
        )
    }
}
