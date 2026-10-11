# App Review information (to finish before submitting)

`review_information/notes.txt` is the text for App Review's **Notes**
field (fastlane `deliver` reads it). The rest of App Review's
information is the maintainer's to fill in, in App Store Connect or as
`review_information/*.txt` files that are **never committed**:

- **Contact**: `first_name.txt`, `last_name.txt`, `phone_number.txt`,
  `email_address.txt`.
- **Sign-in**: `demo_user.txt`, `demo_password.txt`: a dedicated Google
  test account the maintainer creates for review (not a personal one;
  2-step verification off, or the reviewer can't sign in). It must not be
  invented here. Before submitting, sign in with it once on a phone to
  check it works, and leave it with one or two events of made-up riffs.
- **Attachment**: a printed page of a made-up riff for the reviewer to
  scan (see `notes.txt`, step 1).

Notes:

- Sign in with Apple (guideline 4.8) is still to do; while sign-in is
  Google only, review may reject the build ([app stores](../../specs/app-stores.md)).
- Delete account (step 5 of the notes) must be in the submitted build
  (pull request #47).
- The same test account serves Google Play's **App access** declaration
  (Play Console → App content → App access), with the same steps.
