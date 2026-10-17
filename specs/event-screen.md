# Event screen

One event (a capture), opened from the [library](library.md): the list of
its files, each opening alone on the [file screen](#file-screen). If its
text tab is marked correct ([tab recognition](tab-recognition.md#text-view)),
it opens on the Text view; otherwise on the list. When the capture has
recordings, videos or links, the Text view has the play-along sidebar
beside it, open, and **Play along** (♫) in the app bar, as in
[Cam](cam.md#playing-along-with-a-file); the Files view has neither, and
going to it, or to Cam, pauses what plays along.

- **App bar**: the title (and the artist under it, if set); tapping it, or
  **Rename** (pencil), renames the event (see
  [library](library.md#events)). **Clone** copies the event and opens the
  copy ([library](library.md#events)). There's no Reorder button: the
  [files list](#reordering) reorders in place.
  **Download all** (a download arrow) saves the whole capture as
  `<title>.zip`: every file listed (named as in the list; the images
  left out when [hidden](hidden-images.md)), the text tab as
  `<title> tab.txt` and the links, one a line, as `links.txt` (names
  that repeat get " (2)"…); files still coming down
  ([sync](cloud-sync.md#listed-first-files-after)) are waited for.
  **Share** (a link icon) copies the capture's link ([sharing](sharing.md));
  **Share with people** (people with a plus,
  [shared captures](shared-captures.md)) is beside it for the user's own
  events, in a build with sharing. There's no Hide images
  button (captures already [hidden](hidden-images.md) stay hidden).
- **Shared with the user**: a line under the app bar, "Shared by <email>
  · Can edit" or "· Can view and add". Shared to read, Rename, reordering,
  Rotate, Delete and editing the text tab are off for the owner's files
  (the view still changes what shows, without saving it); Add, dragging
  files and Cam add to the user's own [contribution](contributions.md).
- **Contributions**, below the files ([contributions](contributions.md)):
  on the owner's capture, each reader's files under "From <email>", each
  with **Publish** (or Published, to take it back); on a reader's, their
  own under "Your files", each with Delete.
- **Files**: the list of the event's files, in their order, newest last
  (so a page just scanned or added is at the end, and the list scrolls to
  it after Add). Each row has a preview (80 px square, in a row with
  10 px of padding above and below) and a name. Previews are made on
  the device, from the file itself (nothing is fetched from the
  internet); one that can't be made shows its kind's generic badge:
  - **Images** (photos and scans): the image itself, as its filter shows
    it; "Page 1", "Page 2"…
  - **Videos**: the video's first frame (paused, silent) with a play mark
    over it, else a play badge; "Video 1"…
  - **PDFs**: the PDF's first page (PDFium, as the file screen draws it),
    else a PDF badge; "PDF 1"…
  - **Recordings** (audio): a music note; "Recording 1"…
  - **Links**: a link badge (a video badge for a YouTube video: its
    picture would come from YouTube, and nothing loads from there before
    **Play**); the title (or the address's host), the address under it.

  **Playing from the list**: a video's or recording's row has a **play /
  pause** button (before the rename pencil); it plays the file right
  there ([`ListPlayer`](../tabcam_app/lib/screens/mini_player.dart),
  `video_player`), a video in its thumbnail's place, with a scrubbable
  progress bar and the time ("0:12 / 3:04") under its name. One plays at
  a time: playing another stops the first; opening a file (its own
  screen has its own player) and leaving the capture stop it too. At the
  end, play starts it over. One that can't play says so under its name
  ("This video can't be played here", or the recording's message).

  Numbers count the files of that kind. A file the user named shows its
  name instead, whatever it is; files, PDFs, recordings and videos added
  are named after their file name (without the extension; photos aren't,
  pickers name them at random). **Rename file** (a pencil on each row, or
  a long press) asks for the name, prefilled; saving it empty goes back
  to the default name. The name is the page's `title`, synced with the
  event. **Download** (a download arrow, after the pencil) saves the
  file under its name in the list, with its extension (a scanned page,
  kept as `img`, downloads as `.jpg`): a download in the browser, the
  system's "save as" on Android and iOS (`file_picker` `saveFile`); a
  link has none. Downloading is offered read only too. On a phone
  narrower than 600 px, Rename, Download and Delete are in a **More**
  menu (⋮) on each row instead of buttons, so the name keeps its room.
  **Delete file** (a bin on each row, after Download) asks
  "Delete "<name>"?" (Cancel, Delete) and deletes the file (stopping it
  if it plays in the list); the last file can't be deleted (the message
  says to delete the event instead), and a failure shows "Couldn't
  delete". Rename and Delete aren't there read only. A tap opens the file alone on the file screen, except a link's:
  a tap opens the link itself, outside the app, as the file screen's
  **Open** does (a new tab on the web; the browser, or the app for it
  such as YouTube, on Android and iOS). A link's chevron (**Details**)
  opens it on the file screen, for Copy and Delete. With the images [hidden](hidden-images.md), the list
  is the **text tab** first (its first line, or "No text tab yet"; a tap
  goes to the Text view), then the other files.
- <a id="reordering"></a>**Reordering**: in the user's own events or
  those shared to edit, with more than one file listed, each row ends in a
  **drag handle** (in place of the arrow, or after a link's Details,
  tooltip "Reorder"); dragging a
  row by it moves the file in the list itself (no separate sheet). Only
  the handle starts a drag, so a tap still opens the file, and the rename
  pencil and long press still rename it, on the web, desktop and phones.
  Each drop saves the new order at once (the event changes, so it syncs,
  and moved photos or PDFs are
  [read again](tab-recognition.md#reading-by-itself) in their new order).
  With the images [hidden](hidden-images.md), only the other files are
  listed and dragged, the images keep their places, and the text tab
  stays first. Shared to read, with a single file, or while a tool works,
  there are no handles. A failed save shows "Couldn't reorder".
- **Tools** along the bottom:
  - **Files**, first: the list (highlighted while it shows).
  - **Text**, second: the tab read from the files, in place of the list
    (highlighted while it shows): the
    [text view](tab-recognition.md#text-view), or why there's no text
    yet. There's no Read tab: every capture is read by itself
    ([tab recognition](tab-recognition.md#reading-by-itself)). Its icon
    says how the tab stands: a **spinner** in its place while the
    capture is read, on the device or in the cloud (tooltip "Reading the
    tab…"), and only then: once the text tab is there (read on the
    device, or come from the cloud with sync) the spinner stops, and a
    read that waits too long fails; the usual icon once there's a text
    tab; **greyed out** without one (no tab found, not read, the text
    deleted or blank, reading failed or not possible here). Greyed out,
    it still opens the Text view, which says why and offers Read again
    or Sign in. A tap opens the Text view; tapped on the Text view, it
    does nothing more: reading the tab again is the Text view's
    **Rescan**.
  - **Add**: more files, [scanned or picked](scanning.md#adding-to-an-event):
    Scan pages, Document, Photos & videos, Files, or a **Link**. The list
    then shows, scrolled to what was added.
  - **Cam**, last: the camera with the tab under it, one neckline at a
    time, to record the user playing along; takes are added as videos
    ([Cam](cam.md)), and back from it the list shows, scrolled to them.
    On a capture shared to read, takes are the user's own contribution's.
    Off on a capture opened by its link.
  - **Dragging files** onto the screen adds them too, as Files does
    (outlined with "Drop files to add" while they're over it; folders and
    files that aren't pages are left out, with the message saying how
    many); on a capture shared to read, to the user's own contribution.
    Not on a capture opened by its link, nor while a tool works; not on iOS (see [Capture](navigation.md#capture)).

  The Original / Scan view and Rotate are the file screen's, not this
  one's; Delete is on both.
- While a tool works, a progress bar shows under the app bar and the tools
  are off. Failures show as a message at the bottom.

## File screen

One file, opened from the list, on its own screen (the back button goes
to the list). The app bar has the file's name ("Page 2", a link's title,
or the name the user gave it); tapping it renames the file, as does the
**Rename** tool beside Delete.
The file is shown whole, as what it is:

- **Images** are pinch-zoomable (up to 5×), as the view says.
- **PDFs** show the document itself (`pdfrx`, PDFium; WASM on the web,
  loaded when a PDF is first shown), its pages scrolling down, zoomable.
  A PDF that can't be read says so. When the capture has recordings,
  videos or links, the play-along sidebar is beside it, open, with **Play
  along** (♫) in the app bar, as in [Cam](cam.md#playing-along-with-a-file).
- **Videos** show a play button; tapped, they play in place, looping,
  with a bar at the bottom: a **play / pause** button and a scrubbable
  progress bar. A tap on the video also pauses and resumes. A video that
  can't play says so.
- **Recordings** (audio) show as a card with a music note, "Recording"
  and a **play** button; tapped, it loads and plays, with **play /
  pause**, a scrubbable progress bar and the time ("0:12 / 3:04"). At the
  end, play starts it over. A recording that can't play says so. They
  play through `video_player`, as videos do.
- **Links** show as a card with a link icon, the title (or the address's
  host), the address (selectable), **Open** and **Copy** (to the
  clipboard). **Open** opens the link outside the app: on the web in a
  new tab; on Android and iOS in the browser, or the app the system
  hands it to (such as YouTube) (`url_launcher`,
  `LaunchMode.externalApplication`, window `_blank`). Only `http` and
  `https` links open. A link that can't open says so.
- **YouTube videos**: a link to one (`youtube.com/watch?v=…`,
  `youtu.be/…`, `/shorts/…`, `/live/…`, `/embed/…`, on any YouTube
  host) shows the same card with a video icon. Nothing plays in the app:
  **Open** opens it like any link, where YouTube starts it at the
  link's own start time (`t=`), if it has one.

Its tools, along the bottom:

- **The view** (images only): a tap flips **Original ↔ Scan**, its icon
  and label saying which shows. **Original**: the photo as taken;
  **Scan**: processed (the Tab [filter](page-filters.md)). It sets that
  image's filter, saved (its thumbnail and the exports follow); a new
  page shows Scan.
- **Rotate** (images only): turns the image a quarter turn clockwise
  (stored as a new page in its place; see [library](library.md#events));
  the screen stays on it.
- **Rename** (pencil), just before Delete: asks for the file's name,
  prefilled, as on the list (saving it empty goes back to the default
  name).
- **Delete**: deletes the file and goes back to the list. The last file
  can't be deleted (the message says to delete the event instead).

Rename and Delete are off while a tool works and on a capture shared read
only. The tools share the bar equally, so all four (an image's) fit a
narrow phone.

A reload or a restart with a file open reopens it, over its event's list
([navigation](navigation.md#coming-back-where-the-user-was)).
