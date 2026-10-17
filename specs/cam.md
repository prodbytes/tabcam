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
- **Moving along the tab**: any key (but the space bar while a file
  [plays along](#playing-along-with-a-file)) goes to the next neckline (a
  keyboard, or a Bluetooth page-turner pedal); **Backspace**, **←**,
  **↑** and **Page Up** go to the one before. Shift, Control, Alt,
  Meta, Caps Lock, Fn and Escape pressed alone do nothing. A tap on the
  neckline goes to the next; the arrows beside it (**Previous line**,
  **Next line**) to either side. It stops at the first and the last.
- <a id="head-gestures"></a>**Head gestures** (Android, iOS and the web): a nod
  **up**, or a turn of the head to the user's **right**, goes to the next
  neckline; a nod **down** or a turn to the **left**, to the one before
  ([`head_gestures.dart`](../tabcam_app/lib/capture/head_gestures.dart)).
  Only a strong, deliberate gesture counts, so playing doesn't turn the
  tab: the head must move at least 20° up or down, or 25° sideways, from
  where it rests, and come back to rest (within 8°) within a second; the
  strongest direction wins. Held away longer, such as looking down at
  the fretboard, it's no gesture, and after 3 s there the head rests
  there. After a gesture, the next waits 0.8 s. On Android and iOS the
  camera's frames (about 10 a second, while recording too) go to ML
  Kit's face detector (`google_mlkit_face_detection`, accurate mode, on
  the device, the nearest face); its angles never leave the phone.
  - **On the web** ([`web_head_tracker.dart`](../tabcam_app/lib/capture/web_head_tracker.dart),
    behind a conditional import, so Android and iOS don't build it), the
    browser's camera streams no frames to the app, so MediaPipe Tasks
    Vision's **Face Landmarker** reads the camera preview's own `<video>`
    itself, about 10 times a second, one detection at a time, while
    recording too (`detectForVideo`, `VIDEO` mode, one face, the facial
    transformation matrix on). camera_web gives that element no id or
    class, so the tracker looks for a `<video>` playing a live camera
    `MediaStream` (`srcObject`), one inside Flutter's
    `<flt-platform-view>` first, and looks again when the camera
    changes; no second camera stream is opened. The library
    (`@mediapipe/tasks-vision@0.10.21`, its WebAssembly from the same
    jsDelivr path) and the model (`face_landmarker.task`, float16 v1,
    from Google's `storage.googleapis.com/mediapipe-models`) load only
    when Cam opens with head gestures on, with the GPU, or the CPU if
    that fails. If they can't load (offline, blocked), it's logged
    (`TabCam: head gestures: …`) and no face is seen: Cam works on
    without gestures. The frames never leave the browser.
  - The head's angles come from the facial transformation matrix (4×4,
    column-major; `headAngles`): its third column is where the face
    looks in the camera's space (X to the frame's right, Y up, Z towards
    the user). Pitch is that direction's angle above level; yaw its
    angle towards -X, since the frames aren't mirrored (camera_web
    mirrors the front camera's preview with CSS only) and the user's
    right is on the frame's left.

  A face icon in the app bar switches them on (the default) and off,
  in the theme's primary colour while it sees a face; off, nothing
  watches for faces. While a take plays back, gestures do nothing.
- **Rec** records video and sound (`camera`, `ResolutionPreset.high`)
  from the neckline showing, until **Stop**. The take is then added to
  the capture as a video, at the end of its files, named "Take 1",
  "Take 2"… (the first number no file has), and a message says so. It
  syncs as any video does. Going back while recording stops it and
  keeps the take. Back on the capture, its takes show: the file list
  (not the Text view), scrolled to its end.
- <a id="the-tab-in-the-take"></a>**The tab is in the take**: each
  neckline shows along the bottom of the video while it showed in Cam,
  as a band as wide as the video (white monospaced text on a dark,
  see-through strip, about a third of a landscape take for a six-string
  staff; [`take_overlay.dart`](../tabcam_app/lib/capture/take_overlay.dart)).
  The app draws each band itself (`renderBand`, 1280 px wide, scaled to
  the video), the same on every platform, and puts it in on the device:
  nothing is uploaded to make it, and no server is involved.
  - **Web**: recorded in as it goes
    ([`web_take_recorder.dart`](../tabcam_app/lib/capture/web_take_recorder.dart)):
    every frame, the camera preview's `<video>` and the band go onto a
    canvas, and the browser's `MediaRecorder` records the canvas
    (`captureStream(30)`) with the camera's sound (else the
    microphone's): WebM (VP9 or VP8, Opus), or MP4 where only that
    records (Safari). Should a band's image fail, its text is drawn on
    the canvas as it is. Should the recorder fail to start, the camera
    records the take alone and a message says so, with why ("Recording
    without the tab: …"). Checked end to end in Chromium, Firefox and
    WebKit with a fake webcam (the saved take's frames have the band).
  - **Android and iOS**: burned in after recording, by the platform's
    own video tools over the method channel `tabcam/take_overlay`
    (`burn`: the take, an output path, and the bands with their times
    in ms): Media3 Transformer with an `OverlayEffect`
    ([`TakeOverlay.kt`](../tabcam_app/android/app/src/main/kotlin/com/nu01/tabcam/TakeOverlay.kt))
    on Android; an `AVMutableVideoComposition` with Core Animation
    layers ([`AppDelegate.swift`](../tabcam_app/ios/Runner/AppDelegate.swift))
    on iOS. The take comes out upright, as it showed, as H.264 and AAC
    in MP4. "Adding the tab to the video…" shows meanwhile. If it
    fails, the take is saved as recorded and a message says it was
    saved without the tab, and why ("The take was saved without the
    tab: …").
  - A capture with no text tab records the camera alone.
- **Play** plays the last take of this visit back in the camera's place,
  until **Stop** or its end; the necklines under it turn where they
  turned while it was recorded (the take has the tab in it too).

<a id="playing-along-with-a-file"></a>**Playing along with a file**:
when the capture has recordings, videos or links, Cam opens with a
sidebar on the right (40% of the screen's width, from 120 to 280 px):
at its top a compact **player frame**, always there, with the first of
them loaded in it, paused (`BackingTrack`,
[`backing_track.dart`](../tabcam_app/lib/capture/backing_track.dart)),
and under it the list of them in the capture's order (its takes too),
each with its icon and name; the list scrolls, the frame stays.
**Play along** (♫ in the app bar, in the primary colour while open)
hides and shows the sidebar, frame and all; hiding it pauses what plays
(kept offstage, so a link's page isn't reloaded). A capture with none of
them has no sidebar and no ♫. A tap on one plays it in the frame, taking
the place of the one before; a tap on the one in the frame pauses or
plays it. The user plays along, and records as usual: Rec doesn't stop
it, so the microphone records it too (iOS mixes its sound with the
recording's: `mixWithOthers`).

- **The frame**, as wide as the sidebar and at most a third of the
  screen's height: a video (or a link's page, 16:9) above a progress bar
  to scrub; a recording only the progress bar; under them its icon and
  name in small type, then **Play** / **Pause** and **Stop** (pauses
  it, back at its start). It has no Close: something is always loaded.
  The one in the frame is marked in the list.
- **The space bar** pauses and plays it while the sidebar shows (a key
  down; held, it doesn't repeat), and doesn't turn the tab; with the
  sidebar hidden, space turns the tab again. A tap in the sidebar or the
  frame gives the keys back to Cam.
- **A link** straight to a sound or video file (its path ends in `.mp3`,
  `.m4a`, `.aac`, `.wav`, `.ogg`, `.oga`, `.opus`, `.flac`, `.mp4`,
  `.m4v`, `.mov` or `.webm`) plays in the app like a recording or video.
  Any other link shows in the frame
  ([`link_frame.dart`](../tabcam_app/lib/capture/link_frame.dart)):
  - **A YouTube video** in YouTube's embedded player (privacy-enhanced,
    `youtube-nocookie.com/embed/<id>`, with its iframe API on, autoplay
    off when it opens paused with Cam), told to play, pause and stop by
    the iframe API's messages (`playVideo`, `pauseVideo`; stop is
    `pauseVideo` then `seekTo` 0). On Android and iOS it's in a web view
    (`webview_flutter`), in a page of its own from
    `https://tabcam.nu01.com/` (YouTube wants to know the site that
    embeds it), with media playing inline and without a tap first; on
    the web, an iframe.
  - **Another page**: on Android and iOS loaded in the web view, its
    first `<video>` or `<audio>` played and paused by the space bar
    (and paused once the page loads, when it opens paused); on the web
    in an iframe, which another site's page can't be told to play,
    pause or stop (no Play / Pause or Stop), and which some sites
    refuse to be shown in.
  - A click inside the frame gives it the keyboard (on the web, the
    page in it gets the space bar) until the user taps Cam again.
- **Play** (the last take) pauses it first. Leaving Cam stops it.

On a capture shared with the user to read, each take goes to their own
[contribution](contributions.md), named among its takes. Cam is off on a
capture opened by its link (a take couldn't be saved there), and while a
tool works. Opening it stops what
plays in the list.

**Permissions**: the camera and the microphone (iOS:
`NSCameraUsageDescription`, `NSMicrophoneUsageDescription`; Android: the
`camera` plugin's `CAMERA` and `RECORD_AUDIO`; the web: the browser's
prompt). On the web a take is WebM, on Android MP4, on iOS MOV.
