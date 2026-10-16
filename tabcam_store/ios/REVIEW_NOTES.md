# App Review information (to finish before submitting)

`metadata/review_information/notes.txt` is the text for App Review's
**Notes** field (`bash scripts/store-upload-ios.sh` uploads it with
fastlane `deliver`). The rest of App Review's information is the
maintainer's to fill in, in App Store Connect or as
`metadata/review_information/*.txt` files that are **never committed**
(`.gitignore` ignores the folder's other files), which the same script
then uploads:

- **Contact**: `first_name.txt`, `last_name.txt`, `phone_number.txt`,
  `email_address.txt`.
- **Sign-in**: `demo_user.txt`, `demo_password.txt`, if a demo account
  is given: a dedicated Google test account the maintainer creates for
  review (not a personal one; 2-step verification off, or the reviewer
  can't sign in). It must not be invented here. The notes tell the
  reviewer that Sign in with Apple works with any Apple ID; Apple may
  still ask for a demo account. Before submitting, sign in with it once
  on a phone to check it works, and leave it with one or two captures of
  made-up riffs.
- **Attachment** (optional): a printed page of a made-up riff for the
  reviewer to scan.

The same test account serves Google Play's **App access** declaration
(Play Console → App content → App access), with the same steps.
