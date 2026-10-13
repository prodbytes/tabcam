# Event screen

One event (a capture), opened from the [library](library.md): the list of
its files, each opening alone on the [file screen](#file-screen). If its
text tab is marked correct ([tab recognition](tab-recognition.md#text-view)),
it opens on the Text view; otherwise on the list.

- **App bar**: the title (and the artist under it, if set); tapping it, or
  **Rename** (pencil), renames the event (see
  [library](library.md#events)). **Clone** copies the event and opens the
  copy ([library](library.md#events)). There's no Reorder button: the
  [files list](#reordering) reorders in place.
  **Share** (a link icon) copies the capture's link ([sharing](sharing.md));
  **Share with people** (people with a plus,
  [shared captures](shared-captures.md)) is beside it for the user's own
  events, in a build with sharing. There's no Hide images
  button (captures already [hidden](hidden-images.md) stay hidden).
- **Shared with the user**: a line under the app bar, "Shared by <email>
  · Can edit" or "· Read only". Read only, Rename, reordering, Add, Rotate, Delete
  and editing the text tab are off; the view still changes what shows,
  without saving it.
- **Files**: the list of the event's files, in their order, newest last
  (so a page just scanned or added is at the end, and the list scrolls to
  it after Add). Each row has a preview and a name:
  - **Images** (photos and scans): the image itself, as its filter shows
    it; "Page 1", "Page 2"…
  - **Videos**: a play badge; "Video 1"…
  - **PDFs**: a PDF badge; "PDF 1"…
  - **Recordings** (audio): a music note; "Recording 1"…
  - **Links**: a link badge; the title (or the address's host), the
    address under it.

  Numbers count the files of that kind. A file the user named shows its
  name instead, whatever it is; files, PDFs, recordings and videos added
  are named after their file name (without the extension; photos aren't,
  pickers name them at random). **Rename file** (a pencil on each row, or
  a long press) asks for the name, prefilled; saving it empty goes back
  to the default name. The name is the page's `title`, synced with the
  event. A tap opens the file alone on the file screen. With the images [hidden](hidden-images.md), the list
  is the **text tab** first (its first line, or "No text tab yet"; a tap
  goes to the Text view), then the other files.
- <a id="reordering"></a>**Reordering**: in the user's own events or
  those shared to edit, with more than one file listed, each row ends in a
  **drag handle** (in place of the arrow, tooltip "Reorder"); dragging a
  row by it moves the file in the list itself (no separate sheet). Only
  the handle starts a drag, so a tap still opens the file, and the rename
  pencil and long press still rename it, on the web, desktop and phones.
  Each drop saves the new order at once (the event changes, so it syncs,
  and moved photos or PDFs are
  [read again](tab-recognition.md#reading-by-itself) in their new order).
  With the images [hidden](hidden-images.md), only the other files are
  listed and dragged, the images keep their places, and the text tab
  stays first. Read only, with a single file, or while a tool works,
  there are no handles. A failed save shows "Couldn't reorder".
- **Tools** along the bottom:
  - **Files**, first: the list (highlighted while it shows).
  - **Text**, second: the tab read from the files, in place of the list
    (highlighted while it shows): the
    [text view](tab-recognition.md#text-view), or why there's no text
    yet. There's no Read tab: every capture is read by itself
    ([tab recognition](tab-recognition.md#reading-by-itself)).
  - **Add**: more files, [scanned or picked](scanning.md#adding-to-an-event):
    Scan pages, Document, Photos & videos, Files, or a **Link**. The list
    then shows, scrolled to what was added.

  The Original / Scan view, Rotate and Delete are the file screen's, not
  this one's.
- While a tool works, a progress bar shows under the app bar and the tools
  are off. Failures show as a message at the bottom.

## File screen

One file, opened from the list, on its own screen (the back button goes
to the list). The app bar has the file's name ("Page 2", a link's title,
or the name the user gave it); tapping it, or **Rename file** (pencil),
renames the file.
The file is shown whole, as what it is:

- **Images** are pinch-zoomable (up to 5×), as the view says.
- **PDFs** show the document itself (`pdfrx`, PDFium; WASM on the web,
  loaded when a PDF is first shown), its pages scrolling down, zoomable.
  A PDF that can't be read says so.
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
  clipboard). **Open** shows the page in a browser inside the app on
  Android and iOS (Custom Tabs, Safari View Controller), or where there's
  none, the browser or the app that handles it (such as YouTube); on the
  web, in a new tab. A link that can't open says so.
- **YouTube videos**: a link to one (`youtube.com/watch?v=…`,
  `youtu.be/…`, `/shorts/…`, `/live/…`, `/embed/…`, on any YouTube
  host) shows the same card with a video icon and **Play** first.
  Nothing is loaded from YouTube until **Play**: tapped, the card
  becomes YouTube's embedded player (`youtube_player_iframe`, in the
  privacy-enhanced youtube-nocookie.com mode), playing from the link's
  start time (`t=` / `start=`, as `90`, `90s` or `1m30s`), with
  **Open** and **Copy** under it. YouTube's controls are in the app's
  language; captions follow the viewer's YouTube setting; related
  videos at the end are from the same channel; full screen on the web
  only. If the video can't play here for any reason (YouTube's error,
  such as the video not allowing embedding or not found; the player
  page not loading; no player within 20 seconds; no web view), the
  page goes back to the link card, saying "This video can't be played
  here", without **Play**: **Open** opens it in a new tab (on Android
  and iOS, the browser inside the app, as for any link). Only the web,
  Android and iOS embed; elsewhere it's a plain link.

Its tools, along the bottom:

- **The view** (images only): a tap flips **Original ↔ Scan**, its icon
  and label saying which shows. **Original**: the photo as taken;
  **Scan**: processed (the Tab [filter](page-filters.md)). It sets that
  image's filter, saved (its thumbnail and the exports follow); a new
  page shows Scan.
- **Rotate** (images only): turns the image a quarter turn clockwise
  (stored as a new page in its place; see [library](library.md#events));
  the screen stays on it.
- **Delete**: deletes the file and goes back to the list. The last file
  can't be deleted (the message says to delete the event instead).

A reload or a restart with a file open reopens it, over its event's list
([navigation](navigation.md#coming-back-where-the-user-was)).
