# Delete confirmations

Deleting something in the app asks first, in one shared dialog
([lib/screens/delete_confirm.dart](../tabcam_app/lib/screens/delete_confirm.dart)):
what goes ("Delete "<name>"?", with a line under it where there's more to
say), **Cancel** and the delete button (**Delete**, or **Remove** for a
shared capture), and a **Don't ask again** checkbox, unticked.

## The kinds of delete

Each kind asks, or doesn't, on its own:

| Kind | Where | Meta key |
|---|---|---|
| A capture of the user's own | Home, a card's ⋮ menu, **Delete** ([library](library.md)) | `capture` |
| A capture shared with the user | Home, a card's ⋮ menu, **Remove** ([shared captures](shared-captures.md)) | `shared-capture` |
| One of a capture's files | the event screen's list, **Delete file** ([event screen](event-screen.md)); the play-along sidebar's Delete on its row ([Cam](cam.md#deleting-from-the-sidebar)) | `file` |
| One of a reader's own files | the event screen's **Your files**, Delete ([contributions](contributions.md)); the play-along sidebar's Delete on its row (their takes) | `contribution` |

The list and the play-along sidebar (beside the Text view, in Cam, on
the file screen) delete a file through the same code
([`file_delete.dart`](../tabcam_app/lib/screens/file_delete.dart),
`deleteFile`), so they ask, or don't, as one: Don't ask again ticked in
the sidebar holds in the list too, and the other way round. The file
screen's own **Delete** (its app bar's) never asked and still doesn't
(it deletes the file and goes back to the list).

## Don't ask again

- Ticked and confirmed, the delete goes ahead and that kind no longer
  asks on this device: the next one is deleted at once. Other kinds still
  ask (skipping a file's confirm doesn't skip a capture's).
- Ticked and cancelled, nothing changes: nothing is deleted and it asks
  next time, the box unticked again.
- What no longer asks is kept on the device (the library's
  `deleteconfirms` meta file, `{"skip": ["file", …]}`; letters and digits
  only, since on the apps it names a file and the store refuses anything
  else), not synced: each device asks until it's told not to.
- On the web it's kept in the browser's localStorage, as every device
  setting is ([library](library.md#device-settings)), so it lasts
  reloads and closing the tab; only where the browser refuses storage (a
  private window, say) does it last only until the tab is reloaded.
  Signing out or deleting the account keeps it, as on the apps: it's the
  device's, not the account's.

## Ask before deleting

The way back is on the **Profile** tab, a device setting under Language
([navigation](navigation.md#profile)): **Ask before deleting**, a switch.
On (the default) when every kind asks: "Deleting a capture or a file asks
first, on this device." Off once any kind doesn't: "Some deletes happen
at once, without asking. Turn it on to be asked again." Turned on, every
kind asks again. It only turns them on: while every kind asks it's on and
can't be switched off, since only a confirm's **Don't ask again** stops
one asking, so a stray tap on Profile never stops every confirm.

## What always asks

Account-level confirms aren't these: **Delete account** always asks with
its own dialog, which has no Don't ask again
([cloud sync](cloud-sync.md#deleting-the-account)), and nothing here
changes it. Other confirms that aren't deletes (Rescan's, discarding
Cam's untaken pages) aren't either.

## Tests

`test/delete_confirm_test.dart` (and `test/meta_names_test.dart` for
every meta name): the meta name is one the apps' store takes (and the file test runs on a store that refuses any other, as the
apps' does); the checkbox shows, unticked; ticked and cancelled nothing
is deleted and it asks again; ticked and confirmed the file is deleted,
the next file's delete doesn't ask, and the setting is read back from the
device's store; a skipped file confirm leaves the capture's asking;
Profile's switch shows off, on brings every kind's confirm back, and then
can't be switched off; removing a shared capture, from its card, asks
though captures don't, and its skip leaves the others asking; a reader's
own file, under Your files, asks though files don't, its skip leaves the
others asking and the next one goes at once; deleting the account still
asks, with no checkbox.
