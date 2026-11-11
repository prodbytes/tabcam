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
| One of a capture's files | the event screen's list, **Delete file** ([event screen](event-screen.md)) | `file` |
| One of a reader's own files | the event screen's **Your files**, Delete ([contributions](contributions.md)) | `contribution` |

The file screen's **Delete** never asked and still doesn't (it deletes
the file and goes back to the list).

## Don't ask again

- Ticked and confirmed, the delete goes ahead and that kind no longer
  asks on this device: the next one is deleted at once. Other kinds still
  ask (skipping a file's confirm doesn't skip a capture's).
- Ticked and cancelled, nothing changes: nothing is deleted and it asks
  next time, the box unticked again.
- What no longer asks is kept on the device (the library's
  `delete-confirms` meta file, `{"skip": ["file", …]}`), not synced: each
  device asks until it's told not to.

## Ask before deleting

The way back is on the **Profile** tab, a device setting under Language
([navigation](navigation.md#profile)): **Ask before deleting**, a switch.
On (the default) when every kind asks: "Deleting a capture or a file asks
first, on this device." Off once any kind doesn't: "Some deletes happen
at once, without asking. Turn it on to be asked again." Turned on, every
kind asks again; turned off, none does.

## What always asks

Account-level confirms aren't these: **Delete account** always asks with
its own dialog, which has no Don't ask again
([cloud sync](cloud-sync.md#deleting-the-account)), and nothing here
changes it. Other confirms that aren't deletes (Rescan's, discarding
Cam's untaken pages) aren't either.

## Tests

`test/delete_confirm_test.dart`: the checkbox shows, unticked; ticked and
cancelled nothing is deleted and it asks again; ticked and confirmed the
file is deleted, the next file's delete doesn't ask, and the setting is
read back from the device's store; a skipped file confirm leaves the
capture's asking; Profile's switch shows off, and on brings every kind's
confirm back (off skips them all); deleting the account still asks, with
no checkbox.
