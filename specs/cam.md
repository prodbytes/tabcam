# Cam: playing along

**Cam**, a tool on the [event screen](event-screen.md), lets a guitarist
record themselves playing along with the capture's tab. It's TabCam
Premium's ([cloud OCR](cloud-ocr.md#in-the-app)): without Premium it opens
as a **preview** (`PlayAlongScreen` with `gate` set): no camera is opened
(a camera icon where the preview would be), no key, nod or tap does
anything, Rec and Play are dead, the tab along the bottom is the
capture's or a made-up sample, and the Premium card lies over it all,
its **Not now** leaving. With Premium it opens the camera view
([`PlayAlongScreen`](../tabcam_app/lib/capture/play_along_screen.dart)):

- **The camera** fills the screen, the **front** one first (it faces the
  player); **Flip camera** in the app bar moves to the next one (not
  while recording). The app bar has the capture's title, and first of
  its buttons **Dictionary** (a book icon, in the preview too), which
  shows the chord and scale [dictionary](dictionary.md) in a sidebar on
  the right, the camera beside it (or, turned by its Rotate button, in
  a panel under the camera); typing in it doesn't move the tab,
  and once it's hidden the keys move the tab again. **Metronome** (a
  stopwatch icon) after it opens the [metronome](metronome.md)'s sidebar
  the same way. Without a
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
- **Moving along the tab**: any key (but **1**, which is
  [Rec / Stop](#rec-key), **.**, which is [a new take](#new-take-key),
  and the space bar, 0, ← and → while a file
  [plays along](#playing-along-with-a-file)) goes to the
  next neckline (a keyboard, or a Bluetooth page-turner pedal), **↓**
  among them; **Backspace**, **↑** and **Page Up** go to the one
  before, and so does **←** while nothing plays along. Shift, Control, Alt,
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
  from the neckline showing, until **Stop**.
  <a id="rec-key"></a>The **1** key (on the top row or the keypad)
  presses it too, Rec and then Stop, with the sidebar showing or not
  (so it also starts the sidebar's song, as Rec does); it doesn't turn
  the tab. It acts on the key down: held, it doesn't repeat (it
  doesn't start a take and stop it again). While the button can't be
  pressed (a take being saved or playing back, no camera, the
  preview), 1 does nothing. With Ctrl, ⌘ or Alt held, 1 is another
  shortcut's (the browser's) and turns the tab as any key. The button's
  tooltip says so: "Rec (1)", and "Stop (1) · new take (.)" while
  recording, in English, Spanish and Portuguese. The take is then added to
  the capture as a video, at the end of its files, named "Take 1",
  "Take 2"… (the first number no file has), and a message says so. It
  is marked as a take (`take` on its page, `EventPage.take`), which
  stays when it's renamed, edited, cloned or published, so the
  play-along sidebar lists it with the [takes](#playing-along-with-a-file).
  It syncs as any video does (the mark with it, as its name does).
  Going back while recording stops it and keeps the take. Back on the capture, its takes show: the file list
  (not the Text view), scrolled to its end.
  <a id="new-take-key"></a>The **.** key (on the main keyboard or the
  keypad's decimal key, also where that key types "," as on Brazilian,
  German and most European layouts, matched by where it is on the
  keyboard; the comma key itself turns the tab) starts **a new take** while recording: the
  take is stopped and saved as Stop saves it (added, named, its phrase
  passes kept, the message shown), and once it's saved, the next take
  starts as Rec starts one. The song in the sidebar (when it shows)
  stops at once and goes back to its start (its section's, with one
  chosen), so it's silent while the take is saved; with the new take
  it plays from there, after the count-in if that's on, as Rec starts
  it. The tab stays at the neckline showing, as with Rec (auto-pass
  turns it along the song, as ever). Not recording, **.** starts a take,
  as 1 does. It acts on the key
  down only (held, it doesn't repeat), does nothing while Rec can't be
  pressed, and with Ctrl, ⌘ or Alt it turns the tab as any key. While
  the take is saved for the next, Rec, Play, the camera switch, 1, .
  and going back do nothing, so a second press can't start or stop
  another take (the camera records one at a time). Nor do Rec, 1 and .
  while a take starts (until the camera records), so pressing again at
  once doesn't start a second recording alongside it. If the next take
  can't start, the one saved is kept and a message says why.
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
- **Tab** (beside Rec and Play: **Hide tab** with the tab showing,
  **Show tab** with it hidden) hides the tab along the bottom, leaving
  the camera more of the screen, and shows it again. Hidden, it still
  turns (keys, taps, head gestures, a take playing back) and a take
  still gets it burned in where it showed; it's only off the screen.
  It shows again each time Cam opens.
- <a id="phrase-passes"></a>**Phrase passes**: while recording with
  [Auto-pass](#auto-pass) on, each
  time the user turns the tab (a key, a tap on the neckline or its
  arrows, a head gesture) with a song playing in the sidebar's
  [player](#playing-along-with-a-file) (one that plays in the app: a
  recording or video of the capture's, or a link straight to a sound or
  video file, not a page in a frame), the song's position is noted, with
  which way it turned (**next** or **previous**) and the neckline it
  turned to ([`PhraseTimes`](../tabcam_app/lib/library/phrase_times.dart),
  `BackingTrack.recordPass`, the position read from the player itself).
  A pass within **two seconds** of one the same way (this time through
  or an earlier one) is merged into it, at their **average** time (each
  pass merged into it counting, so it settles as the song is played
  again), keeping the newer's neckline; one moved within two seconds of
  another the same way merges with it too. Passes are only noted while
  recording, only while the song plays, and only while Auto-pass is on:
  with it **off**, recording notes none, for the song or for the take,
  and the passes there already stay as they are (they're neither
  changed nor deleted). Switched during a take, the turns made while it
  was on are noted and kept, those made while it was off aren't. That
  leaves a **gap** in the passes (the song's and the take's), and
  [Auto-pass](#auto-pass) only knows the passes: through a stretch
  recorded with it off the tab stays on the last pass's neckline, and
  goes straight to the next pass's (however many lines on) when the
  song reaches it; before the first pass it shows the neckline that
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
  - **They go with their file**: a file deleted (from the capture, or
    from the user's contribution), its passes are deleted with it; a
    clone's copies of the files have their originals' passes, and so
    does a file the owner [publishes](contributions.md#what-the-owner-sees-and-publishes)
    from a contribution (the owner's own for it, else its reader's).
    Passes for a song deleted elsewhere are let go of at the next save.
  - **The take** keeps its own too, from when its necklines showed
    while Auto-pass was on (merged the same way; `takePhrases`), so
    played along later it turns the tab as it turned in it. A turn made
    while Auto-pass was off is still in the take (burned in, and
    followed when Play plays it back), but it's no pass of the take's;
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
  kept on the device in the `cam` meta file): while a song with phrase
  passes plays in the player, Cam turns the tab by itself where they
  are ([`AutoPass`](../tabcam_app/lib/capture/auto_pass.dart)), reading
  the song's position every 100 ms: as the song passes one, the tab
  goes to its neckline. When the song jumps (it starts over at its end
  or its section's with Repeat, «, », a scrub, Play from the start, or
  auto-pass switched on), the tab goes to the neckline the passes show
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
reverse of the order they were made: Take 3, Take 2, Take 1), played along as the others
are. A take is one Cam marked as such (renamed, it still is one), or,
saved before takes were marked, a video named as Cam names them in any
of the app's languages ("Take 3", "Toma 3"; `isTake`). On a capture
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
would (after the [count-in](#count-in), from where it is, or from its
start, its section's, at its end), once the take is recording; one
that plays already plays on, and with the sidebar hidden nothing
starts. Stop (the take's) leaves it playing.

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
holds in both; the capture's last file can't
be deleted (the message says to delete the event instead), and a
failure shows "Couldn't delete". It shows only where the list would
offer it: on the user's own captures and those shared with them to
edit, on every file; on a capture shared to read, on none of the
owner's, only on the reader's own (their takes, listed after the
capture's files and under **Takes**), which it deletes from their
[contribution](contributions.md), file and all. Not in Cam's Premium
preview, nor on a capture opened by its link. It's greyed while a take
records, saves (with ".", until the next take has started) or plays
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
  to scrub (marked where its [phrase passes](#phrase-passes) are, with
  the button that clears them at the line's right end), the
  [count-in](#count-in) at the start of the progress bar's line; a recording only that line; under them its icon and
  name in small type, then **«** (10 seconds back, not before the
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
  in the primary colour once set), **|◀** and **▶|** (start or end it
  where it plays now) and, once set, **✕** (play all of it again). While
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
  goes back to the start and keeps counting. Repeat and a section's
  loop start over without one; the count-in is real time, whatever the
  speed. The setting is kept on the device (the meta file
  `play-along`, `{"countIn": false}`), for Cam, the Text view and the
  file screen alike.
- **The space bar** pauses and plays it while the sidebar shows (a key
  down; held, it doesn't repeat), and doesn't turn the tab; with the
  sidebar hidden, space turns the tab again. A tap in the sidebar or the
  frame gives the keys back to Cam.
- **0** (on the top row or the keypad) goes back to the start of the
  file, or of its section when one is set, playing on if it was playing
  and staying paused if it wasn't (`BackingTrack.restart`; a link in
  the frame goes back by Stop, then plays again if it played). Like
  space, it doesn't turn the tab while the sidebar shows. Ctrl / ⌘ + 0
  is left to the browser (its zoom).
- **← and →** go 10 seconds back and on in it, as « and » do (held,
  again and again), and don't turn the tab while the sidebar shows; the
  tab's phrases go by **↑** (the one before) and **↓** (the next). With
  the sidebar hidden, ← and → turn the tab again. A page-turner pedal
  that sends ← and → skips in the song while the sidebar shows: one
  that sends ↑ / ↓ or Page Up / Page Down turns the tab then.
- **The keys outside Cam**: in the Text view and on a recording's file
  screen, a tap in the sidebar gives it the keyboard
  ([`PlayAlongKeys`](../tabcam_app/lib/capture/play_along_sidebar.dart)),
  so **0** and the **space bar** work there as in Cam; typing in a field
  (the Text view's editor) still types them.
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
    `https://tabcam.nu01.com/` (YouTube wants to know the site that
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

On a capture shared with the user to read, each take goes to their own
[contribution](contributions.md), named among its takes. Cam is off on a
capture opened by its link (a take couldn't be saved there), and while a
tool works. Opening it stops what
plays in the list.

**Permissions**: the camera and the microphone (iOS:
`NSCameraUsageDescription`, `NSMicrophoneUsageDescription`; Android: the
`camera` plugin's `CAMERA` and `RECORD_AUDIO`; the web: the browser's
prompt). On the web a take is WebM, on Android MP4, on iOS MOV.
