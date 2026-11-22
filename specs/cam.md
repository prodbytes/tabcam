# Cam: playing along

**Cam**, a tool on the [event screen](event-screen.md), lets a guitarist
record themselves playing along with the capture's tab. It's tabs.cam
Premium's ([cloud OCR](cloud-ocr.md#in-the-app)): without Premium it opens
as a **preview** (`PlayAlongScreen` with `gate` set): no camera is opened
(a camera icon where the preview would be), no key, nod or tap does
anything, Rec and Play are dead, the tab under the camera is the
capture's or a made-up sample, and the Premium card lies over it all,
its **Not now** leaving. With Premium it opens the camera
([`PlayAlongScreen`](../tabcam_app/lib/capture/play_along_screen.dart)).
The [video editor](video-edit.md#rec-over-this)'s **Rec over this**
(Premium's too) turns the editor into Cam on the video it edits: the
camera in its place, the video playing along in the main row as a file
picked in the sidebar does (as it is, not as edited), so a take
recorded there has it as its song; Back puts the edit back.

<a id="cams-view"></a>**Cam's view is the video editor's**: one widget,
`StudioView`
([`video_edit_screen.dart`](../tabcam_app/lib/screens/video_edit_screen.dart),
Cam's parts in
[`video_edit_cam.dart`](../tabcam_app/lib/screens/video_edit_cam.dart)),
one frame whatever is in its **main row**: in Cam the camera, in its
place, where the [video editor](video-edit.md#in-cam) has the video it
edits; `PlayAlongScreen` builds it with the camera, `VideoEditScreen`
with a page. A [`CamSession`](../tabcam_app/lib/capture/cam_session.dart)
does what Cam does (the camera, the head gestures, the tab and
auto-pass, the microphone and its volume, the takes and their Play), and
the view shows it with the widgets in
[`cam_controls.dart`](../tabcam_app/lib/capture/cam_controls.dart).

- **The frame**, as the editor's: **the viewer** at the top, the camera
  (`CamView`) on black with the tab's phrase under it (`CamPhrase`); the
  play-along, dictionary and metronome sidebars at the right, the
  body's whole height; and docked at the bottom, the viewer's width, on
  the theme's surface colour, **Cam's controls** (`CamStrip`: Rec with
  its microphone's menu and level meter, Play, Tab and Auto-pass) over
  **the ruler and the rows**: the main row ([below](#the-main-row)) and
  under it the take's ([below](#the-takes-row)). The controls
  always show, and the phrase wherever it fits, the camera taking the
  room that's left, however little; the rows come after them, as many
  as leave the camera at least 160 points under the phrase (the main
  row first, then the take's), and none while
  the on-screen keyboard is open (the dictionary's search typed in). So
  in a window too short for it all the rows give way first, and the
  phrase only in one too short for the phrase itself (six strings at the
  largest text on a phone on its side); a phone on its side has the
  camera, the phrase (all six strings of a guitar's) and the controls,
  without the rows. Hiding the tab (**Tab**) gives its room to the rows.
  The rows also give way where their bar would be narrower than 120
  points: on a phone beside the play-along sidebar (open by default,
  half the screen's width), whose player has the same song; with the
  sidebar hidden, they show. The app bar is in the theme's colours; the
  viewer stays black.
- **The camera**, the **front** one first (it faces the player); **Flip
  camera** in the app bar moves to the next one (not while recording).
  The app bar has the capture's title, and first of its buttons
  **Dictionary** (a book icon, in the preview too), which shows the
  chord and scale [dictionary](dictionary.md) in a sidebar on the right,
  the view beside it (or, turned by its Rotate button, in a panel under
  it); typing in it doesn't move the tab, and once it's hidden the keys
  move the tab again. **Metronome** (a stopwatch icon) after it opens
  the [metronome](metronome.md)'s sidebar the same way. Then **Play
  along** (♫, [below](#playing-along-with-a-file); not in the preview),
  the keyboard button ([keyboard shortcuts](keyboard-shortcuts.md)),
  head gestures ([below](#head-gestures)) and Flip camera. Without a
  camera, or one that isn't allowed, the view says so.
  [A camera that won't start](#a-camera-that-wont-start) gives way to the
  next one.
- **The tab**, under the camera, one **phrase** at a time: a staff
  (a run of string lines) with the lines right above it, such as chord
  names and a section name (a neckline, in the code:
  [`necklines`](../tabcam_app/lib/recognition/necklines.dart)). Text
  that isn't over a staff (lyrics under it, notes at the end) is left
  out; a tab with no string lines at all (chords only) shows its
  blocks between blank lines. A file's divider, in a tab read from
  several files ([several files](tab-recognition.md#several-files)), is
  in no phrase: it ends a staff as a blank line does. The phrase is in the monospace font,
  shrunk to fit the viewer's width (a long staff reads best with the
  phone turned sideways), with its number under it ("2 / 14"). A
  capture with no text tab yet says to read it first.
- **Moving along the tab**: any key (but **/** and **.**, which are
  [a new take](#new-take-key), **H**, which shows the
  [keyboard shortcuts](keyboard-shortcuts.md), and the space bar, **1**, 0, ← and →
  while a file [plays along](#playing-along-with-a-file)) goes to the
  next phrase (a keyboard, or a Bluetooth page-turner pedal), **↓**
  among them; **Backspace**, **↑** and **Page Up** go to the one
  before, and so does **←** while nothing plays along. Shift, Control, Alt,
  Meta, Caps Lock, Fn and Escape pressed alone do nothing. A tap on the
  phrase goes to the next; the arrows beside it (**Previous line**,
  **Next line**) to either side. It stops at the first and the last.
- <a id="head-gestures"></a>**Head gestures** (Android, iOS and the web): a nod
  **up**, or a turn of the head to the user's **right**, goes to the next
  phrase; a nod **down** or a turn to the **left**, to the one before
  ([`head_gestures.dart`](../tabcam_app/lib/capture/head_gestures.dart)).
  Only a strong, deliberate gesture counts, so playing doesn't turn the
  tab: the head must move at least 20° up or down, or 25° sideways, from
  where it rests, and come back to rest (within 8°) within a second; the
  strongest direction wins. Held away longer, such as looking down at
  the fretboard, it's no gesture, and after 3 s there the head rests
  there. After a gesture, the next waits 0.8 s. On Android and iOS the
  camera's frames (about 10 a second; about 7 while a take records, see
  [Recording comes first](#recording-comes-first)) go to ML
  Kit's face detector (`google_mlkit_face_detection`, accurate mode, on
  the device, the nearest face); its angles never leave the phone.
  - **On the web** ([`web_head_tracker.dart`](../tabcam_app/lib/capture/web_head_tracker.dart),
    behind a conditional import, so Android and iOS don't build it), the
    browser's camera streams no frames to the app, so MediaPipe Tasks
    Vision's **Face Landmarker** reads the camera preview's own `<video>`
    itself, about 10 times a second (about 7 while a take records), one
    detection at a time (`detectForVideo`, `VIDEO` mode, one face, the facial
    transformation matrix on). camera_web gives that element no id or
    class, so the tracker looks for a `<video>` playing a live camera
    `MediaStream` (`srcObject`), one inside Flutter's
    `<flt-platform-view>` first, and looks again when the camera
    changes; no second camera stream is opened. The library
    (`@mediapipe/tasks-vision@0.10.21`, its WebAssembly from the same
    jsDelivr path) and the model (`face_landmarker.task`, float16 v1,
    from Google's `storage.googleapis.com/mediapipe-models`) load only
    once head gestures are switched on, with the GPU, or the CPU if
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

  They're **off when Cam opens** (each time: the choice isn't kept). A
  face icon in the app bar switches them on and off, in the theme's
  primary colour while it sees a face; off (struck through), nothing
  watches for faces and the camera streams no frames for them. While a take plays back, gestures do nothing.
- **Rec** records video and sound (`camera`, `ResolutionPreset.high`)
  from the phrase showing, until **Stop**, the sound first
  ([Recording comes first](#recording-comes-first)).
  <a id="rec-key"></a>Rec has no key of its own: **.** starts a take
  with the sidebar's song back at its start, and **/** one with the
  song where it is, as Rec does ([a new take](#new-take-key)); Stop is
  the button (or / and ., which start the next take). **1** is the
  song's play / pause, as the space bar
  ([the keys in every screen](#keys-in-every-screen)); until 2026-11-17
  it was Rec / Stop. Either, pausing the song while a take records,
  stops the take too ([below](#space-stops-take)). The button's tooltip names the keys: "Rec (.)",
  and "Stop · new take (/) · redo (.)" while recording, in English,
  Spanish and Portuguese. The take is then added to
  the capture as a video, at the end of its files, named by **the time
  it started** (Rec, / or . pressed), in hours and minutes, 24-hour:
  "Take 14:32" (Spanish "Toma 14:32"; `takeName`). The date isn't in the
  name: the sidebar lists the takes under their day. Takes started in
  the same minute share the name, nothing more is added (until
  2026-11-17 the seconds, then a number, were: "Take 14:32:07", "Take
  14:32:07 (2)"; takes named so keep their names). Takes saved before
  were named "Take 1", "Take 2"… and keep their names. While it
  records, and once it's added, the [take's row](#the-takes-row) under
  the main row shows it. A message says
  the take was added. It
  is marked as a take (`take` on its page, `EventPage.take`), which
  stays when it's renamed, edited, cloned or published, so the
  play-along sidebar lists it with the [takes](#playing-along-with-a-file).
  It syncs as any video does (the mark with it, as its name does). It
  also keeps a **log** of what Cam noted while it recorded (the tab's
  turns and how far the file started before them, see
  [What a take keeps](#what-a-take-keeps)).
  Going back while recording stops it and keeps the take. Back on the capture, its takes show: the file list
  (not the Text view), scrolled to its end.
  <a id="new-take-key"></a>Two keys start **a new take** while
  recording, the take recorded so far either kept or thrown away:
  - **/** (on the main keyboard or the keypad) **cuts**: the take is
    stopped and saved as Stop saves it (added, named, its phrase passes
    kept, the message shown), and once it's saved, the next take starts
    as Rec starts one. Both takes are in the capture, one ending and the
    other starting where / was pressed. The song in the sidebar (when it
    shows) **pauses where it is** at the cut, rather than playing on
    while the take is saved (which can take seconds: on iOS the take is
    made H.264), so the next take misses none of it: once the next take
    records, it plays on from there after the take's
    [count-in](#count-in), and the next take's log notes it from there
    ([the editor](video-edit.md#a-takes-song-lined-up) lines it up
    there). Paused before, it stays paused until the next take starts
    it, as Rec does.
  - **.** (on the main keyboard or the keypad's decimal key, also where
    that key types "," as on Brazilian, German and most European layouts,
    matched by where it is on the keyboard; the comma key itself turns
    the tab) **starts over**: the song in the sidebar (when it shows)
    stops at once and goes back to its start (its section's, with one
    chosen), so it's silent while the take is thrown away; the take is
    stopped and not saved (nothing added to the capture, nothing synced,
    its file deleted from the device; on Android the app's sound for it
    is dropped, not put into the video), a message says "Take thrown
    away: recording it again", and the next take starts as Rec starts
    one, the song with it from its start, after the take's count-in.
    Pressed again and again, only the last take is kept, once it's
    stopped (Stop or /). A take saved before is never touched: . only
    throws away the one recording.

  The tab stays at the phrase showing, as with Rec (auto-pass turns it
  along the song, as ever). Not recording, **/** starts a take as Rec
  does (the song playing on, or started from where it is), and **.**
  starts one with the song back at its start. They act on the key down
  only (held, they don't repeat), do nothing while Rec can't be pressed,
  and with Ctrl, ⌘ or Alt they turn the tab as any key. While the take
  is saved (or thrown away) for the next, Rec, Play, the camera switch,
  /, . and going back do nothing, so a second press can't start or stop
  another take (the camera records one at a time). Nor do Rec, / and .
  while a take starts (until the camera records), so pressing again at
  once doesn't start a second recording alongside it. If the next take
  can't start after /, the one saved is kept and a message says why.
- <a id="rec-menu"></a>**Rec's menu: the microphone.** An arrow beside
  Rec (its tooltip "Microphone") opens a menu, as a video call's
  microphone button does: under **Record from**, **Default microphone**
  (the system's choice) and the microphones takes can record from, the
  one they record from checked. Picking another opens it at once, for
  the takes from now on, and Cam keeps it on the device (`mic` in the
  `cam` meta file, beside Auto-pass), so it opens from it the next time
  (before any take: the microphone is opened from it as Cam opens). One
  that won't open (unplugged, say) leaves the default open, so takes
  still have their sound: picked, "Couldn't open …: takes record from
  the default microphone." says so, and the default is what's chosen
  and kept; kept from before and not connected,
  Cam opens the default without a word, and the menu checks the default
  (the one kept is tried again the next time). The arrow does nothing
  while a take starts, records, is saved for the next or plays back, nor
  while a microphone opens (it changes takes to come, never one
  recording). In English, Spanish and Portuguese.
  - **Web**: the browser's audio inputs (`enumerateDevices`), named as
    the browser names them ("Microphone 2", by their place in the list,
    when it gives no name, before the microphone is allowed); Chrome's
    own "default" and "communications" entries are left out (the menu's
    Default is the browser's). Picked, the microphone the take recorder
    holds is closed and opened again from that device (`deviceId`
    exact, the same constraints as ever, see
    [Recording comes first](#recording-comes-first)); the device's id is
    what's kept.
  - **Android**: where the app records the takes' sound
    ([Recording comes first](#recording-comes-first)), the phone's
    inputs (`AudioManager.getDevices`): its own microphones ("Phone
    microphone", with where on the phone, such as "(bottom)", when it
    says), wired headsets, USB devices and headsets, and line inputs. Not
    Bluetooth headsets: their microphones are for calls (SCO, 8 or
    16 kHz), and open only with one. Picked, the microphone is opened
    again (the same sources and formats, in turn) with that device
    preferred (`AudioRecord.setPreferredDevice`); should none open from
    it, the system's choice. Kept by its type, name and address (its
    system id changes as it's plugged in again). Where the camera records
    the sound itself (the app's microphone unavailable), there's no
    arrow: the camera plugin takes no choice.
  - **iOS**: the audio session's inputs (`availableInputs`: the
    iPhone's microphone, wired and USB ones; no Bluetooth headsets, which
    the session's category leaves out), named as the system names them.
    Picked, it's the session's preferred input (`setPreferredInput`),
    which the camera records from (its capture session uses the app's
    audio session); its port's UID is what's kept. Set again as Cam
    opens, and back to none when it closes.
  - Checked: the menu, its check, the choice kept and opened first when
    Cam opens again, the message for one that won't open, the arrow
    dead while a take records, and none where the camera records the
    sound (`test/play_along_test.dart`, the web's recorder faked, and
    Android's channel); in Chrome, the recorder opening from the
    device, the default when it won't open, and the list without
    Chrome's own entries (`test/web_take_recorder_test.dart`). The
    Kotlin built (a debug APK) and the Swift type-checked; **not yet on
    a phone**: Android's USB and wired inputs, and iOS's route to the
    camera's sound.
- <a id="level-meter"></a>**The level meter**, left of Rec (in the
  space that keeps Rec over its label), shows how loud the microphone
  is, as a recording program's meter does
  ([`level_meter.dart`](../tabcam_app/lib/capture/level_meter.dart)):
  a column of 12 segments from -60 dBFS to full scale, finer near the
  top (bottom edges -60, -48, -40, -34, -28, -24, -20, -16, -12, -9, -6
  and -3 dBFS), **green** below -18 dBFS, **yellow** from -18 to -6,
  **red** from -6; those not reached are dim. It shows the loudest
  sample since it last asked, about every 40 ms: rising at once,
  falling back 24 dB a second, the highest held for 1.5 s (that segment
  stays lit) before it falls too. It reads between takes as in them, so
  the level can be set before Rec, with the [input
  volume](#input-volume) it opens when tapped. Its tooltip says
  "Microphone level: tap to set the input volume" (English, Spanish,
  Portuguese). It shows where the app reads the
  takes' microphone itself:
  - **Web**: a Web Audio analyser on the take recorder's microphone
    (`WebTakeRecorder.peak`: an `AudioContext`, a
    `MediaStreamAudioSourceNode` and an `AnalyserNode` of 2048 samples,
    never connected to the speakers, made again for another
    microphone and closed with Cam), its latest samples' loudest.
  - **Android**: the app's own microphone ([Recording comes
    first](#recording-comes-first)), over the method channel
    `tabcam/take_level` (`peak`: the loudest since the last `peak`, 0
    to 1; null when it isn't read). In a take, the take's reader notes
    each 20 ms read's loudest sample; between takes (from `prepare`, and
    again as soon as a take's sound has stopped, while it's put into the
    take), a thread of its own (`Monitor`) keeps the microphone recording
    and does the same, the sound let go; it stops before a take starts,
    another microphone is chosen, or Cam closes. So on Android the
    microphone now records the whole time Cam is open (the system's
    microphone indicator shows), as on the web.
  - **None** in the preview, on iOS (the camera records the takes'
    sound, which the app doesn't read), nor on Android where the camera
    records it (the app's microphone unavailable): there the space is
    blank.
  Tested: the ballistics, colours and the meter's asking
  (`test/level_meter_test.dart`), and in Cam on the web (faked recorder)
  and Android (the channel faked), and none where the camera records the
  sound (`test/play_along_test.dart`); `TakeSoundMath.peak` on the JVM.
  **Not yet checked on a phone or in a browser.**
- <a id="input-volume"></a>**Input volume**: the level meter, tapped
  (or clicked), opens a menu by it: "Input volume", the volume in dB
  (+6 dB, 0 dB, −6 dB), an upright slider from −24 to +24 dB in 1 dB
  steps (up louder, down quieter) and **Reset** (back to 0 dB, greyed at
  0 dB). The volume changes as the slider moves, and the meter shows
  the microphone at that volume at once, so it can be set by eye (out
  of the red); it's kept in Cam's settings (`gainDb`, left out at 0 dB)
  and set again each time Cam opens. Only between takes: while a take
  starts or records the meter can't be tapped, and a take keeps the
  volume it started with. Where there's no meter (iOS, the preview,
  Android where the camera records the sound) there's no input volume.
  It's a gain on the sound as read (digital), so it can't undo a
  microphone that clips before the app gets its sound.
  - **Web** (`WebTakeRecorder.setGain`): the meter's Web Audio graph
    gets a `GainNode` between the microphone's source and the analyser.
    At 0 dB a take records the microphone's own track, as before; at
    any other volume it records the gain node's output (a
    `MediaStreamAudioDestinationNode`, two channels), the
    `AudioContext` resumed as Rec is pressed; should the browser hold
    it, the take records the microphone as it comes and says so in the
    log (`TabCam: cam: input volume: …`).
  - **Android**: `gain` on `tabcam/take_level` (`gain`: the factor,
    kept within ±24 dB); the between-takes reader and the take's reader
    multiply each 16-bit sample by it as it's read, clipped at full
    scale (`TakeSoundMath.applyGain`), before the meter or the encoder
    sees it. The app's microphone keeps the last one set until Cam sets
    it again as it opens.
  Tested: the menu (up, down, the dB shown, kept, set as Cam opens,
  Reset, not while recording) with the web's recorder faked and on
  Android with the channel faked (`test/play_along_test.dart`);
  `TakeSoundMath.applyGain` on the JVM. **Not yet checked on a phone or
  in a browser.**
- <a id="the-tab-with-the-take"></a><a id="the-tab-in-the-take"></a>**The tab is kept with the take and
  added by the editor**: a take is saved at once as the camera recorded
  it, with no tab in its picture and no second encode (no "Adding the
  tab…" wait; on iOS, only an HEVC take is encoded again, below). Its
  [log](#what-a-take-keeps) keeps the phrases it showed and when
  each showed (`burned: false`), and the
  [video editor](video-edit.md#layers) draws them over the take, each
  along the bottom of the video while it showed in Cam (a band as wide
  as the video: white monospaced text on a dark, see-through strip,
  `renderBand` in [`edit_layers.dart`](../tabcam_app/lib/capture/edit_layers.dart)):
  in its preview, in the [file screen](event-screen.md#file-screen)'s
  player, and in its Download, where its **Tab** chip turns it off.
  Cam's [Play](#play) turns the phrases along the take from the same
  log. Everywhere else the take is its file as it is, without the tab:
  the file list's play buttons, the play-along sidebar, and the list's
  Download and Download all (and older versions of the app, which don't
  know the log). Nothing is uploaded, and no server is involved.
  - **Web**: the take recorder records the camera preview's own video
    track as it comes, with the microphone's sound
    ([`web_take_recorder.dart`](../tabcam_app/lib/capture/web_take_recorder.dart),
    the browser's `MediaRecorder` on a stream of the two tracks; see
    [Recording comes first](#recording-comes-first)): WebM (VP8, else
    VP9, with Opus), or MP4 where only that records (Safari), the sound
    at 192 kbps and the video at 5 Mbps. Nothing is drawn while it
    records (no canvas, no work per frame), so a take goes on recording
    while the browser's tab is hidden, without frozen frames. Should the
    recorder fail to start, the camera plugin records the take itself,
    with the microphone's sound (its track added to the camera's stream,
    which has none): the same take, so nothing is said. Without a
    microphone (refused, or none) no take starts at all, the camera's
    alone neither: a message says to allow or connect one ("No take
    without its sound: …"). Checked in Chromium with a fake webcam (the
    saved take's frames are the camera's, top to bottom).
  - **Android**: the camera's MP4 (H.264), with the sound the app
    records put in ([Recording comes first](#recording-comes-first)).
  - **iOS**: the camera plugin (camera_avfoundation) writes an MP4 in
    the codec the device recommends. As the take is saved, its codec is
    asked for ([`take_h264.dart`](../tabcam_app/lib/capture/take_h264.dart),
    method channel `tabcam/video_edit`, `codec`: the video track's four
    letters): an H.264 take (`avc1`) is saved as it is; any other (HEVC,
    `hvc1`, which Chrome and Firefox don't play everywhere) is made
    H.264 once (`h264`: the whole take through the editor's renderer,
    nothing drawn on it, its orientation kept, its sound re-encoded to
    AAC; [`AppDelegate.swift`](../tabcam_app/ios/Runner/AppDelegate.swift),
    `TakeH264`), "Saving the take so every browser plays it…" showing
    meanwhile. That costs about what burning the tab in did, and only
    for an HEVC take. Should it fail, the take is saved as recorded and
    a message says why ("The take was saved as the camera recorded it,
    which some browsers can't play: …"). Checked on a Mac, the same
    AVFoundation code in a command-line harness (an H.264 clip told
    `avc1`; an HEVC one told `hvc1` and made `avc1`, as long), and by a
    RunnerTests case (compiled for the simulator, not run there yet);
    **not yet on an iPhone**: which codec it records, and that an HEVC
    take made H.264 plays in Chrome and Firefox after sync.
  - A capture with no text tab records the camera alone, its log
    without a tab.
- <a id="play"></a>**Play** plays the capture's last take back in the camera's place (the
  last of the user's own, on a capture shared to read: their
  contribution's), until **Stop** or its end: the one just recorded, or,
  when Cam opens, the last one recorded before (on this device or
  another); deleted, the one before it. It's the take the
  [take's row](#the-takes-row) shows, whose **Play the take** is this
  Play. Only a take this device can
  play: on iOS a WebM (a take recorded in Chrome or Firefox) is passed
  over for the last one before it that isn't, and with none Play is
  greyed (`takePlaysHere`). A take from another device may still be
  downloading when Play is tapped: until it opens Play shows **Stop**,
  which lets it go (it doesn't play once it arrives), and Rec, 1 and .
  wait, so no take starts with it about to play into it. The phrases under it turn
  where they turned while it was recorded, as its
  [log](#what-a-take-keeps) says (at their times in the file, the lag
  added): a phrase the capture's tab no longer has (its text changed
  since) shows as it was, without the "2 / 5" under it. A tab with the
  same phrase twice (a repeated riff): the take just recorded turns
  to the copy that showed (Cam keeps its lines while it's open, as long
  as the tab doesn't change); one recorded before, whose log keeps the
  text once, to the copy nearest the phrase before, and of two as
  near, the one the way it was going (forward at first), its first
  phrase the first copy (`TakeTab.placesIn`, a guess where the take
  went back and forth over the copies). Stopped, the tab stays at the
  last phrase shown that the capture's tab has. A take
  from before takes had a log turns none (its tab is in its picture).
- **Tab** (beside Rec and Play: **Hide tab** with the tab showing,
  **Show tab** with it hidden) hides the tab under the camera, leaving
  the camera more of the screen, and shows it again. Hidden, it still
  turns (keys, taps, head gestures, a take playing back) and a take's
  log still notes each turn, so the editor draws it where it showed;
  it's only off the screen.
  It shows again each time Cam opens.
- <a id="phrase-passes"></a>**Phrase passes**: while recording with
  [Auto-pass](#auto-pass) on, each
  time the user turns the tab (a key, a tap on the phrase or its
  arrows, a head gesture) with a song playing in the sidebar's
  [player](#playing-along-with-a-file) (one that plays in the app: a
  recording or video of the capture's, or a link straight to a sound or
  video file, not a page in a frame), the song's position is noted, with
  which way it turned (**next** or **previous**) and the phrase it
  turned to ([`PhraseTimes`](../tabcam_app/lib/library/phrase_times.dart),
  `BackingTrack.recordPass`, the position read from the player itself).
  A pass within **two seconds** of one the same way (this time through
  or an earlier one) is merged into it, at their **average** time (each
  pass merged into it counting, so it settles as the song is played
  again), keeping the newer's phrase; one moved within two seconds of
  another the same way merges with it too. Passes are only noted while
  recording, only while the song plays, and only while Auto-pass is on:
  with it **off**, recording notes none, for the song or for the take,
  and the passes there already stay as they are (they're neither
  changed nor deleted). Switched during a take, the turns made while it
  was on are noted and kept, those made while it was off aren't. That
  leaves a **gap** in the passes (the song's and the take's), and
  [Auto-pass](#auto-pass) only knows the passes: through a stretch
  recorded with it off the tab stays on the last pass's phrase, and
  goes straight to the next pass's (however many lines on) when the
  song reaches it; before the first pass it shows the phrase that
  pass turned from, so when the turns before it were made with
  Auto-pass off, that's not the one the take started on.
  - **Per file**: each recording, video or link keeps its own passes,
    at its own times, on the file's own timeline (a video's edit
    doesn't move them: the player plays the file as it is). Two songs
    of a capture, or a song and a take, never share them: recorded
    along one and then another in the same take, each gets the passes
    made while it played, and the player and auto-pass use only the
    passes of the file that plays.
  - **Kept** with the capture, not in the video and not as a file: in
    its `event.json`, as `phrases`, by the song's page ID, the base
    name its file is kept under (`<id>.<extension>`; each pass
    `{"ms", "dir": "next" | "previous", "line", "n"}`), so it syncs and
    clones with the capture, and no list, sidebar or export shows it.
    Not a file of its own beside the song's (`<id>.phrases.json`): page
    files never change once written, so sync and the
    [file cache](cdn.md) need only see which pages a capture has, and
    passes change at every take. On
    a capture shared to read, they go to the user's own
    [contribution](contributions.md) (its `contrib.json`), taking the
    owner's place for them. They're saved when the take is (Stop, or
    leaving Cam), not each pass.
  - **They go with their file**: a file deleted from the capture keeps
    them in the trash (restored, it has them), and they're deleted when
    it's purged ([Deleted and Purge](trash.md)); one deleted from the
    user's contribution, they're deleted with it; a
    clone's copies of the files have their originals' passes, and so
    does a file the owner [publishes](contributions.md#what-the-owner-sees-and-publishes)
    from a contribution (the owner's own for it, else its reader's).
    Passes for a song deleted elsewhere are let go of at the next save.
  - **The take** keeps its own too, from when its phrases showed
    while Auto-pass was on (merged the same way; `takePhrases`), so
    played along later it turns the tab as it turned in it. A turn made
    while Auto-pass was off is still in the take's log (drawn by the
    editor, and followed when Play plays it back), but it's no pass of
    the take's;
    a take recorded with Auto-pass off all along has none.
  - **In the player**: a tick across the song's progress bar at each
    pass (in the theme's primary colour), and at the bar's right end, on
    its line, a **clear** button (a clear-all icon in the same colour,
    "Clear the phrase passes marked on the bar") that drops them all; no
    count is shown. A pass shows on the bar as soon as it's made, while
    the take still records, not only once it's saved. Cleared during a
    take, the marks go at once and the take records on: passes made
    after (Auto-pass on) are noted and marked again, and only those are
    kept. The same frame shows them beside the Text view and
    on the file screen.
- <a id="auto-pass"></a>**Auto-pass** (beside Tab: its icon in the
  primary colour while on, struck through while off; on by default,
  kept on the device in the `cam` meta file, with
  [Rec's menu](#rec-menu)'s microphone): while a song with phrase
  passes plays in the player, Cam turns the tab by itself where they
  are ([`AutoPass`](../tabcam_app/lib/capture/auto_pass.dart)), reading
  the song's position every 100 ms: as the song passes one, the tab
  goes to its phrase. When the song jumps (it starts over at its end
  or its section's with Repeat, «, », a scrub, Play from the start, or
  auto-pass switched on), the tab goes to the phrase the passes show
  there: the last one's before it, or the first one's previous line
  before it. A pass by hand the same way within two seconds after
  auto-pass made one is taken as that pass: it doesn't turn the tab
  again (once; a second one does), and, recording, its time is merged
  into it; one by hand just before a pass is noted as usual, and the
  pass then finds the tab already there. While a take plays back, or
  the song is paused, it does nothing. Off, the tab turns only by
  hand, and no [phrase passes](#phrase-passes) are noted while
  recording (its tooltip says so: "Auto-pass off: the tab turns only
  when you turn it, and no phrase passes are recorded"); the ones
  there already are kept for when it's on again.

<a id="playing-along-with-a-file"></a>**Playing along with a file**:
when the capture has recordings, videos or links (or, in Cam, PDFs to
[follow](#following-a-pdf)), Cam has a sidebar on
the right, open by default: it opens by itself the first time the capture has one, when Cam
opens or when one arrives later (a sync, the first take), and once the
user hides it, it stays hidden. **Its width** is half of the screen's,
from 160 to 360 px, until the user drags its left edge, a separator
(`SplitHandle`, as the PDF pane's): left, wider; right, narrower; from
160 px up to leaving what's beside it 120 px. A double tap on the edge
puts the default back. The width set is the same on every screen with
the sidebar and kept on the device between sessions
([`SidebarWidths`](../tabcam_app/lib/screens/sidebar_widths.dart)).
Dragged narrow, the player's buttons shrink to fit. The
[dictionary](dictionary.md)'s sidebar, open, sits to its right, and is
resizable the same way (turned by its Rotate button, it's a panel under
both instead, its top edge the one to drag). The same sidebar is beside the
[Text view](event-screen.md) (there with a notation sheet at its bottom,
[tab recognition](tab-recognition.md#text-view)) and a PDF or an image
on the [file screen](event-screen.md#file-screen), and a recording
opened there plays in it
(`PlayAlong`, `PlayAlongSidebar`,
[`play_along_sidebar.dart`](../tabcam_app/lib/capture/play_along_sidebar.dart)).
At its top a compact **player frame**, there whenever there's something
to play, with the first of them loaded in it, paused (`BackingTrack`,
[`backing_track.dart`](../tabcam_app/lib/capture/backing_track.dart)):
a song to play along with, not one of Cam's takes, unless there's
nothing else (then the most recent take); on the file screen, the recording
opened, take or not. Under it the list: the [text tab](#following-the-text)
first, if listed; then the files to play along in the capture's order,
under **Play along**, each with its icon and name; then the
[PDFs](#following-a-pdf) or pages to follow; and **last, Cam's takes**,
under **Takes** (Spanish **Tomas**), **the most recent first** (the
reverse of the order they were made), **grouped by day**: each day's
takes under a small heading of their own, **Today** (Spanish **Hoy**,
Portuguese **Hoje**), **Yesterday** (**Ayer**, **Ontem**), else the
date in the app's language, weekday, month and day ("Sat, Nov 14"),
with the year when it isn't this one ("Wed, Dec 31, 2025";
`dayLabel`). The day is when the take was saved, read from its page's
ID, which is the time it was made in microseconds (`timeOfId`), so
takes saved before this grouping are grouped too; one whose ID isn't a
time (none Cam makes) is listed without a day heading, where it falls
(`takesByDay`). A take copied into another capture gets a new ID, so
it's listed under the day it was copied. Takes are played along as the
others are. A take is one Cam marked as such (renamed, it still is
one), or, saved before takes were marked, a video named as Cam names
them in any of the app's languages, by number or by time ("Take 3",
"Toma 3", "Take 14:32"; `isTake`). On a capture
shared to read, the reader's own files (their
[contribution](contributions.md)'s, their takes among them) are listed
too, after the capture's (their takes under **Takes**, above the
capture's, theirs being the more recent), but not one published (the
capture's copy is listed) (`PlayAlong.filesOf`). Each file's row ends
in [Delete](#deleting-from-the-sidebar). The list
scrolls, the frame stays.
**Play along** (♫ in the app bar, in the primary colour while open)
hides and shows the sidebar, frame and all; hiding it pauses what plays
(kept offstage, so a link's page isn't reloaded). A capture with none of
them has no sidebar and no ♫, unless it has a text tab: then ♫ is
there, and the sidebar, opened with it, lists the text to
[follow](#following-the-text) (the text alone doesn't open it by
itself). A tap on one plays it in the frame, taking
the place of the one before; a tap on the one in the frame pauses or
plays it. The user plays along, and records as usual: Rec doesn't stop
it, so the microphone records it too (iOS mixes its sound with the
recording's: `mixWithOthers`). **Rec starts it**: with the sidebar
showing and the one in the frame not playing, Rec plays it as Play
would, from where it is (or from its start, its section's, at its
end), once the take is recording, after the take's
[count-in](#count-in), which a take always has, the count-in switched
off or not; a count-in under way as Rec is pressed counts again from
the take's start, so every take opens with its 2 seconds before the
song (`BackingTrack.playWithTake`). One that plays already plays on,
and with the sidebar hidden nothing starts. Stop (the take's) leaves it playing. While the take records,
its [log](#what-a-take-keeps) notes where the song played (paused,
skipped or started over too), so the [editor](video-edit.md#a-takes-song-lined-up)
opens the take with the song already lined up: nothing to sync by hand.

<a id="the-main-row"></a>**The main row** ("Song", in the dock under
the ruler) is the file playing along, as the editor's main row is the
video it edits: the file chosen in the sidebar (or loaded in its player
by itself) fills it, in place of the one before, and plays through the
sidebar's player (`BackingTrack`), the same one, so its count-in,
section, speed, Repeat, phrase passes and keys are the player's, never
doubled; the sidebar's player stays, the same song's picture and
controls. The row's header has **Play the song** / **Pause the song**
(Pause while it counts in too), as the player's Play. Its bar, as long
as the ruler (the file's length), has the file's name, the part played
filled (the primary colour; red while a take records) and the section,
where one is set, outlined in the tertiary colour; the ruler's playhead
follows the player. A tap on the bar or the ruler takes the player
there, and a drag along them follows (at most every 150 ms, the last
where it's let go), kept within the section where one is set
(`BackingTrack.seek`); the ruler zooms as the editor's. A link in a
frame, which can't be taken to a time, is its name on a dashed bar; a
file still loading, its name alone. With nothing loaded where the
capture has a file that plays, the row is a dashed **Play along with a
song…**, which opens the sidebar with its first file loaded, paused
(`PlayAlong.show`); with nothing in the capture that plays (only a PDF
to follow, say) there's no row. In English, Spanish and Portuguese.

<a id="the-takes-row"></a>**The take's row**, under the main row (the
main row first, as the opened one is in the editor), is the take, in
`StudioView`'s `_recRow`
([`video_edit_cam.dart`](../tabcam_app/lib/screens/video_edit_cam.dart)):
- **While a take records** (from Rec, / or ., and on while it's saved
  and the next one starts after / and ., so the row doesn't go back to
  the take before meanwhile), the row is red. Its header says how long
  the take has recorded, "● 0:12" (`CamSession.elapsed`, told every
  quarter of a second while a take records and only then; only the dock
  is built again for it, never the camera's preview). Its bar, on the
  ruler's axis (the main row's song), has a block for each part of the
  song that has played in the take so far, as the take's log notes it
  (`SongNotes.soFar`, `songSpansOn` in
  [`take_log.dart`](../tabcam_app/lib/capture/take_log.dart)): it grows
  as the song plays; paused, it stops growing while the take goes on;
  moved on meanwhile (a tap on the main row, »), the song plays on in a
  block of its own after a gap; started over (its section, Repeat, 0),
  a block over the part played before, each block with a line where it
  starts. With nothing with a time in the main row (no file
  loaded, or nothing in the capture to play, a link in a frame, a file
  still loading), the ruler is the take's clock, rounded up to the next
  30 seconds (0:30, then 1:00, and so on), the take one block from its
  start and the playhead at its end.
- **After it** the row is the take saved: its name in its header ("Take
  10:01", or as it's renamed since), which opens **Play the take**
  (Cam's Play: the take in the camera's place, its phrases turning as
  they did; **Stop the take** while it plays) and **Edit the take** (the
  take in the camera's place, as the sidebar's
  [Edit](#editing-a-take-from-the-sidebar) opens it; Back puts the
  camera back and the row with it). Its bar, in the theme's secondary
  colour, has its blocks where it played along the main row's song, from
  its log (`TakeLog.song`). Recorded with nothing with a time in the
  main row, it stays on the take's clock, as long as it recorded. One
  that didn't play along the song in the main row (another song chosen
  since, the take itself chosen there, none) is its name on a dashed
  bar, unplaced.
- **Opened again**, Cam's row is the capture's last take (the one Play
  plays back), placed the same way from its log, or unplaced; one from
  before Cam opened has no length known, so with nothing with a time in
  the main row it's unplaced too.
- The next take replaces it. There's none before the first take, nor
  in the Premium preview. In English, Spanish and Portuguese.

The row is only what's shown: a take is the same page as before, saved,
logged and lined up the same way ([What a take keeps](#what-a-take-keeps)).

<a id="deleting-from-the-sidebar"></a>**Deleting from the sidebar**: each
file in it (the recordings, videos and links, Cam's takes among them,
and the PDFs and pages to [follow](#following-a-pdf); not the text tab)
has **Delete** (a bin; its tooltip "Delete <name>") at the right end of
its row, after its mark (playing, or followed). It's the capture's
list's [Delete file](event-screen.md), from the same code (`deleteFile`,
`mayDeleteFile`,
[`file_delete.dart`](../tabcam_app/lib/screens/file_delete.dart)): it
asks "Delete "<name>"?" (Cancel, Delete, and **Don't ask again**) in the
app's shared [delete confirm](delete-confirms.md), as the list's
"file" kind for one of the capture's files and its "contribution" kind
for one of a reader's own, so a Don't ask again ticked in either place
holds in both; the capture's last file deletes the capture with it, once the user confirms ("Delete "<capture>"?", saying "<file>" is its only file, so the capture goes with it, to Deleted: the capture's own Delete confirmation, its Don't ask again included), to the trash as Home's Delete does, with Undo, and the app goes back to Home; on a capture shared with the user to edit, which only its owner deletes, the last file stays ("A shared capture keeps at least one file…") (a take that's its capture's only file, as a
capture of one video recorded into, deletes the capture and leaves
Cam; until 2026-11-18 it couldn't be deleted at all, "An event keeps at
least one page"), and a failure shows "Couldn't delete". It shows only where the list would
offer it: on the user's own captures and those shared with them to
edit, on every file; on a capture shared to read, on none of the
owner's, only on the reader's own (their takes, listed after the
capture's files and under **Takes**), which it deletes from their
[contribution](contributions.md), file and all. A capture's file it
deletes goes to the capture's trash ([Deleted and Purge](trash.md)). Not in Cam's Premium
preview, nor on a capture opened by its link. It's greyed while a take
records, saves (with "/" or ".", until the next take has started) or plays
back, and while the screen works. Once deleted, the file loaded in the
player (playing or paused) is let go of: it stops and the frame closes,
nothing else loading by itself; a PDF or page followed closes its pane;
the take Cam's Play would play back gone, Play is greyed. Beside the
Text view, a recording the capture's list was playing (it plays on in
the Text view) stops too, as the list's Delete stops it, and the delete
shows in the screen's progress bar, as the list's does. A file
deleted anywhere else (the list, a sync) is let go of the same way. On
the [file screen](event-screen.md#file-screen), the file it shows (a
recording, listed in its own sidebar) has no Delete there: the screen's
own Delete deletes it and goes back to the list.

<a id="editing-a-take-from-the-sidebar"></a>**Editing a take from the
sidebar**: each of Cam's takes in it (under **Takes**; not the songs,
videos that aren't takes, links, PDFs or pages) has **Edit** (scissors,
as the file screen's; its tooltip "Edit <name>") right before its
Delete; the [take's row](#the-takes-row)'s **Edit the take** is the
same for the last take. Either pauses what played along first (right
after Stop the song plays on), so only the editor's preview sounds
([`_editTake`](../tabcam_app/lib/screens/video_edit_screen.dart)).
**In Cam** it opens the
[video editor](video-edit.md#in-cam) on that take **in Cam's own view**,
in the camera's place, with no screen pushed over Cam
([Cam's view](#cams-view)): the take in the viewer with its tab, title
and watermark, the editor's transport, its rows (Take, then the song
lined up) and the cut's steps in the dock, the Download settings, and
the editor's app bar (Reset, Download, Download settings, Dictionary,
Metronome, Play along, Share, the keyboard button, About; on a phone
[Rec over this](video-edit.md#rec-over-this), Dictionary, Metronome,
Play along, Share and About in its More menu), with **Back** at its
start. The take's edit is as it was left, its
song lined up, the same edit as on its file screen. The keys are the
editor's ([keyboard shortcuts](keyboard-shortcuts.md)): the space bar
plays its preview; Cam's (/, ., the tab's) and the player's (1, 0)
do nothing. The sidebar stays at the right, the take edited without
Edit or Delete (nor has any page Back is still to bring back, such as
the one [Rec over this](video-edit.md#rec-over-this) left); another
take's Edit takes its place in the main row
(the first's edit kept). The song in the take's Song row, deleted in
the sidebar, leaves the row first, as its Remove does: its player lets
go of the file, the take is its only row, and the edit kept no longer
names it. The camera stays open behind the editor, hidden, its head
gestures pause (no frame goes to them), and the metronome plays on. In
a browser the preview's `<video>` stays in the page and plays on
meanwhile, only not drawn (Flutter takes its platform view out of the
picture, not out of the page), so after Back it shows live at once and
the head tracker reads it again. **Back** keeps the edit and puts the
camera back, the song in the main row as it was, its gestures watching
again, Cam's keys back; a file tapped in the sidebar does the same,
then plays in the main row.
On a phone, where the sidebar would leave the editor narrower than 360
points, or on its side, too narrow for the Download settings beside
the viewer, the Edit hides the sidebar, and it shows again with the
camera. During a download (the editor's), Back does nothing and the
sidebar takes no taps. **Beside the Text view** and on a recording's
**file screen** it opens the editor over the screen, exactly as
**Edit** on the take's own [file screen](event-screen.md#file-screen)
does (the same call, `VideoEditScreen.open`, with the same Premium
service for the watermark); there the recording the capture's list was
playing stops (beside the Text view), or the file the screen shows is
let go of meanwhile (the file screen), so only the editor's preview
sounds, and back, the screen is as it was. It shows where the file
screen would offer Edit: on the capture's own takes, in a capture that
isn't read only (none on one shared to read, nor on a reader's own
contribution's takes); not in Cam's Premium preview, nor on a capture
opened by its link. It's greyed when Delete is: while a take records,
saves or plays back, and while the screen works.

<a id="following-a-pdf"></a>**Following a PDF**: in Cam and in the
[Text view](tab-recognition.md#text-view) (not beside a PDF), the
sidebar also lists the capture's PDFs, under **Follow a PDF** (after the
files to play along and before Cam's takes, with a PDF icon; the capture's photos aren't
listed), so the guitarist can read the tab from the page itself when the
text tab is still wrong. A tap on one opens a **PDF pane** on the **left** of the
camera (`PlayAlong.followed`, `_FollowPane`; 40% of the screen's width, from 160
to 480 px, so the page reads), with a **separator** between it and the
camera (`SplitHandle`, a line with a grip, 12 px wide to take a finger,
a resize cursor on a computer): dragged right, the PDF gets wider and the
camera smaller, down to 120 px; dragged left, the PDF down to 120 px; a
double tap puts the default width back. The width is kept while Cam is
open, for the next PDF shown too. The pane has the PDF's name and
**Hide the PDF** (✕)
at its top, the document under them, its pages scrolling down, zoomable
by pinching or with its **Zoom in** and **Zoom out** buttons
(`PdfPage`, as the [file screen](event-screen.md#file-screen) shows it).
The one showing is marked in the list (a split icon); tapping it again,
or ✕, hides the pane. Only one PDF shows at a time: tapping another
takes its place. The pane is apart from the sidebar: hiding the sidebar
(♫) keeps the PDF, and the keys and gestures still turn the tab (a tap
in the pane gives the keys back to Cam). A PDF deleted or synced away
while it shows closes the pane. The Text view's sidebar lists PDFs
too; on the file screen, a PDF's and an image's sidebar lists nothing
to follow, and a recording's lists the capture's **images and PDFs**,
under **Follow a page or PDF** (an image shows in the pane
pinch-zoomable, as the file screen shows it; its tooltips say **Show
the page beside it** / **Hide the page**).

<a id="following-the-text"></a>**Following the text**: in Cam and on
the [file screen](event-screen.md#file-screen) (beside a PDF, an image
or a recording), when the capture has a text tab, the sidebar's list
starts with it: **Text tab** (a notes icon), above the files to play
along, the PDFs and pages to follow and the takes (`PlayAlong.withText`,
`PlayAlong.followsText`). A tap shows the text in the same pane on the
left (**Show the text beside it**), as a PDF is followed: its name and
**Hide the text** (✕) at the top, the separator to drag, the width kept
for the next one shown. The text is in the tab's monospaced font, lines
as written (not wrapped, so the strings line up), scrolling down and
across, selectable to copy (`FollowedText`); an edit or a sync shows in
it at once. The pane shows one thing at a time: a PDF or a page tapped
takes the text's place, and the text tapped takes theirs; tapped again,
or ✕, it hides. A text cleared while it shows closes the pane and the
row goes. The Text view's sidebar doesn't list it (the text is the
view).

- **The frame**, as wide as the sidebar and at most a third of the
  screen's height (on a short screen the video shrinks first, so the
  list under it keeps at least two rows): a video (or a link's page, 16:9) above a progress bar
  to scrub (the part played in the theme's **primary colour**, and in
  its **red** while a take records; marked where its [phrase passes](#phrase-passes) are, with
  the button that clears them at the line's right end), the
  [count-in](#count-in) at the start of the progress bar's line; a recording only that line; under them its icon and
  name in small type, then **|◀** (back to the start, as the **0** key,
  below: the file's or its section's, count-in included; "Back to the
  start (0)"), **«** (10 seconds back, not before the
  start), **Play** / **Pause** (Pause while it counts in too), **Stop** (pauses it, back at its start),
  **»** (10 seconds forward) and **Repeat** (on by default, in the
  primary colour while on: at its end it starts over; a recording or
  video loops, a YouTube video is started over when it says it ended, a
  page's first video or sound loops). It has no Close: something is
  always loaded.
- **The section** (a recording or video of the capture's own, not a
  link: a link can't be held to the split second): under the progress
  bar, a range over the whole file whose two ends set the part that
  plays, its times (`Section 0:12.3–0:45.0`, to the tenth of a second,
  in the theme's **secondary colour** once set, as the range is), **|◀** and **▶|** (start or end it
  where it plays now) and, once set, **✕** (play all of it again). While
  **Repeat** is on, and while either end of the range is dragged, the
  section shows over the progress bar too: a band in the secondary colour
  from its start to its end, as high as the bar's line, over the part
  played and under the phrase marks, following a drag (the two
  bars aren't as wide, so the range alone doesn't show where the section
  falls on the progress bar). With Repeat on it stays for as long as the
  section is set, so the part that repeats shows on the bar as it plays;
  with Repeat off it shows only while the range is dragged, gone when
  it's let go. The part played, the band and the range's line are a
  little see-through (all at 75%; the range's ends and its times are
  solid), so where the band and the part played overlap, the part played
  still shows a little under it. While
  one is set the player's own looping is off and its position is checked
  every 100 ms: at the section's end it goes back to the section's
  start, playing on with Repeat, paused without. A section that ends at
  the file's end (or near enough for the player to get there first)
  completes the player, which pauses itself at the end: that counts as
  the section's end too, so with Repeat it starts the section over, and
  without it it's paused at the section's start. Play from outside it
  starts at its start, Stop goes back to its start, « and » stay within
  it. A section is at least half a second long; covering the whole file,
  it's none. Each file keeps its own while the screen is open
  ([`backing_track.dart`](../tabcam_app/lib/capture/backing_track.dart)).
  The one in the frame is marked in the list.
- **The speed** (a recording, video or link playing in the app, not a
  page in a frame): under the section, **Slower** (−) and **Faster**
  (+) either side of a slider from 0.25× to 1.5× in steps of 5 % (each
  button one step, greyed out at the ends), the speed after them
  (`0.75×`, in the primary colour once changed; a tap on it goes back to
  1×) and **Normal speed** (↺, lit once changed), which goes back to 1×
  too. The pitch stays, so a part
  can be learnt slowly (the players keep the pitch: ExoPlayer, AVPlayer
  and the browsers' `playbackRate`). The speed is kept for the next file
  chosen while the screen is open; a section plays at it too.
- <a id="count-in"></a>**The count-in** (what plays in the app: a
  recording, a video, a link straight to a sound or video file; a page
  in a frame plays at once): Play, the space bar or a tap on a file in
  the list waits **2 seconds in silence** before it plays, time to get
  from the keyboard or the screen to the instrument
  (`BackingTrack.countIn`). On by default. It shows at the start of the
  progress bar's line, before the bar: the **Count-in** button (a timer,
  in amber while on; a timer struck through, grey, while off), then,
  while it's on, its seconds in **amber**, not the progress bar's
  colour: `2s` and a short amber bar. While it counts in, the bar fills
  and the seconds count down (`2s`, `1s`), and Play shows Pause: Play
  (or space) again, Pause, Stop, hiding the sidebar or another file
  stop it without playing; turned off meanwhile, it plays at once; **0**
  goes back to the start and counts in again, from the top (below).
  **Starting over counts in too**: at its end with Repeat on (the
  file's, or a section's), it pauses at the start, counts in, and plays
  again, a breath between times through; the player's own looping is
  off meanwhile, and Cam watches the end itself every tenth of a second
  (`BackingTrack._keepInSection`). With the count-in off, it starts
  over at once (the whole file by the player's own looping).
  **While a take records it always counts in** (`BackingTrack.countsIn`),
  at play and at each start over, whatever the setting: the user's
  breath before the song, and a margin that keeps the song's start
  inside the take, after the recording has surely started, so the
  [song can be found in it](#the-song-found-in-the-takes-sound).
  Switched off while a take counts in, it counts on; with the count-in
  off, the seconds show while it counts in for a take. The count-in is
  real time, whatever the speed. The setting is kept on the device (the meta file
  `playalong`, `{"countIn": false}`; until 2026-11-11 it was named
  `play-along`, which the apps' store refuses, so it was never kept there), for Cam, the Text view and the
  file screen alike.
- **The space bar and 1** (on the top row or the keypad) pause and play
  it while the sidebar shows (a key down; held, they don't repeat), and
  don't turn the tab; with the sidebar hidden, they turn the tab again.
  <a id="space-stops-take"></a>Pausing it (playing, or counting in)
  while a take records **stops the take too**, saved as Stop (Rec)
  saves it (`CamSession.keyPaused`, told by `PlayAlongKeys.onKeyPause`);
  until 2026-11-22 the take recorded on. Playing it never starts a take,
  and the frame's own **Pause** button still only pauses the song (the
  take records on). A tap in the sidebar or the frame gives the keys
  back to Cam.
- **0** (on the top row or the keypad) always goes back to the
  beginning: the start of the file, or of its section when one is set,
  count-in included (`BackingTrack.restart`). Paused, it stays paused
  there (Play counts in, as ever). Playing, it starts over as Play
  starts it: with the [count-in](#count-in) on, it goes silent at the
  start, counts the 2 seconds in and plays; with it off, it plays on
  from the start. While it counts in, the count starts over. (A link in
  the frame, which has no count-in, goes back by Stop, then plays again
  if it played.) Like space, it doesn't turn the tab while the sidebar
  shows. Ctrl / ⌘ + 0 is left to the browser (its zoom). The frame's
  **|◀** button does the same, the one `BackingTrack.restart` both call.
- **← and →** go 10 seconds back and on in it, as « and » do (held,
  again and again), and don't turn the tab while the sidebar shows; the
  tab's phrases go by **↑** (the one before) and **↓** (the next). With
  the sidebar hidden, ← and → turn the tab again. A page-turner pedal
  that sends ← and → skips in the song while the sidebar shows: one
  that sends ↑ / ↓ or Page Up / Page Down turns the tab then.
- <a id="keys-in-every-screen"></a>**The keys in every screen**: **0**,
  **1** and the **space bar** are the player's wherever its sidebar
  shows (Cam, the Text view, a file's screen), without a tap in the
  sidebar first, whatever has the keyboard
  ([`PlayAlongKeys`](../tabcam_app/lib/capture/play_along_sidebar.dart)
  gets the keys before the screen does): 0 goes back to the start, 1
  (on the top row or the keypad) and the space bar pause and play, in
  Cam too (where 1 was [Rec / Stop](#rec-key) until 2026-11-17), and
  **←** and **→** go 10 seconds back and on, as « and » do (held, again
  and again; Alt + ← is left to the browser's Back). Until 2026-11-19
  ← and → did that only in Cam, though the shortcuts listed them on a
  capture's and a file's screens too; with the sidebar hidden, in Cam
  ← still turns the tab back.
  Ctrl / ⌘ + 1 is left to the browser (its first tab). The exceptions:
  typing in a field (the Text view's
  editor, the dictionary's search) still types them, until a tap in the
  sidebar takes the keyboard out of the field; under a dialog, a menu
  or another screen the keys are that one's; with the sidebar hidden
  they're the screen's own; while a take is edited in Cam's view, in the
  camera's place, they're the editor's
  ([editing a take](#editing-a-take-from-the-sidebar)); and a Cam
  preview has no keys.
- **A link** straight to a sound or video file (its path ends in `.mp3`,
  `.m4a`, `.aac`, `.wav`, `.ogg`, `.oga`, `.opus`, `.flac`, `.mp4`,
  `.m4v`, `.mov` or `.webm`) plays in the app like a recording or video.
  Any other link shows in the frame
  ([`link_frame.dart`](../tabcam_app/lib/capture/link_frame.dart)):
  - **A YouTube video** in YouTube's embedded player (privacy-enhanced,
    `youtube-nocookie.com/embed/<id>`, with its iframe API on, autoplay
    off when it opens paused with Cam), told to play, pause and stop by
    the iframe API's messages (`playVideo`, `pauseVideo`; stop is
    `pauseVideo` then `seekTo` 0). Asked to (`listening`), it says its
    current time, from which « and » `seekTo` 10 seconds back or on, and
    when it ends, for Repeat. On Android and iOS it's in a web view
    (`webview_flutter`), in a page of its own from
    `https://tabs.cam/` (YouTube wants to know the site that
    embeds it), with media playing inline and without a tap first; on
    the web, an iframe.
  - **Another page**: on Android and iOS loaded in the web view, its
    first `<video>` or `<audio>` played and paused by the space bar,
    moved by « and », looped by Repeat (and paused once the page loads,
    when it opens paused); on the web in an iframe, which another site's
    page can't be told to play, pause or stop (no controls), and which
    some sites refuse to be shown in.
  - A click inside the frame gives it the keyboard (on the web, the
    page in it gets the space bar) until the user taps Cam again.
- **Play** (the last take) pauses it first. Leaving Cam stops it.

On a capture [shared](shared-captures.md) with the user (read only),
Cam opens on their own copy of it instead (their newest, or a
[clone](library.md#events) made then, whose files stay the owner's
until they change), which takes the capture's place on the event
screen, so each take is theirs. Cam is off on a
capture opened by its link (a take couldn't be saved there), and while a
tool works. Opening it stops what
plays in the list.

<a id="what-a-take-keeps"></a>**What a take keeps**: besides its file,
each take Cam saves keeps a **log** of what Cam noted while it recorded,
on its page (`takeLog` in the capture's details, `EventPage.takeLog`,
[`take_log.dart`](../tabcam_app/lib/capture/take_log.dart)), written
once, as the take is saved, and never changed after, but for where its
song was found in its sound (`sync`, below), added once. It notes; it
fixes nothing: what the song played through (`out`) is noted for the
editor, and nothing is moved or corrected as the take records. A log read from
the capture's details is written back exactly as it came, whatever in
it this version doesn't know or can't read included (a newer app's
`lagFrom`, a field in a turn, a segment or the tab, a turn out of
order), so saving the page again here loses nothing of a newer app's;
a clone only renames the pages its `song` segments name. It syncs, is
published and goes into the user's [contribution](contributions.md)
with the page as its name does; a [clone](library.md)'s copy names the
copy's files; renamed or edited, it stays. From it the
[editor](video-edit.md#layers) draws the tab over a take whose tab
isn't in its picture (`burned: false`: every take Cam saves now), in the
preview, the file screen's player and the editor's Download, with its
**Tab** chip to turn it off, and lines the song played along up with
it ([lined up](video-edit.md#a-takes-song-lined-up)).
Play uses it too (above). A few KB for a ten-minute take:
```json
"takeLog": {
  "v": 1, "burned": false,
  "lagMs": 180, "lagFrom": "bounds",
  "lagRaw": {"startCallMs": -240, "startReturnMs": -10,
             "stopCallMs": 61000, "stopReturnMs": 61310, "fileMs": 61420},
  "out": {"route": "bluetooth", "id": "3f9a1c07", "latencyMs": 160,
          "from": "session"},
  "tab": {"lines": ["e|--3--5--7--|", "e|--5--7--8--|"],
          "marks": [[0, 0], [4210, 1], [8380, 0]]},
  "song": [{"at": 2000, "to": 61000, "page": "p3", "from": 0, "speed": 1}],
  "sync": {"v": 1, "page": "p3", "from": "sound", "ms": 38,
           "clips": [{"at": 2000, "ms": 38, "score": 21.4}]}
}
```
- **The tab** (`tab`; none when the capture had no text tab): the
  phrases the take showed (`lines`), each text once, in the order
  first shown, so a later change to the capture's tab changes nothing
  here; and each turn (`marks`: ms on the take's clock, and which of
  `lines`), every one as it came: those made with Auto-pass off, with
  the tab hidden, two at once or back to the same text, the first at 0
  (the phrase it started on). The bands and the take's own
  [phrase passes](#phrase-passes) are worked out from the turns as
  before (`takePhrases`, the passes leaving out the turns made with
  Auto-pass off); the log keeps them all. At most 4000 turns (the
  first).
- **Whether the tab is in its picture** (`burned`): false for every
  take Cam saves now (the tab is kept apart, see
  [the tab and the take](#the-tab-with-the-take)). True on takes saved
  by the versions that put the tab in the picture as they saved it
  (drawn in as the web recorded, or burned in after on Android and
  iOS): the editor draws no tab over those. A log that doesn't say
  counts as burned, so the tab is never drawn twice.
- **The lag** (`lagMs`): how long the file had been recording when the
  take's clock started (the clock starts once the recording has):
  a time on the clock is `lagMs` later in the file (the start staying
  the file's start). `lagFrom` says how it was told:
  - `recorder` (the web): since the browser's recorder was told to
    start (on the page's clock, read as the take's clock starts; the
    recorder's `start` returns once its `start` event says it records,
    at most a second on). The file starts with the first frame after
    the recorder is told to; Chrome sends the event about a tenth of a
    second later, with the file's first frames written already, so the
    lag counted from the event (as it was until 2026-11-17) was that
    much short. Measured in Chromium: a sound made a second after the
    recorder was told to start was in the file 7 to 44 ms later than
    that, and 87 to 143 ms later counted from the event.
  - `bounds` (Android, iOS, and the web's camera recording alone): the
    file's first frame came between the camera being told to start and
    that returning, so the lag is between those two (on the clock,
    before its 0); its last frame between being told to stop and that
    returning, so, with the file's length (its video track's, read from
    the MP4's index, [`mp4_length.dart`](../tabcam_app/lib/capture/mp4_length.dart),
    only the boxes' headers read), the lag is between the length less
    each. The lag is the middle of where both ranges agree; where they
    don't, or the length can't be read (a WebM), the middle of the
    first. Typically within ±100 ms; the editor's nudges and its delay
    control move what's left.
  - `none`: not told, 0.
  The readings it was told from (`lagRaw`, ms on the take's clock) are
  kept, so it can be told again better later; on Android with the app's
  own sound, also `soundLeadMs`, how long before the video's first
  frame the sound began (what was dropped of it as it was put in, the
  stop's reply).
- <a id="what-the-song-played-through"></a>**What the song played
  through** (`out`): the audio output as the take's clock started, read
  without holding the clock back, and read again once the recording
  stopped: `route` (`speaker`, `wired`, `bluetooth`, `usb`, `airplay`,
  `other`, or `unknown`), `id`, a **fingerprint** of the output's name
  (the first 8 hex digits of its SHA-256, `TakeOutput.fingerprint`),
  so one headset is told from another while the name itself, which can
  carry the owner's ("…'s AirPods"), never leaves the device; the
  latency the platform reports for it (`latencyMs`, a hint only), how
  it was told (`from`), and `changed` when the output was another as
  the take stopped (headphones connected or taken off during it). Per
  platform:
  - iOS (`session`): the audio session's current route, its first
    output (`tabcam/audio`, method `output`), and the session's
    `outputLatency` (about 160 ms for AirPods, seconds for AirPlay).
    AVPlayer's position probably allows for most of it already.
  - Android: from 13 on (`media`), the devices media plays through
    (`getAudioDevicesForAttributes`, as video_player's ExoPlayer
    plays); before (`devices`), the outputs connected ranked as the
    system routes media (Bluetooth, wired, USB, the speaker)
    (`tabcam/take_sound`, method `output`; no permission, never the
    device's address). No latency: none is public, and ExoPlayer's
    position already allows for the system's own estimate (the
    headset's delay report on Bluetooth).
  - The web (`browser`): the default output's name as the browser
    gives it (`enumerateDevices`; names come with the microphone
    allowed, which a take has), its route guessed from its words, and
    Web Audio's `outputLatency` where the browser has it (not Safari
    before 18.4), a figure for Web Audio's path, not the video
    element's.
  None of them is applied by Cam or by the editor by itself: the
  [editor](video-edit.md#the-songs-delay) says what the song played
  through under its delay control, and a take through headphones whose
  song wasn't found in its sound opens with the delay kept for that
  output on the device, if one is. Read failing, the take is saved
  without it. None on takes saved before Cam noted it.
- **The song** (`song`): the song played along in the sidebar's
  player, as segments of the take (`at`, `to` on the take's clock; the
  song's page, where in it (`from`, ms) and at what `speed`), noted as
  it records (`SongNotes`, [`take_log.dart`](../tabcam_app/lib/capture/take_log.dart)):
  each time the player changes, where it is; a pause, its end, another
  song, another speed or a jump (where it is more than 300 ms from
  where it would be, playing on: a seek, a skip, Repeat or its section
  starting over) ends a segment, and playing again starts the next. As
  one starts, fresh readings of the player tell again where it started
  (video_player polls its player's position every tenth of a second,
  so the one it has may be that late):
  at once, 0.3 s and 1 s after, each read halfway between asking the
  player and its answer, the last telling it best. A player says it
  plays a little before its sound starts, its position held at the
  start meanwhile; a reading that would put the segment's start before
  the song's start moves the segment's start later instead, to when
  the song's start sounded (it used to stay where the player said it
  played, the song then lined up that much early). Each segment's
  readings tell only that one, not the next (Repeat starting it over
  within the second). A song playing already as Rec is pressed is noted from the
  take's start. At most 2000 segments. `songLink` when a link in a
  frame played (it has no position: no segment). Empty when none
  played, and on takes saved before Cam noted it. The editor lines the
  song up from them ([lined up](video-edit.md#a-takes-song-lined-up)).
  **Bluetooth**: the user plays along with the song as they hear it,
  a Bluetooth speaker's or headphones' delay (a sixth to a third of a
  second) after the player plays it. The players' positions count that
  delay already, as far as the system reports it: Android's ExoPlayer
  from `AudioTrack.getTimestamp` (and the output's latency), iOS's
  AVPlayer and the browsers from the output's reported latency, since
  they keep a video's picture in step with the sound heard. So Cam adds
  no offset of its own for Bluetooth (one would count the delay twice);
  what the system reports wrong (it can be off by tens of ms, and change
  while it plays) is [measured from the take's sound](#the-song-found-in-the-takes-sound)
  when the microphone hears the speaker (600 ms each way is looked in),
  and with headphones (the microphone hears no song) the editor's
  [Delay](video-edit.md#the-songs-delay) corrects it by hand, and can
  keep it for that output ([`out`](#what-the-song-played-through)), so
  the takes through it open with it.
- <a id="the-song-found-in-the-takes-sound"></a>**Where the song really
  is** (`sync`): the segments say where the player was and the lag where
  the file was, each good to a tenth of a second or so; but the take's
  microphone heard the song from the speaker, so where the song is in
  the take can be **measured from the take's own sound**, to the
  millisecond, and the song and the take lined up as well as they can
  be. It's measured on the device, from the two files
  ([`song_sync.dart`](../tabcam_app/lib/capture/song_sync.dart),
  `SongSync`; nothing is uploaded), and kept with the log, the one thing
  added to it after the take is saved (`TakeLog.withSync`,
  `Library.setTakeSync`; a take that has one keeps it):
  - **When**: after Cam saves a take whose log noted a song (once no
    take records: not between the takes the **/** key runs on, which
    are measured when the last one stops, or as Cam closes), and when
    the [editor](video-edit.md#a-takes-song-lined-up) opens a take not
    measured yet (one from before, or from a device that couldn't read
    its files); one take at a time, waiting while a take records
    ([`take_syncer.dart`](../tabcam_app/lib/capture/take_syncer.dart)).
  - **What**: the song the log lines up (the one played longest, at its
    own speed), each of its segments of 3 s or more on its own (the six
    longest): in up to four **windows** of 8 s spread along the segment
    (one every 8 s or so; a segment of 8 s or less, one, from its
    middle), the take's sound in each, 0.6 s more either side, against
    the song's, both mixed to one channel at 8 kHz
    ([`sound_reader.dart`](../tabcam_app/lib/capture/sound_reader.dart):
    Web Audio in the browser, the file decoded whole, a WebM's sound
    put where the file has it start, as a player plays it
    ([`webm_times.dart`](../tabcam_app/lib/capture/webm_times.dart);
    see [video edit](video-edit.md#fades), how it's rendered on the
    web); `MediaExtractor` and `MediaCodec` on Android, each decoded
    buffer placed by its time, `AVAssetReader` on iOS, only the part
    asked for, over the channel `tabcam/video_edit`, method `samples`).
    A sample's time is the sound's in the file as a player plays it.
  - **How**: the two sounds' cross-correlation with each frequency's
    level mostly taken out (GCC-PHAT, 100 Hz to 3.6 kHz), so the match
    is a sharp peak whatever the speaker, the room and the microphone
    did to the song's tone, and the guitar played over it only raises
    the floor. Each window's own best match tells where the song is
    there; a straight line through the clear ones is the **drift**
    between the take's clock and the song player's (some parts per
    million; 300 at most, more being a window's wrong match; logged, not
    kept). Then the windows' correlations, each as a score (its spread
    1), are **added up**, each moved by the drift to the windows'
    middle: the song stands out about √(windows) times more clearly than
    in any one (a song too quiet under the guitar for one window is
    found in four), and where it is is told for the segment's middle,
    off by half the drift at either end. That sum's peak, to a fraction
    of a sample, is how much later (or earlier) than the log says the
    song is: the segment's **shift**, in ms. (Until 2026-11-18 one 12 s
    window from the middle was measured: a song about 4 dB quieter in
    the take is found now, and a drift's error no longer blurs a long
    segment's match.) A match counts when it stands at least 14 times
    the others' spread above them, and 1.3 times higher than the next
    best place a twentieth of a second or more away (a guitar in the
    song's key and time, without the song, stays under 10 or so; music
    with a beat has other places about as good a beat apart, and one of
    two could be the wrong one). The work is done off the screen's
    thread (but on the web, which has one: about a tenth of a second a
    segment).
  - **Kept** as `sync`: the song (`page`), how it was told (`from`:
    `sound`, found; `none`, looked for and not found in any segment,
    as with headphones, or a song too quiet in the take: the log's
    line-up stands, moved by the editor's delay for what the
    headphones added (kept per output, [`out`](#what-the-song-played-through)),
    and it isn't looked for again), the song's shift
    (`ms`: the middle one of its segments'), and each segment measured
    (`clips`: its start on the take's clock, `at`, its own shift, `ms`,
    and how clearly it was found, `score`). A segment is then
    `at + lagMs +` its shift into the file (its own, when it was
    measured, else the song's). Files that can't be read here (a WebM
    on iOS) leave it unmeasured, for another device to try; a way of
    telling this version doesn't know (a newer app's `from`) is kept as
    it came and not used. A clone's names the copy's song.
  - **The editor's Auto-align** ([video edit](video-edit.md#auto-align-how))
    looks the same way, but around where the Song lane has the song now
    (not where the log does), further either side (2 s), with a higher
    bar (16), and, where the song isn't in the take's sound
    (headphones), by the onsets alone (the guitar played in time with
    the song shares its onsets, not its sound; it could be a beat off).
    It moves the lane and writes no `sync`.
- A take without a log (saved before takes had one) has its tab in its
  picture, or never had one. A log dropped by an older app that
  re-saved the page (one from before pages kept the keys they don't
  know) makes a take look like one of those: the editor then draws no
  tab over it, and its file has none.
- Checked: the turns kept unfiltered, the phrases kept once and the
  turns pointing at them, the JSON read back as written (and leniently:
  what isn't as expected is left out), the lag's midpoint for made-up
  timings and the start's range where the two don't agree, the length
  read from a made-up MP4's index, the log saved with a take (never
  burned: the camera's file saved as it is, nothing burned in; the
  web's recorder's lag, the web's camera alone), kept
  through a rename and a restart, a clone's naming its copy's song, a
  newer app's log written back as it came through a rename and a clone,
  Play of an older take after Cam reopens turning its phrases, lag
  and all, and Play of a take on a tab with a phrase twice turning to
  the copy that showed (the one just recorded exactly, an older one by
  the nearest copy), what the song played through noted (Android's,
  iOS's and the web's readings, read as the clock starts and after the
  stop, `changed` when they differ, the name only as its fingerprint, a
  failing read leaving the take saved without it), the sound's lead on
  Android, Rec, 1 and . waiting while the take to play opens
  and Play letting it go, and on iOS Play passing over a WebM
  (`test/take_log_test.dart`, `test/play_along_test.dart`,
  in Chrome `test/web_take_recorder_test.dart`); and the song found in
  the take's sound (`test/song_sync_test.dart`, with made-up riffs: a
  song heard through a made-up room, under a guitar, found to the
  millisecond, earlier or later, each segment its own; not found when
  it isn't there; the sync's JSON, added to a log without changing the
  rest, through a clone; a take in the library measured once, waiting
  while a take records, left for later when its files can't be read;
  Cam asking for it as a take is saved; in Chrome,
  `test/web_sound_reader_test.dart`: files decoded at the rate asked
  for, and the song found in a video the browser recorded as it records
  a take; where a WebM's sound starts, from made-up files
  (`test/webm_times_test.dart`) and, by hand, the same as `ffprobe`
  says for three takes recorded in Chromium (72, 7 and 0 ms);
  Android's way down to 8 kHz by JVM tests, `SampleBinsTest` (written,
  not run: the Gradle test task doesn't start here);
  iOS's reader run on a Mac against a WAV and an AAC file, a tone's
  start read where it is). The Kotlin `output` is built into a debug
  APK and the Swift one type-checked. **Not yet on a phone**: how big
  the log grows, that saving it costs no dropped frames, the song found
  in a real take's sound there (Android's and iOS's readers on a
  phone's own files; how often a real room and guitar leave it
  unfound), and the output read there (Android 13's media route and an
  older phone's ranking, an iPhone's route; how far iOS's reported
  latency is from what's measured).

<a id="recording-comes-first"></a>**Recording comes first**: in a take
the sound matters most, so Cam records it as a musician wants it, sets it
up when Cam opens rather than as the take starts (starting a take changes
nothing the song playing along hears), and makes what else runs wait or
slow down while a take records
([`take_priority.dart`](../tabcam_app/lib/capture/take_priority.dart)).
- **Web**: the camera opens without sound (`enableAudio: false`), and
  the take recorder opens the microphone itself when Cam opens, and keeps
  it open until Cam closes, without the processing meant for voice calls:
  `echoCancellation`, `noiseSuppression`, `autoGainControl` and
  `voiceIsolation` off (echo cancellation takes out the song playing
  along, noise suppression takes held notes for noise, automatic gain
  pumps the level), two channels and 48 kHz where the microphone has
  them (asked for, not required). What the browser gave is logged
  (`TabCam: cam: microphone: …`); Safari on iOS may not honour all of it.
  The take's sound is at 192 kbps, its video at 5 Mbps, in VP8 before
  VP9, the camera's frames as they come (nothing drawn on them). Chrome
  encodes both in software (libvpx), VP8 at a fraction of VP9's cost.
  H.264, which Chrome can encode in the graphics hardware, isn't asked
  for: in a WebM, Firefox and Safari don't play it, and an MP4 take
  would change what the rest of the app reads from the web's takes
  (WebM); left for a change of its own. With no microphone (refused or
  missing) Rec records nothing and says so ("No take without its
  sound: …"); should the recorder fail and the camera record the take
  alone, the microphone's track is added to the camera's stream (its
  preview is muted, so it isn't heard), so that take has its sound too.
- **iOS**: the camera records sound at 128 kbps (AAC; its plugin writes
  mono at 44.1 kHz). When Cam opens, the microphone joins the camera
  (`prepareForVideoRecording`; else it would as the take starts, and the
  take's first moments of sound are lost), and the app's audio session is
  set over the method channel `tabcam/audio` (`prepare`, in
  [`AppDelegate.swift`](../tabcam_app/ios/Runner/AppDelegate.swift)):
  play and record, in the `videoRecording` mode (the microphone by the
  camera, none of a call's voice processing), mixed with others (the
  song playing along, in the app or another, goes on and isn't lowered:
  no ducking), the speaker by default, Bluetooth (A2DP) and AirPlay for
  the sound out, 48 kHz preferred. It's set again as each take starts
  (changed only where something changed it), and `release` puts the
  mode back to the default when Cam closes. A take played back in Cam
  plays mixed with others too, and so do the list's video thumbnails
  (never heard; the capture's screen stays under Cam and makes the new
  take's as it's saved, maybe while the next records), so neither stops
  a song playing in another app (opened otherwise, a player takes
  "mixed with others" from the app's session).
- **Android**: the app records the take's sound itself, apart from the
  camera, and puts it into the take when it stops
  ([`TakeSound.kt`](../tabcam_app/android/app/src/main/kotlin/com/nu01/tabcam/TakeSound.kt),
  [`take_sound.dart`](../tabcam_app/lib/capture/take_sound.dart), method
  channel `tabcam/take_sound`). The camera plugin (CameraX) would
  record the camcorder source, with the phone maker's automatic gain,
  noise suppression and limiter, and takes no other source or bitrate.
  - **When Cam opens** (`prepare`, before the camera): the microphone
    permission is asked for if it isn't granted yet, then the microphone
    is opened with `AudioRecord`, from the first source that works:
    `UNPROCESSED` where the phone says it has it
    (`AudioManager.PROPERTY_SUPPORT_AUDIO_SOURCE_UNPROCESSED` is
    "true": no gain control, noise suppression or limiter), else
    `VOICE_PERFORMANCE` (Android 10 on: meant for live music), else
    `MIC`; 48 kHz stereo, else 48 kHz mono, 44.1 kHz stereo, 44.1 kHz
    mono; 16-bit PCM. Each is tried (started, read from for up to half
    a second, stopped), and the first that gives sound is kept open
    until Cam closes (`release`), recording between takes for the
    [level meter](#level-meter). What it got is logged (`tabs.cam: take
    sound: unprocessed 48000/2 …`). The camera then opens **without
    sound** (`enableAudio: false`). Should no source work, or the
    microphone be refused, the camera opens with sound and records the
    take's as before (the camcorder source), and why is logged
    (`TabCam: cam: the camera records the take's sound: …`). Refused,
    the camera plugin asks for the microphone again as it opens: refused
    there too, Cam says the camera or microphone isn't allowed, as
    before; allowed there, Cam prepares again at once, without asking
    (`prepare` with `ask` false), and the app records the takes' sound
    after all. That camera, opened with sound, records none of its own:
    its plugin only adds the microphone to a recording when the
    permission reads as granted as it starts, which the app hides then
    (see Rec).
  - **Rec** starts the sound first (`start`: the microphone records, its
    AAC encoder and file set up, so a failure shows before any video;
    then no take starts and "Couldn't record: …" says why), then the
    camera, and tells the app's side the moment the camera's recording
    has started (`videoStarted`). The sound is read on a thread of its
    own at the urgent-audio priority (`THREAD_PRIORITY_URGENT_AUDIO`),
    which only reads (20 ms at a time, from a half-second buffer, at
    least four times the system's smallest) and queues; another thread,
    at the normal priority, encodes it to AAC (256 kbps in stereo, 128
    kbps in mono, `MediaCodec`, into an `.m4a` in the cache), so a slow
    encoder only lets the queue grow (192 KB a second in stereo), never
    a gap in the sound. An encoder that fails mid-take still takes what
    is read off the queue till the take stops (dropped), so it doesn't
    grow through the take; the take is then saved without its sound, and
    a message says so. The camera doesn't open the microphone: its
    plugin would (with the camcorder source, muted, but sharing the
    microphone's input, whose processing would then go to the app's
    sound too) unless the permission reads as refused when its
    recording starts, so `MainActivity.checkPermission` says
    `RECORD_AUDIO` is refused, to the app itself, from `start` until
    `videoStarted` (the app's own checks use the application's context
    and are untouched). Should the camera not start, the sound is
    dropped (`cancel`).
  - **In step**: the sound's first frame's time is read from the
    system (`AudioRecord.getTimestamp` in `BOOTTIME`, the latest over
    the first second; else when the first read came back, less its
    length); the video's start is when the camera's recording said it
    started (the plugin waits for CameraX's start event; `videoStarted`
    is called as soon as that returns), or, without it, when Stop was
    pressed (`videoStopping`) less the video's length. The encoder waits
    for the video's start and drops the sound before it (or puts
    silence first, should the sound have started later, at most 2 s),
    so the sound's first frame is the video's first, to the sample.
    Both ways of telling the video's start are logged at Stop, with how
    far apart they are, to check the step on a phone.
  - **Kept in step** through the take: the encoder numbers the sound's
    frames at its nominal rate, while the video's times are the system's,
    so a microphone clock off its rate (100 ppm, a usual error, is 60 ms
    in ten minutes) or frames lost (the reader late by more than the
    half-second buffer) would put the sound out of step as the take goes
    on. So the reader reads the system's timestamp again each second
    (`getTimestamp`, which tells where the sound really is), and from
    the first frame's time it gives, how many frames the sound has
    fallen behind ([`TakeSoundMath`](../tabcam_app/android/app/src/main/kotlin/com/nu01/tabcam/TakeSoundMath.kt)
    `driftFrames`); the encoder makes it up as it goes (`correction`):
    50 ms or more behind, frames were lost, and that much silence goes
    in at once where they were; more than 1 ms either way, one frame is
    repeated or left out per 20 ms read (at most 1 ms a second, ten
    times a clock's usual error; too little to hear). A timestamp going
    back by 50 ms or more, or forward by more than 10 s, is taken as
    wrong, and the timestamps aren't followed for the rest of the take.
    What it came to is logged at Stop (`drift … frames (… ppm …); …
    frames of silence put in, … repeated, … left out`), and silence put
    in for lost frames gets "Check the take's sound: the sound skipped
    … ms" (the take kept). (CameraX, recording the sound itself, timed
    each of its buffers by the timestamps.)
  - **Stop** stops the camera, then the sound (after the video's end),
    and `stop` puts the sound into the camera's MP4
    ([`TakeMux.kt`](../tabcam_app/android/app/src/main/kotlin/com/nu01/tabcam/TakeMux.kt)):
    the video and the sound copied as they are, not re-encoded
    (`MediaExtractor` and `MediaMuxer`, interleaved by time, the
    video's rotation kept), the sound after the video's end left out,
    and, should the encoder say how much priming it put first
    (`encoder-delay`), that many whole AAC frames dropped. The camera's
    file and the `.m4a` are deleted. That file is the take, saved as it
    is: nothing is burned in after, so the sound is never encoded twice.
  - **Never a silent take unsaid**: should the sound not go in, the
    take is saved as the camera recorded it (without sound) and "The
    take was saved without its sound: …" says why; should the sound
    have stopped early (the microphone failed mid-take), be all
    silence (another app holding the microphone silences this one, on
    Android 10 on) or have skipped (frames lost, silence in their place),
    it's saved and "Check the take's sound: …" says so.
  - The song playing along is heard through the microphone, as before
    (the unprocessed source cancels no echo). A take played back in Cam
    mixes with others, so it doesn't take the audio focus from a song
    playing in another app.
  - Checked: the app's side with a faked channel (tests), the native
    side by building it, and its arithmetic (sources, step, drift and
    its making up) by JVM tests (`android/app/src/test`,
    `TakeSoundMathTest`: `./gradlew :app:testDebugUnitTest` in
    `android/`, with the JDK Flutter uses); **not yet on a phone**. Still to check there:
    the step (a clap on the take, sound against picture, and the two
    starts logged), which source the phone gives, and whether the AAC
    encoder states its priming.
- **While a take records**, everywhere: head gestures look for a face
  about 7 times a second instead of 10 (enough for a nod, out and back
  within a second). On Android and iOS that is the face detector's
  rate: with gestures on, the camera plugin still hands every frame to
  the app (it streams no fewer), and the app skips most of them; on iOS
  that copy runs on the queue that writes the take's sound. With
  gestures off when the take starts, the camera streams no frames during
  it at all (turned on during a take, they work from the next). Cloud
  sync starts no pass (one asked for meanwhile,
  such as for the take just saved before the **/** key's next one, runs
  2 s after the take ends, unless another starts by then; a pass already
  running goes on); phrase passes are kept when the take ends, as
  before. Auto-pass and the song playing along go on as ever.
- Not controllable without forking the camera plugins or recording the
  sound separately (as Android now does): iOS's mono 44.1 kHz; the
  plugins' own thread priorities. (The microphone itself is chosen in
  [Rec's menu](#rec-menu).) On iOS, an HEVC take made H.264 has its sound
  re-encoded (AAC to AAC); an H.264 take, and every Android take, keep
  it as recorded.

**Permissions**: the camera and the microphone (iOS:
`NSCameraUsageDescription`, `NSMicrophoneUsageDescription`; Android:
`CAMERA` and `RECORD_AUDIO`, the microphone asked for by the app when Cam
opens (for the take's sound), then the camera by the `camera` plugin; the web: the browser's
prompts, for the camera and then the microphone, when Cam opens; with
the microphone refused, the preview shows but Rec records nothing). On
the web a take is WebM (MP4 on Safari), on Android MP4 (H.264), on iOS
MP4 (H.264; an HEVC take made H.264 as it's saved).

## A camera that won't start

A browser can be allowed the camera and still fail to start one: Chrome's
NotReadableError, "Could not start video source". On Windows that's
common, where a webcam another app has open (Teams, Zoom, the Camera
app) is locked to it, and laptops list cameras a browser can't use (the
infrared Windows Hello camera, "Integrated IR Camera"; a virtual camera
whose app isn't running).

- **The list** ([lib/capture/camera_list.dart](../tabcam_app/lib/capture/camera_list.dart),
  `listCameras`, Cam's and the web's [Scan](scanning.md)'s): camera_web
  opens every camera to learn which way it faces, and fails as a whole
  when one won't start. Then the app lists them itself the same way,
  leaving out those that don't start, and records each for the plugin
  to open (`CameraPlugin.camerasMetadata`, which the plugin fills only
  from its own list). Only when none starts does the error stand.
  Cameras whose name says infrared (`IR`, "infrared") come last.
- **Opening** ([`CamSession`](../tabcam_app/lib/capture/cam_session.dart)):
  Cam opens the front camera, else the first; one that fails gives way
  to the next, until one opens (not after "isn't allowed": none would
  be). None opening, the first one's error shows.
- **The error** for a camera that won't start says so: "The camera won't
  start: another app may be using it (Teams, Zoom, the Camera app). Close
  it and try again, or flip to another camera." It has **Try again**,
  which lists and opens the cameras again, and **Flip camera** stays in
  the app bar (with more than one) to try another. Scan on the web says
  the same, with Try again beside Choose photos instead.

Verified: widget tests (the next camera opens when the first won't start;
none starting, the message, Try again opening it once free, and Flip
camera; infrared ones last), and in Chromium (Playwright, a release web
build of Cam alone, the fake camera, `getUserMedia` patched to fail as
Windows does): an "Integrated IR Camera" listed first that won't start
fails camera_web's list, and Cam then opens the other camera, with its
microphone; every camera busy, the message and Try again show, and Try
again opens the camera once it's free. Not yet on a Windows PC.

