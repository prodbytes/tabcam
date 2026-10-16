import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:flutter/widgets.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:intl/intl.dart' as intl;

import 'app_localizations_en.dart';
import 'app_localizations_es.dart';
import 'app_localizations_pt.dart';

// ignore_for_file: type=lint

/// Callers can lookup localized strings with an instance of AppLocalizations
/// returned by `AppLocalizations.of(context)`.
///
/// Applications need to include `AppLocalizations.delegate()` in their app's
/// `localizationDelegates` list, and the locales they support in the app's
/// `supportedLocales` list. For example:
///
/// ```dart
/// import 'l10n/app_localizations.dart';
///
/// return MaterialApp(
///   localizationsDelegates: AppLocalizations.localizationsDelegates,
///   supportedLocales: AppLocalizations.supportedLocales,
///   home: MyApplicationHome(),
/// );
/// ```
///
/// ## Update pubspec.yaml
///
/// Please make sure to update your pubspec.yaml to include the following
/// packages:
///
/// ```yaml
/// dependencies:
///   # Internationalization support.
///   flutter_localizations:
///     sdk: flutter
///   intl: any # Use the pinned version from flutter_localizations
///
///   # Rest of dependencies
/// ```
///
/// ## iOS Applications
///
/// iOS applications define key application metadata, including supported
/// locales, in an Info.plist file that is built into the application bundle.
/// To configure the locales supported by your app, you’ll need to edit this
/// file.
///
/// First, open your project’s ios/Runner.xcworkspace Xcode workspace file.
/// Then, in the Project Navigator, open the Info.plist file under the Runner
/// project’s Runner folder.
///
/// Next, select the Information Property List item, select Add Item from the
/// Editor menu, then select Localizations from the pop-up menu.
///
/// Select and expand the newly-created Localizations item then, for each
/// locale your application supports, add a new item and select the locale
/// you wish to add from the pop-up menu in the Value field. This list should
/// be consistent with the languages listed in the AppLocalizations.supportedLocales
/// property.
abstract class AppLocalizations {
  AppLocalizations(String locale)
    : localeName = intl.Intl.canonicalizedLocale(locale.toString());

  final String localeName;

  static AppLocalizations? of(BuildContext context) {
    return Localizations.of<AppLocalizations>(context, AppLocalizations);
  }

  static const LocalizationsDelegate<AppLocalizations> delegate =
      _AppLocalizationsDelegate();

  /// A list of this localizations delegate along with the default localizations
  /// delegates.
  ///
  /// Returns a list of localizations delegates containing this delegate along with
  /// GlobalMaterialLocalizations.delegate, GlobalCupertinoLocalizations.delegate,
  /// and GlobalWidgetsLocalizations.delegate.
  ///
  /// Additional delegates can be added by appending to this list in
  /// MaterialApp. This list does not have to be used at all if a custom list
  /// of delegates is preferred or required.
  static const List<LocalizationsDelegate<dynamic>> localizationsDelegates =
      <LocalizationsDelegate<dynamic>>[
        delegate,
        GlobalMaterialLocalizations.delegate,
        GlobalCupertinoLocalizations.delegate,
        GlobalWidgetsLocalizations.delegate,
      ];

  /// A list of this localizations delegate's supported locales.
  static const List<Locale> supportedLocales = <Locale>[
    Locale('en'),
    Locale('es'),
    Locale('pt'),
  ];

  /// Profile: the language setting's title
  ///
  /// In en, this message translates to:
  /// **'Language'**
  String get languageTitle;

  /// Profile: follow the device's language
  ///
  /// In en, this message translates to:
  /// **'Device\'s language'**
  String get languageSystem;

  /// Account: signed-out title
  ///
  /// In en, this message translates to:
  /// **'Sign in'**
  String get accountSignIn;

  /// Account: why to sign in
  ///
  /// In en, this message translates to:
  /// **'Sign in to read tabs, share, and have your events backed up on every device you sign in on.'**
  String get accountSignInIntro;

  /// Account: Premium note when signed out
  ///
  /// In en, this message translates to:
  /// **'Signed in, TabCam Premium transcribes your scans in the cloud as they sync.'**
  String get accountSignInPremium;

  /// Account: sign-in button
  ///
  /// In en, this message translates to:
  /// **'Sign in with Google'**
  String get accountSignInWithGoogle;

  /// Account: the user's role line
  ///
  /// In en, this message translates to:
  /// **'Role: {role}'**
  String accountRole(String role);

  /// Account: sync button
  ///
  /// In en, this message translates to:
  /// **'Sync now'**
  String get accountSyncNow;

  /// Account: sign-out button
  ///
  /// In en, this message translates to:
  /// **'Sign out'**
  String get accountSignOut;

  /// Account: note under Sign out
  ///
  /// In en, this message translates to:
  /// **'Signing out keeps your events on this device.'**
  String get accountSignOutNote;

  /// Account: Premium status being checked
  ///
  /// In en, this message translates to:
  /// **'Checking…'**
  String get accountChecking;

  /// Account: Premium role name
  ///
  /// In en, this message translates to:
  /// **'Premium'**
  String get accountRolePremium;

  /// Account: Free role name
  ///
  /// In en, this message translates to:
  /// **'Free'**
  String get accountRoleFree;

  /// Account: Free role when the check failed
  ///
  /// In en, this message translates to:
  /// **'Free (couldn\'t check)'**
  String get accountRoleFreeUnchecked;

  /// Account: sync status, signed out
  ///
  /// In en, this message translates to:
  /// **'Not syncing'**
  String get accountSyncOff;

  /// Account: sync status, in progress
  ///
  /// In en, this message translates to:
  /// **'Syncing…'**
  String get accountSyncing;

  /// Account: sync status, failed
  ///
  /// In en, this message translates to:
  /// **'Sync failed'**
  String get accountSyncFailed;

  /// Account: sync status with the time (HH:MM)
  ///
  /// In en, this message translates to:
  /// **'Synced at {time}'**
  String accountSyncedAt(String time);

  /// Account: sync status, done
  ///
  /// In en, this message translates to:
  /// **'Synced'**
  String get accountSynced;

  /// Sync summary: events uploaded
  ///
  /// In en, this message translates to:
  /// **'{count} uploaded'**
  String accountSyncUploaded(int count);

  /// Sync summary: events downloaded
  ///
  /// In en, this message translates to:
  /// **'{count} downloaded'**
  String accountSyncDownloaded(int count);

  /// Sync error with the HTTP status
  ///
  /// In en, this message translates to:
  /// **'Sync failed (HTTP {status})'**
  String accountSyncFailedHttp(String status);

  /// Sync error with its technical reason
  ///
  /// In en, this message translates to:
  /// **'Sync failed: {reason}'**
  String accountSyncFailedBecause(String reason);

  /// Sync error: session expired
  ///
  /// In en, this message translates to:
  /// **'Sign in again to sync'**
  String get accountSignInAgainToSync;

  /// Sync error: device clock skewed
  ///
  /// In en, this message translates to:
  /// **'This device\'s clock is off by {minutes} min: set it to the right time to sync'**
  String accountSyncClockOff(int minutes);

  /// Premium check error: session expired
  ///
  /// In en, this message translates to:
  /// **'Sign in again'**
  String get accountSignInAgain;

  /// Premium check error
  ///
  /// In en, this message translates to:
  /// **'Couldn\'t check Premium'**
  String get accountPremiumCheckFailed;

  /// Premium check error: service unavailable
  ///
  /// In en, this message translates to:
  /// **'Couldn\'t check Premium right now'**
  String get accountPremiumCheckFailedNow;

  /// Premium card title (product name)
  ///
  /// In en, this message translates to:
  /// **'TabCam Premium'**
  String get accountPremiumTitle;

  /// Premium card: what Premium does, for premium users
  ///
  /// In en, this message translates to:
  /// **'Your scans are transcribed in the cloud as they sync: the text tab appears on the event by itself.'**
  String get accountPremiumActive;

  /// Premium card: expiry date (YYYY-MM-DD)
  ///
  /// In en, this message translates to:
  /// **'Premium until {date}.'**
  String accountPremiumUntil(String date);

  /// Premium card in store apps: not active
  ///
  /// In en, this message translates to:
  /// **'TabCam Premium isn\'t active for {email}.'**
  String accountPremiumInactive(String email);

  /// Premium card: the upgrade offer
  ///
  /// In en, this message translates to:
  /// **'Have every scan transcribed automatically in the cloud, more accurately than on the phone, and read tabs on the web too. Subscribe with {email}.'**
  String accountPremiumOffer(String email);

  /// Premium card: upgrade button
  ///
  /// In en, this message translates to:
  /// **'Upgrade'**
  String get accountPremiumUpgrade;

  /// Premium card: voucher button
  ///
  /// In en, this message translates to:
  /// **'Redeem a voucher'**
  String get accountPremiumVoucher;

  /// Premium card: re-check button
  ///
  /// In en, this message translates to:
  /// **'Check again'**
  String get accountPremiumCheckAgain;

  /// Snackbar: a link didn't open
  ///
  /// In en, this message translates to:
  /// **'Couldn\'t open {url}'**
  String accountPremiumCouldntOpen(String url);

  /// People sheet title
  ///
  /// In en, this message translates to:
  /// **'Share with people'**
  String get accountPeopleTitle;

  /// People sheet: how sharing works
  ///
  /// In en, this message translates to:
  /// **'People you add find this capture when they sign in to TabCam with that email address. No email is sent.'**
  String get accountPeopleIntro;

  /// People sheet: email field label
  ///
  /// In en, this message translates to:
  /// **'Email'**
  String get accountPeopleEmail;

  /// People sheet: add button
  ///
  /// In en, this message translates to:
  /// **'Add'**
  String get accountPeopleAdd;

  /// People sheet: invalid email error
  ///
  /// In en, this message translates to:
  /// **'Enter an email address'**
  String get accountPeopleEnterEmail;

  /// People sheet: no one yet
  ///
  /// In en, this message translates to:
  /// **'Not shared yet.'**
  String get accountPeopleNone;

  /// People sheet: remove tooltip
  ///
  /// In en, this message translates to:
  /// **'Remove {email}'**
  String accountPeopleRemove(String email);

  /// People sheet: role menu tooltip
  ///
  /// In en, this message translates to:
  /// **'What they can do'**
  String get accountPeopleRoleTooltip;

  /// Share role: edit
  ///
  /// In en, this message translates to:
  /// **'Can edit'**
  String get accountPeopleCanEdit;

  /// Share role: read only
  ///
  /// In en, this message translates to:
  /// **'Read only'**
  String get accountPeopleReadOnly;

  /// Share error: signed out
  ///
  /// In en, this message translates to:
  /// **'Sign in to share'**
  String get accountSignInToShare;

  /// Share error: session expired
  ///
  /// In en, this message translates to:
  /// **'Sign in again to share'**
  String get accountSignInAgainToShare;

  /// Share API error with HTTP status
  ///
  /// In en, this message translates to:
  /// **'Sharing failed (HTTP {status})'**
  String accountShareFailedHttp(String status);

  /// Share sheet: link option
  ///
  /// In en, this message translates to:
  /// **'Link'**
  String get accountShareLink;

  /// Share sheet: link unavailable
  ///
  /// In en, this message translates to:
  /// **'Needs sign-in and cloud sync'**
  String get accountShareLinkNeedsSync;

  /// Share sheet: link option description
  ///
  /// In en, this message translates to:
  /// **'Opens this capture in TabCam, for you and the people it\'s shared with'**
  String get accountShareLinkDetail;

  /// Share sheet: PDF option
  ///
  /// In en, this message translates to:
  /// **'PDF'**
  String get accountSharePdf;

  /// Share sheet: PDF with images hidden
  ///
  /// In en, this message translates to:
  /// **'The text tab and links (the photos and scans are hidden)'**
  String get accountSharePdfHidden;

  /// Share sheet: PDF option description
  ///
  /// In en, this message translates to:
  /// **'Every photo and scan in one PDF, plus the text tab and links'**
  String get accountSharePdfDetail;

  /// Share sheet: text option
  ///
  /// In en, this message translates to:
  /// **'Text'**
  String get accountShareText;

  /// Share sheet: text option description
  ///
  /// In en, this message translates to:
  /// **'The text tab and links, as plain text'**
  String get accountShareTextDetail;

  /// Share sheet: text unavailable
  ///
  /// In en, this message translates to:
  /// **'No text tab yet: it\'s read after each capture'**
  String get accountShareTextNone;

  /// Share sheet: files option
  ///
  /// In en, this message translates to:
  /// **'Files'**
  String get accountShareFiles;

  /// Share sheet: files with images hidden
  ///
  /// In en, this message translates to:
  /// **'A zip of the videos, recordings, PDFs, the text tab and links (the photos and scans are hidden)'**
  String get accountShareFilesHidden;

  /// Share sheet: files option description
  ///
  /// In en, this message translates to:
  /// **'A zip of everything: photos, scans, videos, recordings, PDFs, the text tab and links'**
  String get accountShareFilesDetail;

  /// Snackbar: sharing failed
  ///
  /// In en, this message translates to:
  /// **'Couldn\'t share: {error}'**
  String accountShareFailed(String error);

  /// Exported PDF: heading of the links page
  ///
  /// In en, this message translates to:
  /// **'Links'**
  String get accountExportLinks;

  /// Account: sign-in not configured
  ///
  /// In en, this message translates to:
  /// **'Sign-in isn\'t set up in this build.'**
  String get accountSignInNotSetUp;

  /// Account: Google sign-in failed to start
  ///
  /// In en, this message translates to:
  /// **'Google sign-in is unavailable: {reason}'**
  String accountGoogleUnavailable(String reason);

  /// Event: Add failed (before ': error')
  ///
  /// In en, this message translates to:
  /// **'Couldn\'t add'**
  String get eventCouldntAdd;

  /// Event: snackbar, picked files that aren't media
  ///
  /// In en, this message translates to:
  /// **'{count, plural, =1{1 file isn\'t} other{{count} files aren\'t}} a photo or video, so not added.'**
  String eventSkippedFiles(int count);

  /// Event: snackbar after adding to a capture with hidden images
  ///
  /// In en, this message translates to:
  /// **'Added. Images are hidden on this capture.'**
  String get eventAddedHidden;

  /// Event: Premium upgrade hint
  ///
  /// In en, this message translates to:
  /// **'TabCam Premium transcribes your scans automatically.'**
  String get eventPremiumHint;

  /// Event: Premium hint button
  ///
  /// In en, this message translates to:
  /// **'Upgrade'**
  String get eventUpgrade;

  /// Event: close the Premium hint (tooltip)
  ///
  /// In en, this message translates to:
  /// **'Not now'**
  String get eventNotNow;

  /// Event Text view: no images
  ///
  /// In en, this message translates to:
  /// **'Nothing to read: add a scan, a photo or a PDF.'**
  String get eventNothingToRead;

  /// Event Text view: reading
  ///
  /// In en, this message translates to:
  /// **'Reading the tab…'**
  String get eventReadingTab;

  /// Event Text view: transcribing in the cloud
  ///
  /// In en, this message translates to:
  /// **'Transcribing in the cloud. The text appears here when it\'s done.'**
  String get eventInCloud;

  /// Event Text view: no tab found
  ///
  /// In en, this message translates to:
  /// **'No tab found in the pages. Try rescanning closer and flatter.'**
  String get eventNoTab;

  /// Event Text view: button to read again
  ///
  /// In en, this message translates to:
  /// **'Read again'**
  String get eventReadAgain;

  /// Event: asked when tapping the Text tool again while the Text view shows a tab
  ///
  /// In en, this message translates to:
  /// **'Read the tab again?'**
  String get eventReadAgainTitle;

  /// Event: what reading the tab again does
  ///
  /// In en, this message translates to:
  /// **'The text read before is replaced, unless you edited it or marked it correct.'**
  String get eventReadAgainBody;

  /// Event: asked when tapping Rescan on the Text view
  ///
  /// In en, this message translates to:
  /// **'Rescan the pages?'**
  String get eventRescanTitle;

  /// Event: what Rescan does
  ///
  /// In en, this message translates to:
  /// **'The current text is deleted, even if you edited it or marked it verified, and every photo and PDF is read again to replace it.'**
  String get eventRescanBody;

  /// Event Text view: reading failed
  ///
  /// In en, this message translates to:
  /// **'Reading the tab failed.'**
  String get eventReadFailed;

  /// Event Text view: reading not available here
  ///
  /// In en, this message translates to:
  /// **'Reading tabs needs the Android or iOS app, or TabCam Premium.'**
  String get eventReadUnsupported;

  /// Event Text view: must sign in to read
  ///
  /// In en, this message translates to:
  /// **'Reading tabs needs you signed in.'**
  String get eventReadNeedsSignIn;

  /// Event Text view: sign-in button
  ///
  /// In en, this message translates to:
  /// **'Sign in'**
  String get eventSignIn;

  /// Event Text view: no reader
  ///
  /// In en, this message translates to:
  /// **'No text yet.'**
  String get eventNoTextYet;

  /// Event Text view: not read yet
  ///
  /// In en, this message translates to:
  /// **'Not read yet.'**
  String get eventNotReadYet;

  /// Event Text view: button to read the tab
  ///
  /// In en, this message translates to:
  /// **'Read'**
  String get eventRead;

  /// Event: snackbar on deleting the last page
  ///
  /// In en, this message translates to:
  /// **'An event keeps at least one page; delete the event instead.'**
  String get eventKeepOnePage;

  /// Event app bar tooltip, rename dialog title, and the file screen tool (beside Delete) that renames the file
  ///
  /// In en, this message translates to:
  /// **'Rename'**
  String get eventRename;

  /// Event app bar tooltip
  ///
  /// In en, this message translates to:
  /// **'Share with people'**
  String get eventShareWithPeople;

  /// Event app bar tooltip
  ///
  /// In en, this message translates to:
  /// **'Clone'**
  String get eventClone;

  /// Event app bar tooltip
  ///
  /// In en, this message translates to:
  /// **'Share'**
  String get eventShare;

  /// Share sheet: what Share with people does
  ///
  /// In en, this message translates to:
  /// **'By email, to edit or read only'**
  String get eventShareWithPeopleDetail;

  /// Event tool: the list of the capture's files
  ///
  /// In en, this message translates to:
  /// **'Files'**
  String get eventFiles;

  /// Event file list: a photo or scan, numbered among the capture's pages
  ///
  /// In en, this message translates to:
  /// **'Page {number}'**
  String eventFilePage(int number);

  /// Event file list: a video, numbered among the capture's videos
  ///
  /// In en, this message translates to:
  /// **'Video {number}'**
  String eventFileVideo(int number);

  /// Event file list: a PDF, numbered among the capture's PDFs
  ///
  /// In en, this message translates to:
  /// **'PDF {number}'**
  String eventFilePdf(int number);

  /// Event file list: a recording, numbered among the capture's recordings
  ///
  /// In en, this message translates to:
  /// **'Recording {number}'**
  String eventFileRecording(int number);

  /// Event tool: show the text tab
  ///
  /// In en, this message translates to:
  /// **'Text'**
  String get eventText;

  /// Event tool: add pages
  ///
  /// In en, this message translates to:
  /// **'Add'**
  String get eventAdd;

  /// Event tool: rotate the page
  ///
  /// In en, this message translates to:
  /// **'Rotate'**
  String get eventRotate;

  /// Event: rotate failed (before ': error')
  ///
  /// In en, this message translates to:
  /// **'Couldn\'t rotate'**
  String get eventCouldntRotate;

  /// Event tool: delete the page
  ///
  /// In en, this message translates to:
  /// **'Delete'**
  String get eventDelete;

  /// Capture screen: a file's delete button in the list
  ///
  /// In en, this message translates to:
  /// **'Delete file'**
  String get eventDeleteFile;

  /// Capture screen: download one file
  ///
  /// In en, this message translates to:
  /// **'Download'**
  String get eventDownload;

  /// Capture screen: download every file as a zip
  ///
  /// In en, this message translates to:
  /// **'Download all'**
  String get eventDownloadAll;

  /// Capture screen: a download failed
  ///
  /// In en, this message translates to:
  /// **'Couldn\'t download'**
  String get eventCouldntDownload;

  /// Capture screen: a file's menu (rename, download, delete) on a narrow phone
  ///
  /// In en, this message translates to:
  /// **'More'**
  String get eventFileMore;

  /// Capture screen: deleting a file failed
  ///
  /// In en, this message translates to:
  /// **'Couldn\'t delete'**
  String get eventCouldntDelete;

  /// Event file list: a file's drag handle, to change the files' order
  ///
  /// In en, this message translates to:
  /// **'Reorder'**
  String get eventReorder;

  /// Event: reorder failed (before ': error')
  ///
  /// In en, this message translates to:
  /// **'Couldn\'t reorder'**
  String get eventCouldntReorder;

  /// Event view tool / page filter: photos as taken
  ///
  /// In en, this message translates to:
  /// **'Original'**
  String get eventViewOriginal;

  /// Event view tool: processed (black and white) pages
  ///
  /// In en, this message translates to:
  /// **'Scan'**
  String get eventViewScan;

  /// Page filter name: black ink on white
  ///
  /// In en, this message translates to:
  /// **'Tab'**
  String get eventFilterTab;

  /// Add sheet: scan with the camera
  ///
  /// In en, this message translates to:
  /// **'Scan pages'**
  String get eventAddScan;

  /// Add sheet: scan detail
  ///
  /// In en, this message translates to:
  /// **'More tab pages, with the camera'**
  String get eventAddScanDetail;

  /// Add sheet: from the photo library
  ///
  /// In en, this message translates to:
  /// **'Photos & videos'**
  String get eventAddLibrary;

  /// Add sheet: photo library detail
  ///
  /// In en, this message translates to:
  /// **'From your photo library'**
  String get eventAddLibraryDetail;

  /// Add sheet: from files
  ///
  /// In en, this message translates to:
  /// **'Files'**
  String get eventAddFiles;

  /// Add sheet: files detail
  ///
  /// In en, this message translates to:
  /// **'Image, video, audio and PDF files'**
  String get eventAddFilesDetail;

  /// Add sheet: a link
  ///
  /// In en, this message translates to:
  /// **'Link'**
  String get eventAddLink;

  /// Add sheet: link detail
  ///
  /// In en, this message translates to:
  /// **'A lesson, a recording, the song online'**
  String get eventAddLinkDetail;

  /// Event banner: who shared it, and the access (eventReadOnly or eventCanEdit)
  ///
  /// In en, this message translates to:
  /// **'Shared by {owner} · {access}'**
  String eventSharedBy(String owner, String access);

  /// Event banner: shared read only
  ///
  /// In en, this message translates to:
  /// **'Read only'**
  String get eventReadOnly;

  /// Banner on a capture opened by its link by someone it isn't shared with
  ///
  /// In en, this message translates to:
  /// **'Opened by its link · Read only'**
  String get eventByLink;

  /// Button: leave a capture opened by its link, to sign in
  ///
  /// In en, this message translates to:
  /// **'Sign in'**
  String get linkSignIn;

  /// While a capture opened by its link loads
  ///
  /// In en, this message translates to:
  /// **'Opening the capture…'**
  String get linkOpening;

  /// Button: open the capture's link again
  ///
  /// In en, this message translates to:
  /// **'Try again'**
  String get linkTryAgain;

  /// A capture's link that didn't open
  ///
  /// In en, this message translates to:
  /// **'This capture can\'t be opened. The link may be wrong, its owner may have deleted it, or you may be offline.'**
  String get linkUnavailable;

  /// Event banner: shared, editable
  ///
  /// In en, this message translates to:
  /// **'Can edit'**
  String get eventCanEdit;

  /// Snackbar after cloning an event
  ///
  /// In en, this message translates to:
  /// **'Cloned as \"{title}\"'**
  String eventClonedAs(String title);

  /// Snackbar when cloning fails
  ///
  /// In en, this message translates to:
  /// **'Couldn\'t clone: {error}'**
  String eventCouldntClone(String error);

  /// Rename dialog: the capture's name field
  ///
  /// In en, this message translates to:
  /// **'Name'**
  String get eventName;

  /// Rename dialog button; camera close tooltip
  ///
  /// In en, this message translates to:
  /// **'Cancel'**
  String get eventCancel;

  /// Rename dialog button
  ///
  /// In en, this message translates to:
  /// **'Save'**
  String get eventSave;

  /// Sign-in sheet title, reading tabs
  ///
  /// In en, this message translates to:
  /// **'Sign in to read tabs'**
  String get eventGateReadTabTitle;

  /// Sign-in sheet, reading tabs
  ///
  /// In en, this message translates to:
  /// **'Reading a tab into text needs you signed in.'**
  String get eventGateReadTabDetail;

  /// Sign-in sheet title, sharing
  ///
  /// In en, this message translates to:
  /// **'Sign in to share'**
  String get eventGateShareTitle;

  /// Sign-in sheet, sharing
  ///
  /// In en, this message translates to:
  /// **'Sharing needs you signed in.'**
  String get eventGateShareDetail;

  /// Sign-in sheet body; detail is eventGate...Detail
  ///
  /// In en, this message translates to:
  /// **'{detail} Signed out, you can still scan and add to your captures; they stay on this device.'**
  String eventGateBody(String detail);

  /// Sign-in sheet button
  ///
  /// In en, this message translates to:
  /// **'Sign in with Google'**
  String get eventSignInGoogle;

  /// Camera screen: no camera
  ///
  /// In en, this message translates to:
  /// **'No camera found.'**
  String get eventNoCamera;

  /// Camera screen: permission denied
  ///
  /// In en, this message translates to:
  /// **'The camera isn\'t allowed: let TabCam use it in the browser\'s site settings.'**
  String get eventCameraNotAllowed;

  /// Camera screen: camera error
  ///
  /// In en, this message translates to:
  /// **'The camera failed: {error}'**
  String eventCameraFailed(String error);

  /// Camera screen: snackbar, shot failed
  ///
  /// In en, this message translates to:
  /// **'Couldn\'t take the picture: {error}'**
  String eventCouldntTakePicture(String error);

  /// Camera screen: close with pages taken
  ///
  /// In en, this message translates to:
  /// **'Discard {count, plural, =1{1 page} other{{count} pages}}?'**
  String eventDiscardPages(int count);

  /// Camera screen: discard dialog, keep
  ///
  /// In en, this message translates to:
  /// **'Keep scanning'**
  String get eventKeepScanning;

  /// Camera screen: discard dialog, discard
  ///
  /// In en, this message translates to:
  /// **'Discard'**
  String get eventDiscard;

  /// Camera screen title with no pages yet
  ///
  /// In en, this message translates to:
  /// **'Scan'**
  String get eventScanTitle;

  /// Camera screen title: pages taken
  ///
  /// In en, this message translates to:
  /// **'{count, plural, =1{1 page} other{{count} pages}}'**
  String eventPageCount(int count);

  /// Camera screen tooltip
  ///
  /// In en, this message translates to:
  /// **'Flip camera'**
  String get eventFlipCamera;

  /// Capture screen tool: record yourself playing along with the tab
  ///
  /// In en, this message translates to:
  /// **'Cam'**
  String get eventCam;

  /// Cam: start recording
  ///
  /// In en, this message translates to:
  /// **'Rec'**
  String get camRec;

  /// Cam: stop recording or playing
  ///
  /// In en, this message translates to:
  /// **'Stop'**
  String get camStop;

  /// Cam: play the last take back
  ///
  /// In en, this message translates to:
  /// **'Play'**
  String get camPlay;

  /// Cam: previous neckline tooltip
  ///
  /// In en, this message translates to:
  /// **'Previous line'**
  String get camPrevious;

  /// Cam: next neckline tooltip
  ///
  /// In en, this message translates to:
  /// **'Next line'**
  String get camNext;

  /// Cam: the capture has no text tab
  ///
  /// In en, this message translates to:
  /// **'No text tab yet: read the capture\'s tab to play along with it.'**
  String get camNoTab;

  /// Cam: a recording's name
  ///
  /// In en, this message translates to:
  /// **'Take {number}'**
  String camTake(int number);

  /// Cam: a take was saved
  ///
  /// In en, this message translates to:
  /// **'{name} added to the capture'**
  String camSaved(String name);

  /// Cam: recording failed
  ///
  /// In en, this message translates to:
  /// **'Couldn\'t record: {error}'**
  String camCouldntRecord(String error);

  /// Cam: the tab is being burned into the take
  ///
  /// In en, this message translates to:
  /// **'Adding the tab to the video…'**
  String get camAddingTab;

  /// Cam: burning the tab into the take failed, and why
  ///
  /// In en, this message translates to:
  /// **'The take was saved without the tab: {reason}'**
  String camNoOverlay(String reason);

  /// Cam (web): the tab couldn't be recorded in, and why
  ///
  /// In en, this message translates to:
  /// **'Recording without the tab: {reason}'**
  String camRecordingNoTab(String reason);

  /// Cam: head gestures toggle, on
  ///
  /// In en, this message translates to:
  /// **'Head gestures on: nod up or right for the next line, down or left for the one before'**
  String get camHeadsOn;

  /// Cam: head gestures toggle, off
  ///
  /// In en, this message translates to:
  /// **'Head gestures off'**
  String get camHeadsOff;

  /// Cam: permission denied
  ///
  /// In en, this message translates to:
  /// **'The camera or microphone isn\'t allowed: let TabCam use them in the settings.'**
  String get camNotAllowed;

  /// Camera screen: finish
  ///
  /// In en, this message translates to:
  /// **'Done'**
  String get eventDone;

  /// Camera screen: shutter
  ///
  /// In en, this message translates to:
  /// **'Take a picture'**
  String get eventTakePicture;

  /// Camera screen: no camera, pick photos
  ///
  /// In en, this message translates to:
  /// **'Choose photos instead'**
  String get eventChoosePhotos;

  /// Bottom navigation: the Home tab
  ///
  /// In en, this message translates to:
  /// **'Home'**
  String get homeTabHome;

  /// Bottom navigation: the Capture tab
  ///
  /// In en, this message translates to:
  /// **'Capture'**
  String get homeTabCapture;

  /// Bottom navigation: the Profile tab
  ///
  /// In en, this message translates to:
  /// **'Profile'**
  String get homeTabProfile;

  /// Profile tab's tooltip when signed in
  ///
  /// In en, this message translates to:
  /// **'Signed in as {identity}'**
  String homeSignedInAs(String identity);

  /// Message: a link's capture isn't on this device
  ///
  /// In en, this message translates to:
  /// **'That capture isn\'t on this device.'**
  String get homeLinkNotHere;

  /// Message: sign in to open a linked capture
  ///
  /// In en, this message translates to:
  /// **'Sign in (Profile) to open the capture in this link.'**
  String get homeLinkSignIn;

  /// Message: a linked capture isn't shared with the user
  ///
  /// In en, this message translates to:
  /// **'That capture isn\'t shared with you. Ask its owner to share it with your email address.'**
  String get homeLinkNotShared;

  /// Message after a capture: its title and what it holds (homePages etc.)
  ///
  /// In en, this message translates to:
  /// **'Saved \"{title}\" ({contents})'**
  String homeSaved(String title, String contents);

  /// Action on the saved message: open the event
  ///
  /// In en, this message translates to:
  /// **'Open'**
  String get homeOpen;

  /// Message: scanning failed
  ///
  /// In en, this message translates to:
  /// **'Couldn\'t scan: {error}'**
  String homeScanFailed(String error);

  /// Message: adding media or a link failed
  ///
  /// In en, this message translates to:
  /// **'Couldn\'t add: {error}'**
  String homeAddFailed(String error);

  /// Message: files picked that aren't photos or videos
  ///
  /// In en, this message translates to:
  /// **'{count, plural, =1{1 file isn\'t a photo or video, so not added.} other{{count} files aren\'t a photo or video, so not added.}}'**
  String homeSkipped(int count);

  /// An event's page count
  ///
  /// In en, this message translates to:
  /// **'{count, plural, =1{1 page} other{{count} pages}}'**
  String homePages(int count);

  /// An event's video count
  ///
  /// In en, this message translates to:
  /// **'{count, plural, =1{1 video} other{{count} videos}}'**
  String homeVideos(int count);

  /// An event's audio recording count
  ///
  /// In en, this message translates to:
  /// **'{count, plural, =1{1 recording} other{{count} recordings}}'**
  String homeAudio(int count);

  /// An event's PDF count
  ///
  /// In en, this message translates to:
  /// **'{count, plural, =1{1 PDF} other{{count} PDFs}}'**
  String homePdfs(int count);

  /// An event's link count
  ///
  /// In en, this message translates to:
  /// **'{count, plural, =1{1 link} other{{count} links}}'**
  String homeLinks(int count);

  /// Capture tab: the Scan button
  ///
  /// In en, this message translates to:
  /// **'Scan'**
  String get homeScan;

  /// Capture tab: what Scan does
  ///
  /// In en, this message translates to:
  /// **'With the camera: the page is found, straightened and cleaned up, and you can take several in a row.'**
  String get homeScanDetail;

  /// Capture tab: the uploads section's title
  ///
  /// In en, this message translates to:
  /// **'Add'**
  String get homeAdd;

  /// Capture tab: add from the photo library
  ///
  /// In en, this message translates to:
  /// **'Photos & videos'**
  String get homeAddPhotos;

  /// Capture tab: Photos & videos' detail
  ///
  /// In en, this message translates to:
  /// **'From your photo library'**
  String get homeAddPhotosDetail;

  /// Capture tab: add files
  ///
  /// In en, this message translates to:
  /// **'Files'**
  String get homeAddFiles;

  /// Capture tab: Files' detail
  ///
  /// In en, this message translates to:
  /// **'Image and video files'**
  String get homeAddFilesDetail;

  /// Capture tab: add a link
  ///
  /// In en, this message translates to:
  /// **'Link'**
  String get homeAddLink;

  /// Capture tab: Link's detail
  ///
  /// In en, this message translates to:
  /// **'A lesson, a recording, the song online'**
  String get homeAddLinkDetail;

  /// Profile tab in a build without sign-in
  ///
  /// In en, this message translates to:
  /// **'Sign-in isn\'t set up in this build: your events stay on this device.'**
  String get homeNoSignIn;

  /// Profile tab: the About section's title
  ///
  /// In en, this message translates to:
  /// **'About'**
  String get homeAbout;

  /// About: in place of the version in a development build
  ///
  /// In en, this message translates to:
  /// **'(development build)'**
  String get homeDevelopmentBuild;

  /// About: what the app does
  ///
  /// In en, this message translates to:
  /// **'Scan guitar tabs, read them as text, and share them.'**
  String get homeAboutDetail;

  /// About: the button to the licenses
  ///
  /// In en, this message translates to:
  /// **'Licenses'**
  String get homeLicenses;

  /// Home: the user's own events' section
  ///
  /// In en, this message translates to:
  /// **'My captures'**
  String get homeLibraryMine;

  /// Home: no events of the user's own
  ///
  /// In en, this message translates to:
  /// **'Nothing of your own yet: go to Capture to add some.'**
  String get homeLibraryMineEmpty;

  /// Home: the section of events shared with the user
  ///
  /// In en, this message translates to:
  /// **'Shared with me'**
  String get homeLibraryShared;

  /// Home: the search field's hint
  ///
  /// In en, this message translates to:
  /// **'Search captures'**
  String get homeSearch;

  /// Home: the button that empties the search
  ///
  /// In en, this message translates to:
  /// **'Clear search'**
  String get homeSearchClear;

  /// Home: no event matches the search
  ///
  /// In en, this message translates to:
  /// **'No captures match “{query}”'**
  String homeSearchNone(String query);

  /// Home with no events: the title
  ///
  /// In en, this message translates to:
  /// **'No tabs yet'**
  String get homeLibraryEmpty;

  /// Home: signed in, the first sync is bringing the captures
  ///
  /// In en, this message translates to:
  /// **'Loading your captures…'**
  String get homeLibraryLoading;

  /// Home: nothing here and the first sync failed
  ///
  /// In en, this message translates to:
  /// **'Your captures couldn\'t be loaded'**
  String get homeLibraryLoadFailed;

  /// Home: retry loading the captures
  ///
  /// In en, this message translates to:
  /// **'Try again'**
  String get homeLibraryTryAgain;

  /// Home with no events: what to do
  ///
  /// In en, this message translates to:
  /// **'Go to Capture to scan a tab with the camera (the page is found, straightened and cleaned up for you), or to add photos, videos, files and links.'**
  String get homeLibraryEmptyDetail;

  /// Dialog: remove an event shared with the user
  ///
  /// In en, this message translates to:
  /// **'Remove \"{title}\"?'**
  String homeLibraryRemoveTitle(String title);

  /// Dialog: what removing a shared event does
  ///
  /// In en, this message translates to:
  /// **'It goes from your library. {owner} keeps it, and can share it with you again.'**
  String homeLibraryRemoveBody(String owner);

  /// Dialog button
  ///
  /// In en, this message translates to:
  /// **'Cancel'**
  String get homeLibraryCancel;

  /// Button / menu item: remove a shared event
  ///
  /// In en, this message translates to:
  /// **'Remove'**
  String get homeLibraryRemove;

  /// Message: removing a shared event failed
  ///
  /// In en, this message translates to:
  /// **'Couldn\'t remove: {error}'**
  String homeLibraryRemoveFailed(String error);

  /// Dialog: delete an event
  ///
  /// In en, this message translates to:
  /// **'Delete \"{title}\"?'**
  String homeLibraryDeleteTitle(String title);

  /// Dialog: what deleting an event does
  ///
  /// In en, this message translates to:
  /// **'Its pages and text tab are deleted too.'**
  String get homeLibraryDeleteBody;

  /// Button / menu item: delete an event
  ///
  /// In en, this message translates to:
  /// **'Delete'**
  String get homeLibraryDelete;

  /// Event card: its images are hidden
  ///
  /// In en, this message translates to:
  /// **'images hidden'**
  String get homeLibraryImagesHidden;

  /// Event card: it has a text tab
  ///
  /// In en, this message translates to:
  /// **'text'**
  String get homeLibraryText;

  /// Event card: who shared it
  ///
  /// In en, this message translates to:
  /// **'shared by {owner}'**
  String homeLibrarySharedBy(String owner);

  /// Event card: the menu's tooltip
  ///
  /// In en, this message translates to:
  /// **'More'**
  String get homeLibraryMore;

  /// Event card menu item
  ///
  /// In en, this message translates to:
  /// **'Rename'**
  String get homeLibraryRename;

  /// Event card menu item
  ///
  /// In en, this message translates to:
  /// **'Share'**
  String get homeLibraryShare;

  /// Event card menu item
  ///
  /// In en, this message translates to:
  /// **'Clone'**
  String get homeLibraryClone;

  /// Maintenance screen's default message
  ///
  /// In en, this message translates to:
  /// **'Sorry, TabCam is down for maintenance. Please try again later.'**
  String get homeMaintenanceDefault;

  /// Snackbar after copying the text tab
  ///
  /// In en, this message translates to:
  /// **'Tab copied'**
  String get textViewTabCopied;

  /// Snackbar when fret up/down has no number under the cursor
  ///
  /// In en, this message translates to:
  /// **'Put the cursor on a fret number'**
  String get textViewPutCursorOnFret;

  /// Snackbar when Fix needs Premium
  ///
  /// In en, this message translates to:
  /// **'Fix is part of TabCam Premium'**
  String get textViewFixPremium;

  /// Snackbar action to upgrade to Premium
  ///
  /// In en, this message translates to:
  /// **'Upgrade'**
  String get textViewUpgrade;

  /// Snackbar when Fix needs a new sign-in
  ///
  /// In en, this message translates to:
  /// **'Sign in again to use Fix'**
  String get textViewFixSignIn;

  /// Snackbar when the Fix service is not available
  ///
  /// In en, this message translates to:
  /// **'Fix isn\'t available yet'**
  String get textViewFixUnavailable;

  /// Snackbar when the Fix lookup fails
  ///
  /// In en, this message translates to:
  /// **'Couldn\'t check online right now. Try again later.'**
  String get textViewCheckFailed;

  /// Snackbar when the text was edited during Fix
  ///
  /// In en, this message translates to:
  /// **'The text changed meanwhile: tap Fix again'**
  String get textViewTextChanged;

  /// Snackbar when Fix finds no corrections
  ///
  /// In en, this message translates to:
  /// **'The tab matches the one found online'**
  String get textViewTabMatches;

  /// Snackbar when Fix finds no tab for the song
  ///
  /// In en, this message translates to:
  /// **'Couldn\'t find this song\'s tab online'**
  String get textViewTabNotFound;

  /// Snackbar after the review, with the number of accepted corrections
  ///
  /// In en, this message translates to:
  /// **'{count, plural, =1{1 correction applied} other{{count} corrections applied}}'**
  String textViewApplied(int count);

  /// Button copying the text tab
  ///
  /// In en, this message translates to:
  /// **'Copy'**
  String get textViewCopy;

  /// Button that corrects the tab from the song's tab online
  ///
  /// In en, this message translates to:
  /// **'Fix'**
  String get textViewFix;

  /// Button reading the tab from the pages again
  ///
  /// In en, this message translates to:
  /// **'Rescan'**
  String get textViewRescan;

  /// Tooltip of the Rescan button
  ///
  /// In en, this message translates to:
  /// **'Read the tab from the pages again'**
  String get textViewRescanTip;

  /// Progress text while Fix runs
  ///
  /// In en, this message translates to:
  /// **'Looking for the song\'s tab online…'**
  String get textViewLookingOnline;

  /// Toggle marking the text tab correct
  ///
  /// In en, this message translates to:
  /// **'Verified'**
  String get textViewCorrect;

  /// Tooltip of the Correct toggle while on
  ///
  /// In en, this message translates to:
  /// **'Verified: the event opens on its text'**
  String get textViewMarkedCorrect;

  /// Tooltip of the Correct toggle while off
  ///
  /// In en, this message translates to:
  /// **'Mark the reading verified'**
  String get textViewMarkCorrect;

  /// Tooltip of the − button
  ///
  /// In en, this message translates to:
  /// **'Fret down (the number under the cursor)'**
  String get textViewFretDown;

  /// Tooltip of the + button
  ///
  /// In en, this message translates to:
  /// **'Fret up (the number under the cursor)'**
  String get textViewFretUp;

  /// Tooltip of Overtype while on
  ///
  /// In en, this message translates to:
  /// **'Overtype: typing replaces characters, columns stay put'**
  String get textViewOvertypeOn;

  /// Tooltip of Overtype while off
  ///
  /// In en, this message translates to:
  /// **'Insert: typing pushes the line right'**
  String get textViewOvertypeOff;

  /// Checkbox button toggling overtype mode
  ///
  /// In en, this message translates to:
  /// **'Overtype'**
  String get textViewOvertype;

  /// Title of the dialog asking which song the tab is
  ///
  /// In en, this message translates to:
  /// **'Fix from the song\'s tab'**
  String get textViewSongDialogTitle;

  /// Label of the song field in the Fix dialog
  ///
  /// In en, this message translates to:
  /// **'Song and artist'**
  String get textViewSongLabel;

  /// Helper text of the song field in the Fix dialog
  ///
  /// In en, this message translates to:
  /// **'Looked up on tab sites to correct the reading'**
  String get textViewSongHelper;

  /// Dialog cancel button
  ///
  /// In en, this message translates to:
  /// **'Cancel'**
  String get textViewCancel;

  /// Fix dialog button that starts the lookup
  ///
  /// In en, this message translates to:
  /// **'Check'**
  String get textViewCheck;

  /// Shown as the new value of a correction that deletes text
  ///
  /// In en, this message translates to:
  /// **'removed'**
  String get textViewRemoved;

  /// Tooltip: previous correction
  ///
  /// In en, this message translates to:
  /// **'Previous'**
  String get textViewPrevious;

  /// Tooltip: next correction
  ///
  /// In en, this message translates to:
  /// **'Next'**
  String get textViewNext;

  /// Which correction is shown, of how many
  ///
  /// In en, this message translates to:
  /// **'{index} of {total}'**
  String textViewPosition(int index, int total);

  /// Where a correction is, for a line without a string name
  ///
  /// In en, this message translates to:
  /// **'Line {line}, column {column}'**
  String textViewLineColumn(int line, int column);

  /// Where a correction is, with the line's string name (e, B, G…)
  ///
  /// In en, this message translates to:
  /// **'Line {line} ({string}), column {column}'**
  String textViewLineStringColumn(int line, String string, int column);

  /// Button rejecting a correction
  ///
  /// In en, this message translates to:
  /// **'Reject'**
  String get textViewReject;

  /// Reject button once the correction is rejected
  ///
  /// In en, this message translates to:
  /// **'Rejected'**
  String get textViewRejected;

  /// Button accepting a correction
  ///
  /// In en, this message translates to:
  /// **'Accept'**
  String get textViewAccept;

  /// Accept button once the correction is accepted
  ///
  /// In en, this message translates to:
  /// **'Accepted'**
  String get textViewAccepted;

  /// Tooltip of the menu for all corrections
  ///
  /// In en, this message translates to:
  /// **'All'**
  String get textViewAll;

  /// Menu item accepting all corrections
  ///
  /// In en, this message translates to:
  /// **'Accept all'**
  String get textViewAcceptAll;

  /// Menu item rejecting all corrections
  ///
  /// In en, this message translates to:
  /// **'Reject all'**
  String get textViewRejectAll;

  /// Menu button for all corrections
  ///
  /// In en, this message translates to:
  /// **'All…'**
  String get textViewAllMenu;

  /// Button ending the review, with how many are decided
  ///
  /// In en, this message translates to:
  /// **'Done ({decided}/{total})'**
  String textViewDoneCount(int decided, int total);

  /// Button ending the review once all are decided
  ///
  /// In en, this message translates to:
  /// **'Done'**
  String get textViewDone;

  /// Text page title before the tab is read
  ///
  /// In en, this message translates to:
  /// **'No text tab yet'**
  String get textViewNoTextTab;

  /// Text page, read-only event, before the tab is read
  ///
  /// In en, this message translates to:
  /// **'The images are hidden, and the tab hasn\'t been read.'**
  String get textViewHiddenNotRead;

  /// Text page before the tab is read
  ///
  /// In en, this message translates to:
  /// **'The images are hidden. They\'re still read: the text appears here.'**
  String get textViewHiddenStillRead;

  /// Title of the text tab page
  ///
  /// In en, this message translates to:
  /// **'Text tab'**
  String get textViewTextTab;

  /// Button opening the text tab or a link
  ///
  /// In en, this message translates to:
  /// **'Open'**
  String get textViewOpen;

  /// Snackbar when a link can't be opened
  ///
  /// In en, this message translates to:
  /// **'Couldn\'t open {url}'**
  String textViewCouldNotOpen(String url);

  /// Snackbar after copying a link
  ///
  /// In en, this message translates to:
  /// **'Link copied'**
  String get textViewLinkCopied;

  /// Title of the add link dialog
  ///
  /// In en, this message translates to:
  /// **'Add a link'**
  String get textViewAddLink;

  /// Label of the link address field
  ///
  /// In en, this message translates to:
  /// **'Link'**
  String get textViewLink;

  /// Error under the link field
  ///
  /// In en, this message translates to:
  /// **'Enter a web address (https://…)'**
  String get textViewEnterAddress;

  /// Label of the link title field
  ///
  /// In en, this message translates to:
  /// **'Title (optional)'**
  String get textViewTitleOptional;

  /// Hint of the link title field
  ///
  /// In en, this message translates to:
  /// **'Lesson, recording…'**
  String get textViewTitleHint;

  /// Add link dialog button
  ///
  /// In en, this message translates to:
  /// **'Add'**
  String get textViewAdd;

  /// Video page when the video can't play
  ///
  /// In en, this message translates to:
  /// **'This video can\'t be played here'**
  String get textViewCantPlay;

  /// Video page label before playing
  ///
  /// In en, this message translates to:
  /// **'Video'**
  String get textViewVideo;

  /// Audio page label
  ///
  /// In en, this message translates to:
  /// **'Recording'**
  String get textViewAudio;

  /// Audio page when the recording can't play
  ///
  /// In en, this message translates to:
  /// **'This recording can\'t be played here'**
  String get textViewCantPlayAudio;

  /// Video and audio pages: play button
  ///
  /// In en, this message translates to:
  /// **'Play'**
  String get textViewPlay;

  /// Video and audio pages: pause button
  ///
  /// In en, this message translates to:
  /// **'Pause'**
  String get textViewPause;

  /// PDF page when the PDF can't be shown
  ///
  /// In en, this message translates to:
  /// **'This PDF can\'t be shown here'**
  String get textViewCantShowPdf;

  /// Profile, About: opens the privacy policy
  ///
  /// In en, this message translates to:
  /// **'Privacy policy'**
  String get homePrivacyPolicy;

  /// Deleting the account (Profile > Delete account)
  ///
  /// In en, this message translates to:
  /// **'Your TabCam account was deleted.'**
  String get deleteAccountDone;

  /// Deleting the account (Profile > Delete account)
  ///
  /// In en, this message translates to:
  /// **'Delete your account?'**
  String get deleteAccountTitle;

  /// Deleting the account (Profile > Delete account)
  ///
  /// In en, this message translates to:
  /// **'This deletes:'**
  String get deleteAccountThisDeletes;

  /// Deleting the account (Profile > Delete account)
  ///
  /// In en, this message translates to:
  /// **'All your events, in the cloud and on this device.'**
  String get deleteAccountEvents;

  /// Deleting the account (Profile > Delete account)
  ///
  /// In en, this message translates to:
  /// **'Your shares: the people you shared captures with lose them.'**
  String get deleteAccountShares;

  /// Deleting the account (Profile > Delete account)
  ///
  /// In en, this message translates to:
  /// **'The captures shared with you: they stop showing here.'**
  String get deleteAccountSharedWithYou;

  /// Deleting the account (Profile > Delete account)
  ///
  /// In en, this message translates to:
  /// **'It can\'t be undone.'**
  String get deleteAccountCantUndo;

  /// Deleting the account (Profile > Delete account)
  ///
  /// In en, this message translates to:
  /// **'Your Google account isn\'t deleted.'**
  String get deleteAccountGoogleKept;

  /// Deleting the account (Profile > Delete account)
  ///
  /// In en, this message translates to:
  /// **'A TabCam Premium subscription isn\'t cancelled: cancel it on Substack, where you subscribed.'**
  String get deleteAccountPremiumWeb;

  /// Deleting the account (Profile > Delete account)
  ///
  /// In en, this message translates to:
  /// **'A TabCam Premium subscription isn\'t cancelled: it\'s managed where you bought it.'**
  String get deleteAccountPremiumStore;

  /// Deleting the account (Profile > Delete account)
  ///
  /// In en, this message translates to:
  /// **'If TabCam is signed in on your other devices, sign out there first, so they don\'t upload their events again.'**
  String get deleteAccountOtherDevices;

  /// Deleting the account (Profile > Delete account)
  ///
  /// In en, this message translates to:
  /// **'Cancel'**
  String get deleteAccountCancel;

  /// Deleting the account (Profile > Delete account)
  ///
  /// In en, this message translates to:
  /// **'Delete account'**
  String get deleteAccountButton;

  /// Deleting the account (Profile > Delete account)
  ///
  /// In en, this message translates to:
  /// **'Your account couldn\'t be deleted: {error}'**
  String deleteAccountCouldnt(String error);

  /// Deleting the account (Profile > Delete account)
  ///
  /// In en, this message translates to:
  /// **'Deleting your account'**
  String get deleteAccountDeleting;

  /// Deleting the account (Profile > Delete account)
  ///
  /// In en, this message translates to:
  /// **'Account deleted'**
  String get deleteAccountDeleted;

  /// Deleting the account (Profile > Delete account)
  ///
  /// In en, this message translates to:
  /// **'Account not deleted'**
  String get deleteAccountNotDeleted;

  /// Deleting the account (Profile > Delete account)
  ///
  /// In en, this message translates to:
  /// **'Close'**
  String get deleteAccountClose;

  /// Deleting the account (Profile > Delete account)
  ///
  /// In en, this message translates to:
  /// **'Try again'**
  String get deleteAccountTryAgain;

  /// Deleting the account (Profile > Delete account)
  ///
  /// In en, this message translates to:
  /// **'Deleting your files in the cloud…'**
  String get deleteAccountStepCloud;

  /// Deleting the account (Profile > Delete account)
  ///
  /// In en, this message translates to:
  /// **'Deleting your files in the cloud ({done} of {total})…'**
  String deleteAccountStepCloudCount(int done, int total);

  /// Deleting the account (Profile > Delete account)
  ///
  /// In en, this message translates to:
  /// **'Deleting your shares…'**
  String get deleteAccountStepShares;

  /// Deleting the account (Profile > Delete account)
  ///
  /// In en, this message translates to:
  /// **'Deleting your events on this device…'**
  String get deleteAccountStepDevice;

  /// Deleting the account (Profile > Delete account)
  ///
  /// In en, this message translates to:
  /// **'Deleting your events on this device ({done} of {total})…'**
  String deleteAccountStepDeviceCount(int done, int total);

  /// Deleting the account (Profile > Delete account)
  ///
  /// In en, this message translates to:
  /// **'Signing out…'**
  String get deleteAccountStepSignOut;

  /// Deleting the account (Profile > Delete account)
  ///
  /// In en, this message translates to:
  /// **'Sign in again to delete your account.'**
  String get deleteAccountSignInAgain;

  /// Deleting the account (Profile > Delete account)
  ///
  /// In en, this message translates to:
  /// **'You signed out before your account was deleted. Your files in the cloud were deleted; sign in and delete it again to finish.'**
  String get deleteAccountSignedOutMeanwhile;

  /// Deleting the account (Profile > Delete account)
  ///
  /// In en, this message translates to:
  /// **'Your files in the cloud were deleted, but not your shares: {reason}. Delete your account again to finish.'**
  String deleteAccountSharesFailed(String reason);

  /// Deleting the account (Profile > Delete account)
  ///
  /// In en, this message translates to:
  /// **'sign in again'**
  String get deleteAccountSignInAgainShort;

  /// Deleting the account (Profile > Delete account)
  ///
  /// In en, this message translates to:
  /// **'Your files in the cloud were deleted, but not your shares ({error}). Delete your account again to finish.'**
  String deleteAccountSharesFailedBecause(String error);

  /// Deleting the account (Profile > Delete account)
  ///
  /// In en, this message translates to:
  /// **'Your account was deleted and you were signed out, but some events on this device couldn\'t be deleted ({error}): delete them from Home.'**
  String deleteAccountLeftHere(String error);

  /// Deleting the account (Profile > Delete account)
  ///
  /// In en, this message translates to:
  /// **'{failed} of {total} files in the cloud couldn\'t be deleted. Nothing else was deleted, and you are still signed in: try again.'**
  String deleteAccountSomeFiles(int failed, int total);

  /// Deleting the account (Profile > Delete account)
  ///
  /// In en, this message translates to:
  /// **'Files kept appearing in your cloud folder while it was being emptied. Nothing else was deleted: try again.'**
  String get deleteAccountKeptAppearing;

  /// Deleting the account (Profile > Delete account)
  ///
  /// In en, this message translates to:
  /// **'Your files in the cloud couldn\'t be deleted (HTTP {status}). Nothing else was deleted: try again.'**
  String deleteAccountFilesHttp(int status);

  /// Deleting the account (Profile > Delete account)
  ///
  /// In en, this message translates to:
  /// **'Your files in the cloud couldn\'t be deleted ({type}). Nothing was deleted: try again.'**
  String deleteAccountFilesCognito(String type);

  /// Deleting the account (Profile > Delete account)
  ///
  /// In en, this message translates to:
  /// **'Your files in the cloud couldn\'t be deleted ({error}). Nothing else was deleted: try again.'**
  String deleteAccountFilesError(String error);

  /// Profile: Premium can't be checked for an Apple sign-in
  ///
  /// In en, this message translates to:
  /// **'Premium needs Google sign-in'**
  String get accountPremiumNeedsGoogle;

  /// Sign-in button for Apple (Apple's own wording)
  ///
  /// In en, this message translates to:
  /// **'Sign in with Apple'**
  String get accountSignInWithApple;

  /// Error after a failed Apple sign-in
  ///
  /// In en, this message translates to:
  /// **'Sign in with Apple failed'**
  String get accountAppleSignInFailed;

  /// Error when the Apple sign-in expires
  ///
  /// In en, this message translates to:
  /// **'Your Apple sign-in expired: sign in again.'**
  String get accountAppleSignInExpired;

  /// Why Apple sign-in can't be offered
  ///
  /// In en, this message translates to:
  /// **'Sign in with Apple isn\'t available on this device.'**
  String get accountAppleUnavailable;

  /// Profile: the name shown for an account with a hidden email address
  ///
  /// In en, this message translates to:
  /// **'{provider} ID (private email)'**
  String accountPrivateEmail(String provider);

  /// Profile: the linked accounts sheet's title and button
  ///
  /// In en, this message translates to:
  /// **'Linked accounts'**
  String get profileLinkedAccounts;

  /// Linked accounts: what linking does
  ///
  /// In en, this message translates to:
  /// **'Any of these accounts reaches the same captures, and the profile has all their roles.'**
  String get profileLinkedIntro;

  /// Linked accounts: the profile's owner
  ///
  /// In en, this message translates to:
  /// **'Owner'**
  String get profileOwner;

  /// Linked accounts: the sign-in in use
  ///
  /// In en, this message translates to:
  /// **'This account'**
  String get profileThisAccount;

  /// Linked accounts: unlink an account
  ///
  /// In en, this message translates to:
  /// **'Unlink'**
  String get profileUnlink;

  /// Linked accounts: section title
  ///
  /// In en, this message translates to:
  /// **'Link another account'**
  String get profileLinkAnother;

  /// Linked accounts: make a link code
  ///
  /// In en, this message translates to:
  /// **'Get a link code'**
  String get profileGetCode;

  /// Linked accounts: how to use the code
  ///
  /// In en, this message translates to:
  /// **'Within 10 minutes, sign in with the other account and enter this code under Linked accounts.'**
  String get profileCodeHow;

  /// Linked accounts: copy the link code
  ///
  /// In en, this message translates to:
  /// **'Copy the code'**
  String get profileCopyCode;

  /// Linked accounts: entering a code
  ///
  /// In en, this message translates to:
  /// **'Have a code from your other account? Enter it to link this account to it.'**
  String get profileHaveCode;

  /// Linked accounts: the code field
  ///
  /// In en, this message translates to:
  /// **'Link code'**
  String get profileCodeLabel;

  /// Linked accounts: join the code's profile
  ///
  /// In en, this message translates to:
  /// **'Link this account'**
  String get profileLinkThis;

  /// Linked accounts: what joining does
  ///
  /// In en, this message translates to:
  /// **'This account then uses the other account\'s profile and captures.'**
  String get profileLinkThisNote;

  /// Linked accounts: a bad code
  ///
  /// In en, this message translates to:
  /// **'That code is wrong, already used or expired.'**
  String get profileCodeWrong;

  /// Linked accounts: linking refused
  ///
  /// In en, this message translates to:
  /// **'This account can\'t be linked: it has captures in the cloud of its own, or other accounts linked to it.'**
  String get profileCantLink;

  /// Linked accounts: throttled
  ///
  /// In en, this message translates to:
  /// **'Too many tries: wait a minute and try again.'**
  String get profileTooManyTries;

  /// Linked accounts: another error
  ///
  /// In en, this message translates to:
  /// **'Couldn\'t link: {error}'**
  String profileLinkFailed(String error);

  /// Linked accounts: joined a profile
  ///
  /// In en, this message translates to:
  /// **'Linked: this account now uses the profile {profileId}'**
  String profileLinked(String profileId);

  /// Profile tab: the profile's ID
  ///
  /// In en, this message translates to:
  /// **'Profile: {profileId}'**
  String profileId(String profileId);

  /// Profile tab: every linked account's roles
  ///
  /// In en, this message translates to:
  /// **'Roles: {roles}'**
  String profileRoles(String roles);

  /// Profile tab: a linked (not owner) account can't delete
  ///
  /// In en, this message translates to:
  /// **'Only the profile\'s owner can delete it. To leave it, unlink this account under Linked accounts.'**
  String get profileNotOwner;

  /// Profile tab: the sign-in's provider
  ///
  /// In en, this message translates to:
  /// **'Signed in with {provider}'**
  String accountSignedInWith(String provider);

  /// Profile tab: under Delete account
  ///
  /// In en, this message translates to:
  /// **'Deletes your events in the cloud and on this device, and your shares.'**
  String get accountDeleteNote;

  /// Capture tab: add PDF documents (first in Add)
  ///
  /// In en, this message translates to:
  /// **'Document'**
  String get homeAddDocument;

  /// Capture tab: what Document adds
  ///
  /// In en, this message translates to:
  /// **'PDF files'**
  String get homeAddDocumentDetail;

  /// Event, Add: PDF documents (right after Scan pages)
  ///
  /// In en, this message translates to:
  /// **'Document'**
  String get eventAddDocument;

  /// Event, Add: what Document adds
  ///
  /// In en, this message translates to:
  /// **'PDF files'**
  String get eventAddDocumentDetail;

  /// A capture's file (photo, PDF, link, ...): rename it
  ///
  /// In en, this message translates to:
  /// **'Rename file'**
  String get eventRenameFile;

  /// A link in a capture's list: show it on its own screen (title, address, Copy, Delete); a tap on the row opens the link in the browser
  ///
  /// In en, this message translates to:
  /// **'Details'**
  String get eventFileDetails;

  /// Share: the capture's link was copied to the clipboard
  ///
  /// In en, this message translates to:
  /// **'Link copied'**
  String get eventLinkCopied;

  /// Fix: the strings were lined up
  ///
  /// In en, this message translates to:
  /// **'Tab lined up: every string\'s bars and end match'**
  String get textViewFixLinedUp;

  /// Fix: nothing to line up
  ///
  /// In en, this message translates to:
  /// **'The tab\'s strings already line up'**
  String get textViewFixAlreadyLinedUp;

  /// Fix without Premium: lined up; the online check is Premium's
  ///
  /// In en, this message translates to:
  /// **'Tab lined up. Checking it against the song online is part of TabCam Premium.'**
  String get textViewFixLinedUpPremium;

  /// Welcome screen (signed out): what TabCam does, and to sign in
  ///
  /// In en, this message translates to:
  /// **'Scan guitar tabs, read them as text, and share them. Sign in to start: your captures are kept on every device you sign in on.'**
  String get welcomeBody;

  /// Capture and a capture's screen: shown while files are dragged over them
  ///
  /// In en, this message translates to:
  /// **'Drop files to add'**
  String get dropFilesToAdd;
}

class _AppLocalizationsDelegate
    extends LocalizationsDelegate<AppLocalizations> {
  const _AppLocalizationsDelegate();

  @override
  Future<AppLocalizations> load(Locale locale) {
    return SynchronousFuture<AppLocalizations>(lookupAppLocalizations(locale));
  }

  @override
  bool isSupported(Locale locale) =>
      <String>['en', 'es', 'pt'].contains(locale.languageCode);

  @override
  bool shouldReload(_AppLocalizationsDelegate old) => false;
}

AppLocalizations lookupAppLocalizations(Locale locale) {
  // Lookup logic when only language code is specified.
  switch (locale.languageCode) {
    case 'en':
      return AppLocalizationsEn();
    case 'es':
      return AppLocalizationsEs();
    case 'pt':
      return AppLocalizationsPt();
  }

  throw FlutterError(
    'AppLocalizations.delegate failed to load unsupported locale "$locale". This is likely '
    'an issue with the localizations generation tool. Please file an issue '
    'on GitHub with a reproducible sample app and the gen-l10n configuration '
    'that was used.',
  );
}
