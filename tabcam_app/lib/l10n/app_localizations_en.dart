// ignore: unused_import
import 'package:intl/intl.dart' as intl;

import 'app_localizations.dart';

// ignore_for_file: type=lint

/// The translations for English (`en`).
class AppLocalizationsEn extends AppLocalizations {
  AppLocalizationsEn([String locale = 'en']) : super(locale);

  @override
  String get languageTitle => 'Language';

  @override
  String get languageSystem => 'Device\'s language';

  @override
  String get accountSignIn => 'Sign in';

  @override
  String get accountSignInIntro =>
      'Sign in to read tabs, share, and have your events backed up on every device you sign in on.';

  @override
  String get accountSignInPremium =>
      'Signed in, TabCam Premium transcribes your scans in the cloud as they sync.';

  @override
  String get accountSignInWithGoogle => 'Sign in with Google';

  @override
  String accountRole(String role) {
    return 'Role: $role';
  }

  @override
  String get accountSyncNow => 'Sync now';

  @override
  String get accountSignOut => 'Sign out';

  @override
  String get accountSignOutNote =>
      'Signing out keeps your events on this device.';

  @override
  String get accountChecking => 'Checking…';

  @override
  String get accountRolePremium => 'Premium';

  @override
  String get accountRoleFree => 'Free';

  @override
  String get accountRoleFreeUnchecked => 'Free (couldn\'t check)';

  @override
  String get accountSyncOff => 'Not syncing';

  @override
  String get accountSyncing => 'Syncing…';

  @override
  String get accountSyncFailed => 'Sync failed';

  @override
  String accountSyncedAt(String time) {
    return 'Synced at $time';
  }

  @override
  String get accountSynced => 'Synced';

  @override
  String accountSyncUploaded(int count) {
    return '$count uploaded';
  }

  @override
  String accountSyncDownloaded(int count) {
    return '$count downloaded';
  }

  @override
  String accountSyncFailedHttp(String status) {
    return 'Sync failed (HTTP $status)';
  }

  @override
  String accountSyncFailedBecause(String reason) {
    return 'Sync failed: $reason';
  }

  @override
  String get accountSignInAgainToSync => 'Sign in again to sync';

  @override
  String accountSyncClockOff(int minutes) {
    return 'This device\'s clock is off by $minutes min: set it to the right time to sync';
  }

  @override
  String get accountSignInAgain => 'Sign in again';

  @override
  String get accountPremiumCheckFailed => 'Couldn\'t check Premium';

  @override
  String get accountPremiumCheckFailedNow =>
      'Couldn\'t check Premium right now';

  @override
  String get accountPremiumTitle => 'TabCam Premium';

  @override
  String get accountPremiumActive =>
      'Your scans are transcribed in the cloud as they sync: the text tab appears on the event by itself.';

  @override
  String accountPremiumUntil(String date) {
    return 'Premium until $date.';
  }

  @override
  String accountPremiumInactive(String email) {
    return 'TabCam Premium isn\'t active for $email.';
  }

  @override
  String accountPremiumOffer(String email) {
    return 'Have every scan transcribed automatically in the cloud, more accurately than on the phone, and read tabs on the web too. \$10 a month or \$100 a year: subscribe with $email.';
  }

  @override
  String get accountPremiumUpgrade => 'Upgrade';

  @override
  String get accountPremiumVoucher => 'Redeem a voucher';

  @override
  String get accountPremiumCheckAgain => 'Check again';

  @override
  String accountPremiumCouldntOpen(String url) {
    return 'Couldn\'t open $url';
  }

  @override
  String get accountPeopleCanEdit => 'Can edit';

  @override
  String get accountPeopleReadOnly => 'Can view and add';

  @override
  String get accountSignInToShare => 'Sign in to share';

  @override
  String get accountSignInAgainToShare => 'Sign in again to share';

  @override
  String accountShareFailedHttp(String status) {
    return 'Sharing failed (HTTP $status)';
  }

  @override
  String get accountShareLink => 'Link';

  @override
  String get accountShareLinkNeedsSync => 'Needs sign-in and cloud sync';

  @override
  String get accountShareLinkDetail =>
      'Opens this capture in TabCam, for you and the people it\'s shared with';

  @override
  String get accountSharePdf => 'PDF';

  @override
  String get accountSharePdfHidden =>
      'The text tab and links (the photos and scans are hidden)';

  @override
  String get accountSharePdfDetail =>
      'Every photo and scan in one PDF, plus the text tab and links';

  @override
  String get accountShareText => 'Text';

  @override
  String get accountShareTextDetail => 'The text tab and links, as plain text';

  @override
  String get accountShareTextNone =>
      'No text tab yet: it\'s read after each capture';

  @override
  String get accountShareFiles => 'Files';

  @override
  String get accountShareFilesHidden =>
      'A zip of the videos, recordings, PDFs, the text tab and links (the photos and scans are hidden)';

  @override
  String get accountShareFilesDetail =>
      'A zip of everything: photos, scans, videos, recordings, PDFs, the text tab and links';

  @override
  String accountShareFailed(String error) {
    return 'Couldn\'t share: $error';
  }

  @override
  String get accountExportLinks => 'Links';

  @override
  String get accountSignInNotSetUp => 'Sign-in isn\'t set up in this build.';

  @override
  String accountGoogleUnavailable(String reason) {
    return 'Google sign-in is unavailable: $reason';
  }

  @override
  String get eventCouldntAdd => 'Couldn\'t add';

  @override
  String eventSkippedFiles(int count) {
    String _temp0 = intl.Intl.pluralLogic(
      count,
      locale: localeName,
      other: '$count files aren\'t',
      one: '1 file isn\'t',
    );
    return '$_temp0 a photo or video, so not added.';
  }

  @override
  String get eventAddedHidden => 'Added. Images are hidden on this capture.';

  @override
  String get eventPremiumHint =>
      'TabCam Premium transcribes your scans automatically.';

  @override
  String get eventUpgrade => 'Upgrade';

  @override
  String get eventNotNow => 'Not now';

  @override
  String get eventNothingToRead =>
      'Nothing to read: add a scan, a photo or a PDF.';

  @override
  String get eventReadingTab => 'Reading the tab…';

  @override
  String get eventInCloud =>
      'Transcribing in the cloud: about 1 to 3 minutes a page. The text appears here when it\'s done, even if you leave.';

  @override
  String get eventNoTab =>
      'No tab found in the pages. Try rescanning closer and flatter.';

  @override
  String get eventReadAgain => 'Read again';

  @override
  String get eventRescanTitle => 'Rescan the pages?';

  @override
  String get eventRescanBody =>
      'Every photo and PDF is read again. A tab found replaces the current text, even if you edited it or marked it verified; if none is found, the text is kept.';

  @override
  String eventRescanKept(String reason) {
    return '$reason The text was kept.';
  }

  @override
  String get eventReadFailed => 'Reading the tab failed.';

  @override
  String get eventReadUnsupported =>
      'Reading tabs needs the Android or iOS app, or TabCam Premium.';

  @override
  String get eventReadNeedsSignIn => 'Reading tabs needs you signed in.';

  @override
  String get eventSignIn => 'Sign in';

  @override
  String get eventNoTextYet => 'No text yet.';

  @override
  String get eventNotReadYet => 'Not read yet.';

  @override
  String get eventRead => 'Read';

  @override
  String get eventKeepOnePage =>
      'An event keeps at least one page; delete the event instead.';

  @override
  String get eventRename => 'Rename';

  @override
  String get eventClone => 'Clone';

  @override
  String get eventShare => 'Share';

  @override
  String get eventFiles => 'Files';

  @override
  String eventFilePage(int number) {
    return 'Page $number';
  }

  @override
  String eventFileVideo(int number) {
    return 'Video $number';
  }

  @override
  String eventFilePdf(int number) {
    return 'PDF $number';
  }

  @override
  String eventFileRecording(int number) {
    return 'Recording $number';
  }

  @override
  String get eventText => 'Text';

  @override
  String get eventAdd => 'Add';

  @override
  String get eventRotate => 'Rotate';

  @override
  String get eventCouldntRotate => 'Couldn\'t rotate';

  @override
  String get eventDelete => 'Delete';

  @override
  String get eventDeleteFile => 'Delete file';

  @override
  String get eventDownload => 'Download';

  @override
  String get eventDownloadAll => 'Download all';

  @override
  String get eventCouldntDownload => 'Couldn\'t download';

  @override
  String get eventFileMore => 'More';

  @override
  String get eventCouldntDelete => 'Couldn\'t delete';

  @override
  String get eventReorder => 'Reorder';

  @override
  String get eventCouldntReorder => 'Couldn\'t reorder';

  @override
  String get eventViewOriginal => 'Original';

  @override
  String get eventViewScan => 'Scan';

  @override
  String get eventFilterTab => 'Tab';

  @override
  String get eventAddScan => 'Scan pages';

  @override
  String get eventAddScanDetail => 'More tab pages, with the camera';

  @override
  String get eventAddLibrary => 'Photos & videos';

  @override
  String get eventAddLibraryDetail => 'From your photo library';

  @override
  String get eventAddFiles => 'Files';

  @override
  String get eventAddFilesDetail => 'Image, video, audio and PDF files';

  @override
  String get eventAddLink => 'Link';

  @override
  String get eventAddLinkDetail => 'A lesson, a recording, the song online';

  @override
  String eventSharedBy(String owner, String access) {
    return 'Shared by $owner · $access';
  }

  @override
  String get eventReadOnly => 'Can view and add';

  @override
  String get eventByLink => 'Opened by its link · Read only';

  @override
  String linkTabImporting(String site) {
    return 'Importing the page from $site…';
  }

  @override
  String linkTabImported(String site) {
    return 'The page from $site was added as a PDF, to read its tab.';
  }

  @override
  String linkTabPremium(String site) {
    return 'Link added. On the web, importing the page from $site needs TabCam Premium.';
  }

  @override
  String linkTabFailed(String site) {
    return 'Link added. Couldn\'t import the page from $site.';
  }

  @override
  String get linkSignIn => 'Sign in';

  @override
  String get linkOpening => 'Opening the capture…';

  @override
  String get linkTryAgain => 'Try again';

  @override
  String get linkUnavailable =>
      'This capture can\'t be opened. The link may be wrong, its owner may have deleted it, or you may be offline.';

  @override
  String get eventCanEdit => 'Can edit';

  @override
  String eventClonedAs(String title) {
    return 'Cloned as \"$title\"';
  }

  @override
  String eventCouldntClone(String error) {
    return 'Couldn\'t clone: $error';
  }

  @override
  String get eventName => 'Name';

  @override
  String get eventStudy => 'Study';

  @override
  String get eventStudyHelp => 'Optional: groups related captures';

  @override
  String get eventCancel => 'Cancel';

  @override
  String get eventSave => 'Save';

  @override
  String get eventGateReadTabTitle => 'Sign in to read tabs';

  @override
  String get eventGateReadTabDetail =>
      'Reading a tab into text needs you signed in.';

  @override
  String get eventGateShareTitle => 'Sign in to share';

  @override
  String get eventGateShareDetail => 'Sharing needs you signed in.';

  @override
  String eventGateBody(String detail) {
    return '$detail Signed out, you can still scan and add to your captures; they stay on this device.';
  }

  @override
  String get eventSignInGoogle => 'Sign in with Google';

  @override
  String get eventNoCamera => 'No camera found.';

  @override
  String get eventCameraNotAllowed =>
      'The camera isn\'t allowed: let TabCam use it in the browser\'s site settings.';

  @override
  String eventCameraFailed(String error) {
    return 'The camera failed: $error';
  }

  @override
  String eventCouldntTakePicture(String error) {
    return 'Couldn\'t take the picture: $error';
  }

  @override
  String eventDiscardPages(int count) {
    String _temp0 = intl.Intl.pluralLogic(
      count,
      locale: localeName,
      other: '$count pages',
      one: '1 page',
    );
    return 'Discard $_temp0?';
  }

  @override
  String get eventKeepScanning => 'Keep scanning';

  @override
  String get eventDiscard => 'Discard';

  @override
  String get eventScanTitle => 'Scan';

  @override
  String eventPageCount(int count) {
    String _temp0 = intl.Intl.pluralLogic(
      count,
      locale: localeName,
      other: '$count pages',
      one: '1 page',
    );
    return '$_temp0';
  }

  @override
  String get eventFlipCamera => 'Flip camera';

  @override
  String get eventCam => 'Cam';

  @override
  String get camRec => 'Rec';

  @override
  String get camStop => 'Stop';

  @override
  String get camPlay => 'Play';

  @override
  String get camPrevious => 'Previous line';

  @override
  String get camNext => 'Next line';

  @override
  String get camNoTab =>
      'No text tab yet: read the capture\'s tab to play along with it.';

  @override
  String camTake(int number) {
    return 'Take $number';
  }

  @override
  String camSaved(String name) {
    return '$name added to the capture';
  }

  @override
  String camCouldntRecord(String error) {
    return 'Couldn\'t record: $error';
  }

  @override
  String get camAddingTab => 'Adding the tab to the video…';

  @override
  String camNoOverlay(String reason) {
    return 'The take was saved without the tab: $reason';
  }

  @override
  String camRecordingNoTab(String reason) {
    return 'Recording without the tab: $reason';
  }

  @override
  String get camAlong => 'Play along with a file';

  @override
  String get camAlongHide => 'Hide the files to play along';

  @override
  String get camAlongTitle => 'Play along';

  @override
  String get camAlongPlay => 'Play (space)';

  @override
  String get camAlongPause => 'Pause (space)';

  @override
  String get camAlongBack => 'Back 10 seconds';

  @override
  String get camAlongForward => 'Forward 10 seconds';

  @override
  String get camAlongRepeatOn => 'Repeat on: it starts over at its end';

  @override
  String get camAlongRepeatOff => 'Repeat off';

  @override
  String camAlongSection(String start, String end) {
    return 'Section $start–$end';
  }

  @override
  String get camAlongSectionStart => 'Start the section here';

  @override
  String get camAlongSectionEnd => 'End the section here';

  @override
  String get camAlongSectionClear => 'Play all of it';

  @override
  String get camAlongStop => 'Stop';

  @override
  String get camHeadsOn =>
      'Head gestures on: nod up or right for the next line, down or left for the one before';

  @override
  String get camHeadsOff => 'Head gestures off';

  @override
  String get camNotAllowed =>
      'The camera or microphone isn\'t allowed: let TabCam use them in the settings.';

  @override
  String get eventDone => 'Done';

  @override
  String get eventTakePicture => 'Take a picture';

  @override
  String get eventChoosePhotos => 'Choose photos instead';

  @override
  String get homeTabHome => 'Home';

  @override
  String get homeTabCapture => 'Capture';

  @override
  String get homeTabProfile => 'Profile';

  @override
  String homeSignedInAs(String identity) {
    return 'Signed in as $identity';
  }

  @override
  String get homeLinkNotHere => 'That capture isn\'t on this device.';

  @override
  String get homeLinkSignIn =>
      'Sign in (Profile) to open the capture in this link.';

  @override
  String get homeLinkNotShared =>
      'That capture isn\'t shared with you. Ask its owner to share it with your email address.';

  @override
  String homeSaved(String title, String contents) {
    return 'Saved \"$title\" ($contents)';
  }

  @override
  String get homeOpen => 'Open';

  @override
  String homeScanFailed(String error) {
    return 'Couldn\'t scan: $error';
  }

  @override
  String get scanCameraNotAllowed =>
      'the camera isn\'t allowed. Let TabCam use it in the settings.';

  @override
  String homeAddFailed(String error) {
    return 'Couldn\'t add: $error';
  }

  @override
  String homeSkipped(int count) {
    String _temp0 = intl.Intl.pluralLogic(
      count,
      locale: localeName,
      other: '$count files aren\'t a photo or video, so not added.',
      one: '1 file isn\'t a photo or video, so not added.',
    );
    return '$_temp0';
  }

  @override
  String homePages(int count) {
    String _temp0 = intl.Intl.pluralLogic(
      count,
      locale: localeName,
      other: '$count pages',
      one: '1 page',
    );
    return '$_temp0';
  }

  @override
  String homeVideos(int count) {
    String _temp0 = intl.Intl.pluralLogic(
      count,
      locale: localeName,
      other: '$count videos',
      one: '1 video',
    );
    return '$_temp0';
  }

  @override
  String homeAudio(int count) {
    String _temp0 = intl.Intl.pluralLogic(
      count,
      locale: localeName,
      other: '$count recordings',
      one: '1 recording',
    );
    return '$_temp0';
  }

  @override
  String homePdfs(int count) {
    String _temp0 = intl.Intl.pluralLogic(
      count,
      locale: localeName,
      other: '$count PDFs',
      one: '1 PDF',
    );
    return '$_temp0';
  }

  @override
  String homeLinks(int count) {
    String _temp0 = intl.Intl.pluralLogic(
      count,
      locale: localeName,
      other: '$count links',
      one: '1 link',
    );
    return '$_temp0';
  }

  @override
  String get homeScan => 'Scan';

  @override
  String get homeScanDetail =>
      'With the camera: the page is found, straightened and cleaned up, and you can take several in a row.';

  @override
  String get homeAdd => 'Add';

  @override
  String get homeAddPhotos => 'Photos & videos';

  @override
  String get homeAddPhotosDetail => 'From your photo library';

  @override
  String get homeAddFiles => 'Files';

  @override
  String get homeAddFilesDetail => 'Image and video files';

  @override
  String get homeAddLink => 'Link';

  @override
  String get homeAddLinkDetail => 'A lesson, a backing track, a video';

  @override
  String get homeNoSignIn =>
      'Sign-in isn\'t set up in this build: your events stay on this device.';

  @override
  String get homeAbout => 'About';

  @override
  String get homeDevelopmentBuild => '(development build)';

  @override
  String get homeAboutDetail =>
      'Scan guitar tabs, read them as text, and share them.';

  @override
  String get homeLicenses => 'Licenses';

  @override
  String get homeLibraryMine => 'My captures';

  @override
  String get homeLibraryMineEmpty =>
      'Nothing of your own yet: go to Capture to add some.';

  @override
  String get homeLibraryShared => 'Shared with me';

  @override
  String get homeSearch => 'Search captures';

  @override
  String get homeSearchClear => 'Clear search';

  @override
  String homeSearchNone(String query) {
    return 'No captures match “$query”';
  }

  @override
  String get homeLibraryEmpty => 'No tabs yet';

  @override
  String get homeLibraryLoading => 'Loading your captures…';

  @override
  String get homeLibraryLoadFailed => 'Your captures couldn\'t be loaded';

  @override
  String get homeLibraryTryAgain => 'Try again';

  @override
  String get homeLibraryEmptyDetail =>
      'Go to Capture to scan a tab with the camera (the page is found, straightened and cleaned up for you), or to add photos, videos, files and links.';

  @override
  String homeLibraryRemoveTitle(String title) {
    return 'Remove \"$title\"?';
  }

  @override
  String homeLibraryRemoveBody(String owner) {
    return 'It goes from your library. $owner keeps it, and can share it with you again.';
  }

  @override
  String get homeLibraryCancel => 'Cancel';

  @override
  String get homeLibraryRemove => 'Remove';

  @override
  String homeLibraryRemoveFailed(String error) {
    return 'Couldn\'t remove: $error';
  }

  @override
  String homeLibraryDeleteTitle(String title) {
    return 'Delete \"$title\"?';
  }

  @override
  String get homeLibraryDeleteBody => 'Its pages and text tab are deleted too.';

  @override
  String get homeLibraryDelete => 'Delete';

  @override
  String get homeLibraryImagesHidden => 'images hidden';

  @override
  String get homeLibraryText => 'text';

  @override
  String homeLibrarySharedBy(String owner) {
    return 'shared by $owner';
  }

  @override
  String get homeLibraryMore => 'More';

  @override
  String get homeLibraryRename => 'Rename';

  @override
  String get homeLibraryShare => 'Share';

  @override
  String get homeLibraryClone => 'Clone';

  @override
  String get homeMaintenanceDefault =>
      'Sorry, TabCam is down for maintenance. Please try again later.';

  @override
  String get textViewTabCopied => 'Tab copied';

  @override
  String get textViewPutCursorOnFret => 'Put the cursor on a fret number';

  @override
  String get textViewFixPremium => 'Fix is part of TabCam Premium';

  @override
  String get textViewUpgrade => 'Upgrade';

  @override
  String get textViewFixSignIn => 'Sign in again to use Fix';

  @override
  String get textViewFixUnavailable => 'Fix isn\'t available yet';

  @override
  String get textViewCheckFailed =>
      'Couldn\'t check online right now. Try again later.';

  @override
  String get textViewTextChanged => 'The text changed meanwhile: tap Fix again';

  @override
  String get textViewTabMatches => 'The tab matches the one found online';

  @override
  String get textViewTabNotFound => 'Couldn\'t find this song\'s tab online';

  @override
  String textViewApplied(int count) {
    String _temp0 = intl.Intl.pluralLogic(
      count,
      locale: localeName,
      other: '$count corrections applied',
      one: '1 correction applied',
    );
    return '$_temp0';
  }

  @override
  String get textViewReview => 'Review';

  @override
  String get textViewReviewTip => 'Show the scanned pages beside the text';

  @override
  String textViewReviewPage(int number) {
    return 'Page $number';
  }

  @override
  String get textViewCopy => 'Copy';

  @override
  String get textViewFix => 'Fix';

  @override
  String get textViewRescan => 'Rescan';

  @override
  String get textViewRescanTip => 'Read the tab from the pages again';

  @override
  String get textViewRescanning => 'Rescanning the pages…';

  @override
  String get textViewLookingOnline => 'Looking for the song\'s tab online…';

  @override
  String get textViewCorrect => 'Verified';

  @override
  String get textViewMarkedCorrect => 'Verified: the event opens on its text';

  @override
  String get textViewMarkCorrect => 'Mark the reading verified';

  @override
  String get textViewFretDown => 'Fret down (the number under the cursor)';

  @override
  String get textViewFretUp => 'Fret up (the number under the cursor)';

  @override
  String get textViewNoteUp => 'Note up a string (cycles round)';

  @override
  String get textViewNoteDown => 'Note down a string (cycles round)';

  @override
  String get textViewPutCursorOnNote =>
      'Put the cursor on a note on a string line';

  @override
  String get textViewNoStringFree =>
      'No other string has room for this note there';

  @override
  String get textViewOvertypeOn =>
      'Overtype: typing replaces characters, columns stay put';

  @override
  String get textViewOvertypeOff => 'Insert: typing pushes the line right';

  @override
  String get textViewOvertype => 'Overtype';

  @override
  String get textViewSongDialogTitle => 'Fix from the song\'s tab';

  @override
  String get textViewSongLabel => 'Song and artist';

  @override
  String get textViewSongHelper =>
      'Looked up on tab sites to correct the reading';

  @override
  String get textViewCancel => 'Cancel';

  @override
  String get textViewCheck => 'Check';

  @override
  String get textViewRemoved => 'removed';

  @override
  String get textViewPrevious => 'Previous';

  @override
  String get textViewNext => 'Next';

  @override
  String textViewPosition(int index, int total) {
    return '$index of $total';
  }

  @override
  String textViewLineColumn(int line, int column) {
    return 'Line $line, column $column';
  }

  @override
  String textViewLineStringColumn(int line, String string, int column) {
    return 'Line $line ($string), column $column';
  }

  @override
  String get textViewReject => 'Reject';

  @override
  String get textViewRejected => 'Rejected';

  @override
  String get textViewAccept => 'Accept';

  @override
  String get textViewAccepted => 'Accepted';

  @override
  String get textViewAll => 'All';

  @override
  String get textViewAcceptAll => 'Accept all';

  @override
  String get textViewRejectAll => 'Reject all';

  @override
  String get textViewAllMenu => 'All…';

  @override
  String textViewDoneCount(int decided, int total) {
    return 'Done ($decided/$total)';
  }

  @override
  String get textViewDone => 'Done';

  @override
  String get textViewNoTextTab => 'No text tab yet';

  @override
  String get textViewHiddenNotRead =>
      'The images are hidden, and the tab hasn\'t been read.';

  @override
  String get textViewHiddenStillRead =>
      'The images are hidden. They\'re still read: the text appears here.';

  @override
  String get textViewTextTab => 'Text tab';

  @override
  String get textViewOpen => 'Open';

  @override
  String textViewCouldNotOpen(String url) {
    return 'Couldn\'t open $url';
  }

  @override
  String get textViewLinkCopied => 'Link copied';

  @override
  String get textViewAddLink => 'Add a link';

  @override
  String get textViewLink => 'Link';

  @override
  String get textViewEnterAddress => 'Enter a web address (https://…)';

  @override
  String get textViewTitleOptional => 'Title (optional)';

  @override
  String get textViewTitleHint => 'Lesson, recording…';

  @override
  String get textViewAdd => 'Add';

  @override
  String get textViewCantPlay => 'This video can\'t be played here';

  @override
  String get textViewVideo => 'Video';

  @override
  String get textViewAudio => 'Recording';

  @override
  String get textViewCantPlayAudio => 'This recording can\'t be played here';

  @override
  String get textViewPlay => 'Play';

  @override
  String get textViewPause => 'Pause';

  @override
  String get textViewCantShowPdf => 'This PDF can\'t be shown here';

  @override
  String get homePrivacyPolicy => 'Privacy policy';

  @override
  String get deleteAccountDone => 'Your TabCam account was deleted.';

  @override
  String get deleteAccountTitle => 'Delete your account?';

  @override
  String get deleteAccountThisDeletes => 'This deletes:';

  @override
  String get deleteAccountEvents =>
      'All your events, in the cloud and on this device.';

  @override
  String get deleteAccountShares =>
      'Your shares: the people you shared captures with lose them.';

  @override
  String get deleteAccountSharedWithYou =>
      'The captures shared with you: they stop showing here.';

  @override
  String get deleteAccountCantUndo => 'It can\'t be undone.';

  @override
  String get deleteAccountGoogleKept => 'Your Google account isn\'t deleted.';

  @override
  String get deleteAccountPremiumWeb =>
      'A TabCam Premium subscription isn\'t cancelled: cancel it on Substack, where you subscribed.';

  @override
  String get deleteAccountPremiumStore =>
      'A TabCam Premium subscription isn\'t cancelled: it\'s managed where you bought it.';

  @override
  String get deleteAccountOtherDevices =>
      'If TabCam is signed in on your other devices, sign out there first, so they don\'t upload their events again.';

  @override
  String get deleteAccountCancel => 'Cancel';

  @override
  String get deleteAccountButton => 'Delete account';

  @override
  String deleteAccountCouldnt(String error) {
    return 'Your account couldn\'t be deleted: $error';
  }

  @override
  String get deleteAccountDeleting => 'Deleting your account';

  @override
  String get deleteAccountDeleted => 'Account deleted';

  @override
  String get deleteAccountNotDeleted => 'Account not deleted';

  @override
  String get deleteAccountClose => 'Close';

  @override
  String get deleteAccountTryAgain => 'Try again';

  @override
  String get deleteAccountStepCloud => 'Deleting your files in the cloud…';

  @override
  String deleteAccountStepCloudCount(int done, int total) {
    return 'Deleting your files in the cloud ($done of $total)…';
  }

  @override
  String get deleteAccountStepShares => 'Deleting your shares…';

  @override
  String get deleteAccountStepDevice => 'Deleting your events on this device…';

  @override
  String deleteAccountStepDeviceCount(int done, int total) {
    return 'Deleting your events on this device ($done of $total)…';
  }

  @override
  String get deleteAccountStepSignOut => 'Signing out…';

  @override
  String get deleteAccountSignInAgain =>
      'Sign in again to delete your account.';

  @override
  String get deleteAccountSignedOutMeanwhile =>
      'You signed out before your account was deleted. Your files in the cloud were deleted; sign in and delete it again to finish.';

  @override
  String deleteAccountSharesFailed(String reason) {
    return 'Your files in the cloud were deleted, but not your shares: $reason. Delete your account again to finish.';
  }

  @override
  String get deleteAccountSignInAgainShort => 'sign in again';

  @override
  String deleteAccountSharesFailedBecause(String error) {
    return 'Your files in the cloud were deleted, but not your shares ($error). Delete your account again to finish.';
  }

  @override
  String deleteAccountLeftHere(String error) {
    return 'Your account was deleted and you were signed out, but some events on this device couldn\'t be deleted ($error): delete them from Home.';
  }

  @override
  String deleteAccountSomeFiles(int failed, int total) {
    return '$failed of $total files in the cloud couldn\'t be deleted. Nothing else was deleted, and you are still signed in: try again.';
  }

  @override
  String get deleteAccountKeptAppearing =>
      'Files kept appearing in your cloud folder while it was being emptied. Nothing else was deleted: try again.';

  @override
  String deleteAccountFilesHttp(int status) {
    return 'Your files in the cloud couldn\'t be deleted (HTTP $status). Nothing else was deleted: try again.';
  }

  @override
  String deleteAccountFilesCognito(String type) {
    return 'Your files in the cloud couldn\'t be deleted ($type). Nothing was deleted: try again.';
  }

  @override
  String deleteAccountFilesError(String error) {
    return 'Your files in the cloud couldn\'t be deleted ($error). Nothing else was deleted: try again.';
  }

  @override
  String get accountPremiumNeedsGoogle => 'Premium needs Google sign-in';

  @override
  String get accountSignInWithApple => 'Sign in with Apple';

  @override
  String get accountAppleSignInFailed => 'Sign in with Apple failed';

  @override
  String get accountAppleSignInExpired =>
      'Your Apple sign-in expired: sign in again.';

  @override
  String get accountAppleUnavailable =>
      'Sign in with Apple isn\'t available on this device.';

  @override
  String accountPrivateEmail(String provider) {
    return '$provider ID (private email)';
  }

  @override
  String get profileLinkedAccounts => 'Linked accounts';

  @override
  String get profileLinkedIntro =>
      'Any of these accounts reaches the same captures, and the profile has all their roles.';

  @override
  String get profileOwner => 'Owner';

  @override
  String get profileThisAccount => 'This account';

  @override
  String get profileUnlink => 'Unlink';

  @override
  String get profileLinkAnother => 'Link another account';

  @override
  String get profileGetCode => 'Get a link code';

  @override
  String get profileCodeHow =>
      'Within 10 minutes, sign in with the other account and enter this code under Linked accounts.';

  @override
  String get profileCopyCode => 'Copy the code';

  @override
  String get profileHaveCode =>
      'Have a code from your other account? Enter it to link this account to it.';

  @override
  String get profileCodeLabel => 'Link code';

  @override
  String get profileLinkThis => 'Link this account';

  @override
  String get profileLinkThisNote =>
      'This account then uses the other account\'s profile and captures.';

  @override
  String get profileCodeWrong => 'That code is wrong, already used or expired.';

  @override
  String get profileCantLink =>
      'This account can\'t be linked: it has captures in the cloud of its own, or other accounts linked to it.';

  @override
  String get profileTooManyTries =>
      'Too many tries: wait a minute and try again.';

  @override
  String profileLinkFailed(String error) {
    return 'Couldn\'t link: $error';
  }

  @override
  String profileLinked(String profileId) {
    return 'Linked: this account now uses the profile $profileId';
  }

  @override
  String profileId(String profileId) {
    return 'Profile: $profileId';
  }

  @override
  String profileRoles(String roles) {
    return 'Roles: $roles';
  }

  @override
  String get profileNotOwner =>
      'Only the profile\'s owner can delete it. To leave it, unlink this account under Linked accounts.';

  @override
  String accountSignedInWith(String provider) {
    return 'Signed in with $provider';
  }

  @override
  String get accountDeleteNote =>
      'Deletes your events in the cloud and on this device, and your shares.';

  @override
  String get homeAddDocument => 'Document';

  @override
  String get homeAddDocumentDetail => 'PDF files';

  @override
  String get eventAddDocument => 'Document';

  @override
  String get eventAddDocumentDetail => 'PDF files';

  @override
  String get eventRenameFile => 'Rename file';

  @override
  String get eventFileDetails => 'Details';

  @override
  String get eventLinkCopied => 'Link copied';

  @override
  String get textViewFixLinedUp =>
      'Tab lined up: every string\'s bars and end match';

  @override
  String get textViewFixAlreadyLinedUp => 'The tab\'s strings already line up';

  @override
  String get textViewFixLinedUpPremium =>
      'Tab lined up. Checking it against the song online is part of TabCam Premium.';

  @override
  String get welcomeBody =>
      'Scan guitar tabs, read them as text, and share them. Sign in to start: your captures are kept on every device you sign in on.';

  @override
  String get dropFilesToAdd => 'Drop files to add';

  @override
  String get deleteAccountAppleCanceled =>
      'Your files in the cloud were deleted, but not your account: Apple\'s confirmation was canceled. Delete your account again to finish.';

  @override
  String get deleteAccountAppleOtherId =>
      'That\'s another Apple ID: confirm with the Apple ID you signed in with.';

  @override
  String get eventYourFiles => 'Your files';

  @override
  String eventYourFilesDetail(String owner) {
    return 'Only you and $owner see these';
  }

  @override
  String eventFilesFrom(String person) {
    return 'From $person';
  }

  @override
  String get eventSomeone => 'someone';

  @override
  String get eventPublishHint => 'Only you see these until you publish them';

  @override
  String get eventPublish => 'Publish: everyone sees it';

  @override
  String get eventUnpublish => 'Published: tap to take it back';

  @override
  String get eventPublished => 'Published';

  @override
  String eventPublishedSnack(String name) {
    return '$name published: everyone sees it now';
  }

  @override
  String get eventCouldntPublish => 'Couldn\'t publish';

  @override
  String get emailSignInButton => 'Sign in with email';

  @override
  String get emailSignInTitle => 'Sign in with email';

  @override
  String get emailSignInIntro =>
      'Type your email address: we\'ll send you a code to sign in with. No password.';

  @override
  String get emailSignInAddress => 'Email address';

  @override
  String get emailSignInSend => 'Send code';

  @override
  String emailSignInSent(String email) {
    return 'We sent a code to $email. Type it here, or tap the link in the email.';
  }

  @override
  String get emailSignInCode => 'Code';

  @override
  String get emailSignInVerify => 'Sign in';

  @override
  String get emailSignInResend => 'Send a new code';

  @override
  String get emailSignInOther => 'Use another address';

  @override
  String get emailSignInBadAddress => 'That isn\'t an email address.';

  @override
  String get emailSignInBadCode =>
      'That code isn\'t right, or it expired: check it, or send a new one.';

  @override
  String get emailSignInTooMany =>
      'Too many tries: wait a few minutes and try again.';

  @override
  String emailSignInFailed(String error) {
    return 'Couldn\'t sign in: $error';
  }

  @override
  String get emailSignInExpired => 'Your email sign-in expired: sign in again.';

  @override
  String get emailSignInUnavailable =>
      'Sign in with email isn\'t set up in this build.';

  @override
  String get ownTabsNote =>
      'TabCam is for musicians practicing with their own tabs. Only add what you have the right to use: tabs you wrote, your teacher\'s, ones you bought, or ones free to share.';
}
