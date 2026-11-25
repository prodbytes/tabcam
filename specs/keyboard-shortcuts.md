# Keyboard shortcuts

**Every button that has a key names it in its tooltip**, after what it
does: "Rec (.)", "Redo (.): …", "New take (/ or ,): …", "Previous
phrase (↑)", "Next phrase (↓)", "Back to the start (0)", "Back 10
seconds (←)", "Play (space)", "Forward 10 seconds (→)", "To the start
(Home)", "To the end (End)", the Text view's "Select all (⌘A)" and
"Select the phrase; again, the next one too (⌘L)", "Keyboard shortcuts
(H)". A key that's the button's only some of the time (the space bar
plays Cam's main-row song only while the sidebar shows) is named only
then. Buttons with no key (Tab, Auto-pass, the microphone's menu,
Stop's own beyond the take keys) say what they do alone.

The screens with keys show what they are: a **keyboard button** (a
keyboard icon, "Keyboard shortcuts (H)") in the app bar, or the **H**
key, opens an overlay listing that screen's keys
([`keys_help.dart`](../tabcam_app/lib/screens/keys_help.dart)). It's on:

- **Cam** ([cam.md](cam.md)), after the play-along button: with a
  take edited in Cam's view, the video editor's, below;
- a **capture's screens** ([event screen](event-screen.md): the files,
  the Text view, the locked previews) and a **file's screen**, after the
  play-along button (on a phone's capture, whose buttons go in a menu,
  there's no button, but H works);
- the **video editor** ([video edit](video-edit.md)), before About (on
  a phone, before its More menu).

Home has no keys, so no button. Nor does a capture opened by its link
signed out (or a file opened from it): the help, button and H key, is
signed-in users', as the dictionary and the metronome are
([sharing](sharing.md#opening-a-link)).

**Cam's view and the editor's are one** ([Cam's view](cam.md#cams-view),
[in Cam](video-edit.md#in-cam)), and its keys go by what's in its main
row: with the camera, Cam's (the tab, the takes) and the play-along
player's (Space, 1, 0, ←, →, while its sidebar shows); with a take
edited in the camera's place, the editor's alone: the space bar plays
the take's preview, ← and → move it, and /, ., 1, 0 and the tab's keys
do nothing, the play-along sidebar showing or not. Back at the camera,
Cam's keys are back. The keyboard button and **H** show the list of
the keys that work then: Cam's, or the video editor's.

**Where the button shows**: on the web, on a computer (macOS, Windows,
Linux) and on a tablet (a screen 600 px or more on its short side): where
a keyboard is likely. On a phone's app it's left out, to leave the app
bar's room to the title; **H** works there too (a Bluetooth keyboard).

**The H key**: pressed alone (with Ctrl, ⌘ or Alt it's another
shortcut's), on the screen on top (under a dialog, a menu or another
screen, it's that one's), and not while typing in a field (the
dictionary's search, the Text view's editor, a video's title: there it
types an h). It's taken before the screen's own keys, so in Cam H
doesn't turn the tab. Open, the overlay shuts on **H** again, **Esc** or
**Close**; Cam then has its keys back.

**The overlay** ("Keyboard shortcuts") lists the screen's keys by
section, each key in a box as on the keyboard, then what it does:

- **Cam**:
  - *Turning the tab*: **Any key**, **↓**: next phrase (a page-turner
    pedal too); **↑**, **Backspace**, **Page Up**: previous phrase (←
    too, with nothing playing along).
  - *Takes*: **.** starts a take with the song from its start;
    recording, throws the take away and records it again. **/** and
    **,** start a take with the song from its start; recording, save
    the take and start the next, the song from its start again. Every
    take so started opens with the 2-second count-in, then the song
    ([Cam](cam.md#new-take-key); the Redo and New take buttons do the
    same).
  - *Playing along (while the sidebar shows; ↑ and ↓ then turn the
    tab)*: **Space**, **1** play or pause the song (pausing it while a
    take records stops the take, saved); **0** back to the
    start, with the count-in (the sidebar's **|◀** button too); **←**,
    **→** 10 seconds back or on
    ([the keys in every screen](cam.md#keys-in-every-screen)).
- **A capture's or a file's screen**: *Playing along (while the sidebar
  shows)*, the same three rows; then *In the Text view*: **⌘ + A**
  selects all the text, **⌘ + L** the phrase at the cursor, again the
  next one too (**Ctrl** in place of ⌘ off macOS and iOS: "Ctrl + A",
  "Ctrl + L"), the Text view's keys in its text
  ([selecting](tab-recognition.md#selecting)).
- **The video editor**: *Preview*: **Space** plays or pauses it;
  **Home** / **End** go to the start / end of the kept part (again: of
  the video); **←**, **→** a tenth of a second back or on; **Shift +
  ←**, **Shift + →** a second.
- Every screen: *Everywhere*: **H** shows or hides these shortcuts;
  then *Game controller*, the buttons that press the screen's keys
  ([below](#game-controller)).

Under the list: "Typing in a field, the keys type as usual." It scrolls
where the screen is short, and fits a phone at the largest text size. In
English, Spanish and Portuguese, the keys' names too (Espacio, Inicio,
Fin, Retroceso, Re Pág, Mayús in Spanish).

## Game controller

A game controller (a PS4's, or any the system knows as a gamepad) works
as a keyboard with these keys
([`game_controller.dart`](../tabcam_app/lib/screens/game_controller.dart)):

| Button | Key |
|---|---|
| ✕ | Space |
| ○ | 0 |
| □ | . |
| △ | / |
| R1 | ← |
| R2 | → |
| D-pad | ↑ ↓ ← → |

A press is that key pressed, through the same shortcuts and focus, so
every screen's keys work from it as from the keyboard, where they would
(the screen on top, not while typing in a field), and do what the key
does there: in Cam R1 is 10 seconds back while the play-along sidebar
shows and the previous phrase while nothing plays along, in the video
editor a tenth of a second back. L1, L2, Share, Options, the sticks'
buttons and the PS button do nothing (nor are they Cam's "any key"). A
button held is one press, with no repeat (Android's D-pad, which comes
as arrow keys, repeats as they do). Each key event is the controller's:
its physical key the button's (Game Button 1 for ✕), its device a
gamepad, its logical key the keyboard's.

The buttons are read on the device, each numbered as on the web's
standard gamepad (0 ✕, 1 ○, 2 □, 3 △, 4 L1, 5 R1, 6 L2, 7 R2, 12 to
15 the D-pad's ↑ ↓ ← →):

- **Android**: the activity hands a gamepad button's key events to
  `GameController.kt` before Flutter: each press and release goes to
  Dart on the method channel `tabcam/controller` (`button`, `[number,
  down]`) and no further. The D-pad is Android's arrow keys (a
  controller's hat is made into them by the system), which Flutter
  takes as the arrows itself.
- **iOS**: Apple's GameController framework (`ControllerButtons` in
  `AppDelegate.swift`): the face buttons, shoulders, triggers and D-pad
  of each controller with a gamepad's layout, connected before the app
  started or after, on the same channel. A press told while its button
  is still down (its release missed while the app was away) is a new
  press.
- **Web**: the browser's Gamepad API: while a controller is connected,
  each animation frame reads the buttons pressed on those with the
  standard mapping (another mapping's numbers are other buttons, so
  it's left out); with none left, every key goes up and the reading
  stops until the next `gamepadconnected`. Browsers tell of a
  controller at its first press on the page.

**In the overlay**, the *Game controller* section ("Mando de juego",
"Controle de videogame") shows each button that presses one of the
screen's keys, "=", then the key: the face buttons as their symbols
(read out as Cross, Circle, Square, Triangle), R1 and R2 by name, the
D-pad as its icon. Cam has them all; a capture's or a file's screen ✕,
○, R1, R2 and the D-pad's ← →; the video editor ✕, R1, R2 and the
D-pad's ← →.
