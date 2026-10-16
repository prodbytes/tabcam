# Cam: playing along

**Cam**, a tool on the [event screen](event-screen.md), lets a guitarist
record themselves playing along with the capture's tab. It opens the
camera view ([`PlayAlongScreen`](../tabcam_app/lib/capture/play_along_screen.dart)):

- **The camera** fills the screen, the **front** one first (it faces the
  player); **Flip camera** in the app bar moves to the next one (not
  while recording). The app bar has the capture's title. Without a
  camera, or one that isn't allowed, the view says so.
- **The tab**, along the bottom, one **neckline** at a time: a staff
  (a run of string lines) with the lines right above it, such as chord
  names and a section name
  ([`necklines`](../tabcam_app/lib/recognition/necklines.dart)). Text
  that isn't over a staff (lyrics under it, notes at the end) is left
  out; a tab with no string lines at all (chords only) shows its
  blocks between blank lines. The neckline is in the monospace font,
  shrunk to fit the screen's width (a long staff reads best with the
  phone turned sideways), with its number under it ("2 / 14"). A
  capture with no text tab yet says to read it first.
- **Moving along the tab**: any key goes to the next neckline (a
  keyboard, or a Bluetooth page-turner pedal); **Backspace**, **←**,
  **↑** and **Page Up** go to the one before. Shift, Control, Alt,
  Meta, Caps Lock, Fn and Escape pressed alone do nothing. A tap on the
  neckline goes to the next; the arrows beside it (**Previous line**,
  **Next line**) to either side. It stops at the first and the last.
- <a id="head-gestures"></a>**Head gestures** (Android and iOS): a nod
  **up**, or a turn of the head to the user's **right**, goes to the next
  neckline; a nod **down** or a turn to the **left**, to the one before
  ([`head_gestures.dart`](../tabcam_app/lib/capture/head_gestures.dart)).
  Only a strong, deliberate gesture counts, so playing doesn't turn the
  tab: the head must move at least 20° up or down, or 25° sideways, from
  where it rests, and come back to rest (within 8°) within a second; the
  strongest direction wins. Held away longer, such as looking down at
  the fretboard, it's no gesture, and after 3 s there the head rests
  there. After a gesture, the next waits 0.8 s. The camera's frames
  (about 10 a second, while recording too) go to ML Kit's face detector
  (`google_mlkit_face_detection`, accurate mode, on the device, the
  nearest face); its angles never leave the phone. A face icon in the
  app bar switches them on (the default) and off, green while it sees a
  face. While a take plays back, gestures do nothing. The web has no
  head gestures (no ML Kit there), nor the icon.
- **Rec** records video and sound (`camera`, `ResolutionPreset.high`)
  from the neckline showing, until **Stop**. The take is then added to
  the capture as a video, at the end of its files, named "Take 1",
  "Take 2"… (the first number no file has), and a message says so. It
  syncs as any video does. Going back while recording stops it and
  keeps the take. Back on the capture, its takes show: the file list
  (not the Text view), scrolled to its end.
- **Play** plays the last take of this visit back in the camera's place,
  until **Stop** or its end; the necklines turn where they turned while
  it was recorded. When they turned isn't saved with the take: older
  takes play from the [file list](event-screen.md) without the tab.

Cam is off on a capture shared read only or opened by its link (a take
couldn't be saved there), and while a tool works. Opening it stops what
plays in the list.

**Permissions**: the camera and the microphone (iOS:
`NSCameraUsageDescription`, `NSMicrophoneUsageDescription`; Android: the
`camera` plugin's `CAMERA` and `RECORD_AUDIO`; the web: the browser's
prompt). On the web a take is WebM, on Android MP4, on iOS MOV.
