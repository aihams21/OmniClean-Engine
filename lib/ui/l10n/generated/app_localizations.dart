import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:flutter/widgets.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:intl/intl.dart' as intl;

import 'app_localizations_ar.dart';
import 'app_localizations_en.dart';

// ignore_for_file: type=lint

/// Callers can lookup localized strings with an instance of AppLocalizations
/// returned by `AppLocalizations.of(context)`.
///
/// Applications need to include `AppLocalizations.delegate()` in their app's
/// `localizationDelegates` list, and the locales they support in the app's
/// `supportedLocales` list. For example:
///
/// ```dart
/// import 'generated/app_localizations.dart';
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

  static AppLocalizations of(BuildContext context) {
    return Localizations.of<AppLocalizations>(context, AppLocalizations)!;
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
    Locale('ar'),
  ];

  /// No description provided for @appTitle.
  ///
  /// In en, this message translates to:
  /// **'OmniClean Engine'**
  String get appTitle;

  /// No description provided for @navDashboard.
  ///
  /// In en, this message translates to:
  /// **'Dashboard'**
  String get navDashboard;

  /// No description provided for @navCleaner.
  ///
  /// In en, this message translates to:
  /// **'Cleaner'**
  String get navCleaner;

  /// No description provided for @navDuplicates.
  ///
  /// In en, this message translates to:
  /// **'Duplicates'**
  String get navDuplicates;

  /// No description provided for @navQuarantine.
  ///
  /// In en, this message translates to:
  /// **'Quarantine'**
  String get navQuarantine;

  /// No description provided for @navSettings.
  ///
  /// In en, this message translates to:
  /// **'Settings'**
  String get navSettings;

  /// No description provided for @actionCancel.
  ///
  /// In en, this message translates to:
  /// **'Cancel'**
  String get actionCancel;

  /// No description provided for @actionClose.
  ///
  /// In en, this message translates to:
  /// **'Close'**
  String get actionClose;

  /// No description provided for @actionConfirm.
  ///
  /// In en, this message translates to:
  /// **'Confirm'**
  String get actionConfirm;

  /// No description provided for @actionContinue.
  ///
  /// In en, this message translates to:
  /// **'Continue'**
  String get actionContinue;

  /// No description provided for @actionRestore.
  ///
  /// In en, this message translates to:
  /// **'Restore'**
  String get actionRestore;

  /// No description provided for @actionPurge.
  ///
  /// In en, this message translates to:
  /// **'Delete forever'**
  String get actionPurge;

  /// No description provided for @actionOk.
  ///
  /// In en, this message translates to:
  /// **'OK'**
  String get actionOk;

  /// No description provided for @dashboardTitle.
  ///
  /// In en, this message translates to:
  /// **'Command centre'**
  String get dashboardTitle;

  /// No description provided for @dashboardSubtitle.
  ///
  /// In en, this message translates to:
  /// **'Live health of this machine and everything it can reclaim.'**
  String get dashboardSubtitle;

  /// No description provided for @dashboardReclaimable.
  ///
  /// In en, this message translates to:
  /// **'Reclaimable now'**
  String get dashboardReclaimable;

  /// No description provided for @dashboardHeldBack.
  ///
  /// In en, this message translates to:
  /// **'Held back by running apps'**
  String get dashboardHeldBack;

  /// No description provided for @dashboardScanAll.
  ///
  /// In en, this message translates to:
  /// **'Scan everything'**
  String get dashboardScanAll;

  /// No description provided for @dashboardCleanSelected.
  ///
  /// In en, this message translates to:
  /// **'Clean selected'**
  String get dashboardCleanSelected;

  /// No description provided for @dashboardNothingScanned.
  ///
  /// In en, this message translates to:
  /// **'No scan yet. Start one to see what this machine can reclaim.'**
  String get dashboardNothingScanned;

  /// No description provided for @dashboardScanDuration.
  ///
  /// In en, this message translates to:
  /// **'Scan finished in {seconds}s'**
  String dashboardScanDuration(Object seconds);

  /// No description provided for @dashboardCancelled.
  ///
  /// In en, this message translates to:
  /// **'Scan cancelled — results are incomplete'**
  String get dashboardCancelled;

  /// No description provided for @dashboardFilesCount.
  ///
  /// In en, this message translates to:
  /// **'{count, plural, =0{No files} =1{1 file} other{{count} files}}'**
  String dashboardFilesCount(int count);

  /// No description provided for @dashboardActivityLog.
  ///
  /// In en, this message translates to:
  /// **'Activity log'**
  String get dashboardActivityLog;

  /// No description provided for @dashboardLogEmpty.
  ///
  /// In en, this message translates to:
  /// **'Nothing logged yet.'**
  String get dashboardLogEmpty;

  /// No description provided for @dashboardLoadAverage.
  ///
  /// In en, this message translates to:
  /// **'Load average'**
  String get dashboardLoadAverage;

  /// No description provided for @dashboardUptime.
  ///
  /// In en, this message translates to:
  /// **'Uptime'**
  String get dashboardUptime;

  /// No description provided for @dashboardCores.
  ///
  /// In en, this message translates to:
  /// **'{count, plural, =1{1 core} other{{count} cores}}'**
  String dashboardCores(int count);

  /// No description provided for @dashboardStorage.
  ///
  /// In en, this message translates to:
  /// **'Storage'**
  String get dashboardStorage;

  /// No description provided for @dashboardStorageFree.
  ///
  /// In en, this message translates to:
  /// **'{bytes} free of {total}'**
  String dashboardStorageFree(String bytes, String total);

  /// No description provided for @dashboardMoreDisks.
  ///
  /// In en, this message translates to:
  /// **'+{count} more'**
  String dashboardMoreDisks(int count);

  /// No description provided for @gaugeCpu.
  ///
  /// In en, this message translates to:
  /// **'CPU'**
  String get gaugeCpu;

  /// No description provided for @gaugeMemory.
  ///
  /// In en, this message translates to:
  /// **'Memory'**
  String get gaugeMemory;

  /// No description provided for @gaugeSwap.
  ///
  /// In en, this message translates to:
  /// **'Swap'**
  String get gaugeSwap;

  /// No description provided for @unavailable.
  ///
  /// In en, this message translates to:
  /// **'unavailable'**
  String get unavailable;

  /// No description provided for @cleanerTitle.
  ///
  /// In en, this message translates to:
  /// **'Cleaner'**
  String get cleanerTitle;

  /// No description provided for @cleanerSubtitle.
  ///
  /// In en, this message translates to:
  /// **'Nothing is deleted here. Everything moves to quarantine and stays restorable.'**
  String get cleanerSubtitle;

  /// No description provided for @cleanerScanAll.
  ///
  /// In en, this message translates to:
  /// **'Scan all modules'**
  String get cleanerScanAll;

  /// No description provided for @cleanerRescan.
  ///
  /// In en, this message translates to:
  /// **'Rescan'**
  String get cleanerRescan;

  /// No description provided for @cleanerCleanSelected.
  ///
  /// In en, this message translates to:
  /// **'Clean selected'**
  String get cleanerCleanSelected;

  /// No description provided for @cleanerSelectAll.
  ///
  /// In en, this message translates to:
  /// **'Select all'**
  String get cleanerSelectAll;

  /// No description provided for @cleanerSelectNone.
  ///
  /// In en, this message translates to:
  /// **'Clear selection'**
  String get cleanerSelectNone;

  /// No description provided for @cleanerNothingFound.
  ///
  /// In en, this message translates to:
  /// **'Nothing to clean in this module.'**
  String get cleanerNothingFound;

  /// No description provided for @cleanerNothingScanned.
  ///
  /// In en, this message translates to:
  /// **'Run a scan to measure every module first.'**
  String get cleanerNothingScanned;

  /// No description provided for @cleanerRequiresRoot.
  ///
  /// In en, this message translates to:
  /// **'Administrator rights required'**
  String get cleanerRequiresRoot;

  /// No description provided for @cleanerRootPrompt.
  ///
  /// In en, this message translates to:
  /// **'OmniClean needs administrator rights to clean system caches.'**
  String get cleanerRootPrompt;

  /// No description provided for @cleanerIdling.
  ///
  /// In en, this message translates to:
  /// **'Idle'**
  String get cleanerIdling;

  /// No description provided for @cleanerScanning.
  ///
  /// In en, this message translates to:
  /// **'Scanning…'**
  String get cleanerScanning;

  /// No description provided for @cleanerCleaning.
  ///
  /// In en, this message translates to:
  /// **'Cleaning…'**
  String get cleanerCleaning;

  /// No description provided for @cleanerDone.
  ///
  /// In en, this message translates to:
  /// **'Done'**
  String get cleanerDone;

  /// No description provided for @cleanerFailed.
  ///
  /// In en, this message translates to:
  /// **'Failed'**
  String get cleanerFailed;

  /// No description provided for @riskSafe.
  ///
  /// In en, this message translates to:
  /// **'Safe'**
  String get riskSafe;

  /// No description provided for @riskModerate.
  ///
  /// In en, this message translates to:
  /// **'Moderate'**
  String get riskModerate;

  /// No description provided for @riskElevated.
  ///
  /// In en, this message translates to:
  /// **'Elevated'**
  String get riskElevated;

  /// No description provided for @cleanerConfirmTitle.
  ///
  /// In en, this message translates to:
  /// **'Move to quarantine?'**
  String get cleanerConfirmTitle;

  /// No description provided for @cleanerConfirmBody.
  ///
  /// In en, this message translates to:
  /// **'{files, plural, =1{1 file} other{{files} files}} · {bytes} will be moved to quarantine. You can restore every item from the Quarantine screen.'**
  String cleanerConfirmBody(int files, String bytes);

  /// No description provided for @cleanerConfirmProceed.
  ///
  /// In en, this message translates to:
  /// **'Move to quarantine'**
  String get cleanerConfirmProceed;

  /// No description provided for @cleanerResultBody.
  ///
  /// In en, this message translates to:
  /// **'Reclaimed {bytes} from {files, plural, =1{1 file} other{{files} files}}.'**
  String cleanerResultBody(String bytes, int files);

  /// No description provided for @cleanerSkippedNote.
  ///
  /// In en, this message translates to:
  /// **'{count, plural, =1{1 item was held back} other{{count} items were held back}} by the safety gate.'**
  String cleanerSkippedNote(int count);

  /// No description provided for @cleanerProgress.
  ///
  /// In en, this message translates to:
  /// **'{done} of {total}'**
  String cleanerProgress(int done, int total);

  /// No description provided for @cleanerHeldBack.
  ///
  /// In en, this message translates to:
  /// **'{bytes} held back (still in use)'**
  String cleanerHeldBack(String bytes);

  /// No description provided for @duplicatesTitle.
  ///
  /// In en, this message translates to:
  /// **'Duplicate finder'**
  String get duplicatesTitle;

  /// No description provided for @duplicatesSubtitle.
  ///
  /// In en, this message translates to:
  /// **'Content-based, never name-based. Every file is verified with SHA-256.'**
  String get duplicatesSubtitle;

  /// No description provided for @duplicatesRoots.
  ///
  /// In en, this message translates to:
  /// **'Folders to scan'**
  String get duplicatesRoots;

  /// No description provided for @duplicatesRootHint.
  ///
  /// In en, this message translates to:
  /// **'/home/you/Downloads'**
  String get duplicatesRootHint;

  /// No description provided for @duplicatesAddRoot.
  ///
  /// In en, this message translates to:
  /// **'Add folder'**
  String get duplicatesAddRoot;

  /// No description provided for @duplicatesRemoveRoot.
  ///
  /// In en, this message translates to:
  /// **'Remove'**
  String get duplicatesRemoveRoot;

  /// No description provided for @duplicatesNoRoots.
  ///
  /// In en, this message translates to:
  /// **'Add at least one folder to scan.'**
  String get duplicatesNoRoots;

  /// No description provided for @duplicatesFind.
  ///
  /// In en, this message translates to:
  /// **'Find duplicates'**
  String get duplicatesFind;

  /// No description provided for @duplicatesCancelScan.
  ///
  /// In en, this message translates to:
  /// **'Stop scan'**
  String get duplicatesCancelScan;

  /// No description provided for @duplicatesPhaseWalking.
  ///
  /// In en, this message translates to:
  /// **'Walking folders…'**
  String get duplicatesPhaseWalking;

  /// No description provided for @duplicatesPhasePreFiltering.
  ///
  /// In en, this message translates to:
  /// **'Comparing sizes…'**
  String get duplicatesPhasePreFiltering;

  /// No description provided for @duplicatesPhaseHashing.
  ///
  /// In en, this message translates to:
  /// **'Hashing contents…'**
  String get duplicatesPhaseHashing;

  /// No description provided for @duplicatesPhaseDone.
  ///
  /// In en, this message translates to:
  /// **'Done'**
  String get duplicatesPhaseDone;

  /// No description provided for @duplicatesSummary.
  ///
  /// In en, this message translates to:
  /// **'{groups, plural, =0{No duplicate groups} =1{1 group} other{{groups} groups}} · {bytes} wasted'**
  String duplicatesSummary(int groups, String bytes);

  /// No description provided for @duplicatesCopies.
  ///
  /// In en, this message translates to:
  /// **'{count, plural, =1{1 copy} other{{count} copies}}'**
  String duplicatesCopies(int count);

  /// No description provided for @duplicatesKeep.
  ///
  /// In en, this message translates to:
  /// **'Keep'**
  String get duplicatesKeep;

  /// No description provided for @duplicatesCopiesLabel.
  ///
  /// In en, this message translates to:
  /// **'Copies to keep'**
  String get duplicatesCopiesLabel;

  /// No description provided for @duplicatesDeleteDuplicates.
  ///
  /// In en, this message translates to:
  /// **'Delete the rest'**
  String get duplicatesDeleteDuplicates;

  /// No description provided for @duplicatesSelectedCount.
  ///
  /// In en, this message translates to:
  /// **'{count, plural, =0{Nothing selected} =1{1 file selected} other{{count} files selected}}'**
  String duplicatesSelectedCount(int count);

  /// No description provided for @duplicatesConfirmTitle.
  ///
  /// In en, this message translates to:
  /// **'Delete {count, plural, =1{1 copy} other{{count} copies}}?'**
  String duplicatesConfirmTitle(int count);

  /// No description provided for @duplicatesConfirmBody.
  ///
  /// In en, this message translates to:
  /// **'The copy you kept stays untouched. The rest moves to quarantine and can be restored at any time.'**
  String get duplicatesConfirmBody;

  /// No description provided for @duplicatesSuggested.
  ///
  /// In en, this message translates to:
  /// **'Suggested keeper'**
  String get duplicatesSuggested;

  /// No description provided for @duplicatesHashPrefix.
  ///
  /// In en, this message translates to:
  /// **'SHA-256 {prefix}…'**
  String duplicatesHashPrefix(String prefix);

  /// No description provided for @quarantineTitle.
  ///
  /// In en, this message translates to:
  /// **'Quarantine'**
  String get quarantineTitle;

  /// No description provided for @quarantineSubtitle.
  ///
  /// In en, this message translates to:
  /// **'Nothing OmniClean removes is ever destroyed. It waits here until you restore or purge it.'**
  String get quarantineSubtitle;

  /// No description provided for @quarantineEmpty.
  ///
  /// In en, this message translates to:
  /// **'The quarantine is empty.'**
  String get quarantineEmpty;

  /// No description provided for @quarantineHolding.
  ///
  /// In en, this message translates to:
  /// **'Holding {bytes}'**
  String quarantineHolding(String bytes);

  /// No description provided for @quarantineItemCount.
  ///
  /// In en, this message translates to:
  /// **'{count, plural, =0{No items} =1{1 item} other{{count} items}}'**
  String quarantineItemCount(int count);

  /// No description provided for @quarantineFrom.
  ///
  /// In en, this message translates to:
  /// **'From {module}'**
  String quarantineFrom(String module);

  /// No description provided for @quarantineWhen.
  ///
  /// In en, this message translates to:
  /// **'Quarantined {when}'**
  String quarantineWhen(String when);

  /// No description provided for @quarantineRestoreOne.
  ///
  /// In en, this message translates to:
  /// **'Item restored.'**
  String get quarantineRestoreOne;

  /// No description provided for @quarantinePurgeOne.
  ///
  /// In en, this message translates to:
  /// **'Item deleted forever.'**
  String get quarantinePurgeOne;

  /// No description provided for @quarantinePurgeTitle.
  ///
  /// In en, this message translates to:
  /// **'Delete forever?'**
  String get quarantinePurgeTitle;

  /// No description provided for @quarantinePurgeBody.
  ///
  /// In en, this message translates to:
  /// **'{count, plural, =1{1 quarantined item} other{{count} quarantined items}} will be permanently deleted. This cannot be undone.'**
  String quarantinePurgeBody(int count);

  /// No description provided for @quarantinePurgeAll.
  ///
  /// In en, this message translates to:
  /// **'Purge everything'**
  String get quarantinePurgeAll;

  /// No description provided for @quarantineExpiredNote.
  ///
  /// In en, this message translates to:
  /// **'{count, plural, =0{Nothing past its restore window} =1{1 item is past its restore window} other{{count} items are past their restore window}}'**
  String quarantineExpiredNote(int count);

  /// No description provided for @quarantineRetention.
  ///
  /// In en, this message translates to:
  /// **'Restore window: {days, plural, =1{1 day} other{{days} days}}'**
  String quarantineRetention(int days);

  /// No description provided for @settingsTitle.
  ///
  /// In en, this message translates to:
  /// **'Settings'**
  String get settingsTitle;

  /// No description provided for @settingsAppearance.
  ///
  /// In en, this message translates to:
  /// **'Appearance'**
  String get settingsAppearance;

  /// No description provided for @settingsAccent.
  ///
  /// In en, this message translates to:
  /// **'Accent theme'**
  String get settingsAccent;

  /// No description provided for @themeCyber.
  ///
  /// In en, this message translates to:
  /// **'Cyber Green'**
  String get themeCyber;

  /// No description provided for @themeCrimson.
  ///
  /// In en, this message translates to:
  /// **'Deep Crimson'**
  String get themeCrimson;

  /// No description provided for @themeCyberHint.
  ///
  /// In en, this message translates to:
  /// **'Green signal. The classic terminal.'**
  String get themeCyberHint;

  /// No description provided for @themeCrimsonHint.
  ///
  /// In en, this message translates to:
  /// **'Red alert. For the loud ones.'**
  String get themeCrimsonHint;

  /// No description provided for @settingsLanguageSection.
  ///
  /// In en, this message translates to:
  /// **'Language'**
  String get settingsLanguageSection;

  /// No description provided for @settingsLanguage.
  ///
  /// In en, this message translates to:
  /// **'App language'**
  String get settingsLanguage;

  /// No description provided for @langSystem.
  ///
  /// In en, this message translates to:
  /// **'Follow the system'**
  String get langSystem;

  /// No description provided for @langEnglish.
  ///
  /// In en, this message translates to:
  /// **'English'**
  String get langEnglish;

  /// No description provided for @langArabic.
  ///
  /// In en, this message translates to:
  /// **'العربية'**
  String get langArabic;

  /// No description provided for @settingsSafety.
  ///
  /// In en, this message translates to:
  /// **'Safety'**
  String get settingsSafety;

  /// No description provided for @settingsMinAge.
  ///
  /// In en, this message translates to:
  /// **'Minimum file age'**
  String get settingsMinAge;

  /// No description provided for @settingsMinAgeValue.
  ///
  /// In en, this message translates to:
  /// **'{hours, plural, =1{1 hour} other{{hours} hours}}'**
  String settingsMinAgeValue(int hours);

  /// No description provided for @settingsMinAgeHint.
  ///
  /// In en, this message translates to:
  /// **'Files touched more recently than this are never touched — a running app may still need them.'**
  String get settingsMinAgeHint;

  /// No description provided for @settingsRetention.
  ///
  /// In en, this message translates to:
  /// **'Restore window'**
  String get settingsRetention;

  /// No description provided for @settingsRetentionHint.
  ///
  /// In en, this message translates to:
  /// **'Quarantined items older than this are offered for permanent deletion.'**
  String get settingsRetentionHint;

  /// No description provided for @settingsQuarantinePath.
  ///
  /// In en, this message translates to:
  /// **'Quarantine location'**
  String get settingsQuarantinePath;

  /// No description provided for @settingsDiagnostics.
  ///
  /// In en, this message translates to:
  /// **'Diagnostics'**
  String get settingsDiagnostics;

  /// No description provided for @settingsRootAccess.
  ///
  /// In en, this message translates to:
  /// **'Administrator access'**
  String get settingsRootAccess;

  /// No description provided for @rootAvailable.
  ///
  /// In en, this message translates to:
  /// **'Available'**
  String get rootAvailable;

  /// No description provided for @rootUnavailable.
  ///
  /// In en, this message translates to:
  /// **'Not available'**
  String get rootUnavailable;

  /// No description provided for @rootUnavailableHint.
  ///
  /// In en, this message translates to:
  /// **'System modules will report that they need elevation.'**
  String get rootUnavailableHint;

  /// No description provided for @settingsOpenLog.
  ///
  /// In en, this message translates to:
  /// **'Activity log'**
  String get settingsOpenLog;

  /// No description provided for @settingsAbout.
  ///
  /// In en, this message translates to:
  /// **'About'**
  String get settingsAbout;

  /// No description provided for @aboutHeadline.
  ///
  /// In en, this message translates to:
  /// **'A cross-platform cleaner that refuses to lie.'**
  String get aboutHeadline;

  /// No description provided for @aboutBody.
  ///
  /// In en, this message translates to:
  /// **'OmniClean never unlinks a file. Everything it collects moves into a quarantine you control, and a hard deny-list blocks system paths, credentials and databases before a single byte is read.'**
  String get aboutBody;

  /// No description provided for @versionLabel.
  ///
  /// In en, this message translates to:
  /// **'Version {version} ({build})'**
  String versionLabel(String version, String build);

  /// No description provided for @settingsReset.
  ///
  /// In en, this message translates to:
  /// **'Reset to defaults'**
  String get settingsReset;

  /// No description provided for @settingsResetDone.
  ///
  /// In en, this message translates to:
  /// **'Settings reset.'**
  String get settingsResetDone;

  /// No description provided for @platformLabel.
  ///
  /// In en, this message translates to:
  /// **'Detected platform: {platform}'**
  String platformLabel(String platform);

  /// No description provided for @riskWhyElevated.
  ///
  /// In en, this message translates to:
  /// **'Touches system-owned files. Run as administrator.'**
  String get riskWhyElevated;

  /// No description provided for @riskWhyModerate.
  ///
  /// In en, this message translates to:
  /// **'Removes files that a running app may still recreate.'**
  String get riskWhyModerate;

  /// No description provided for @riskWhySafe.
  ///
  /// In en, this message translates to:
  /// **'Only regenerable caches and temporary data.'**
  String get riskWhySafe;

  /// No description provided for @errorGeneric.
  ///
  /// In en, this message translates to:
  /// **'Something went wrong: {message}'**
  String errorGeneric(String message);

  /// targetAptArchiveTitle
  ///
  /// In en, this message translates to:
  /// **'APT package archive'**
  String get targetAptArchiveTitle;

  /// targetAptArchiveDescription
  ///
  /// In en, this message translates to:
  /// **'Downloaded .deb files kept for reinstall'**
  String get targetAptArchiveDescription;

  /// targetAptListsTitle
  ///
  /// In en, this message translates to:
  /// **'APT package lists'**
  String get targetAptListsTitle;

  /// targetAptListsDescription
  ///
  /// In en, this message translates to:
  /// **'Indexes apt refreshes from the network'**
  String get targetAptListsDescription;

  /// targetJournalTitle
  ///
  /// In en, this message translates to:
  /// **'System journal'**
  String get targetJournalTitle;

  /// targetJournalDescription
  ///
  /// In en, this message translates to:
  /// **'systemd logs for the whole machine'**
  String get targetJournalDescription;

  /// targetCrashReportsTitle
  ///
  /// In en, this message translates to:
  /// **'Crash reports'**
  String get targetCrashReportsTitle;

  /// targetCrashReportsDescription
  ///
  /// In en, this message translates to:
  /// **'Saved kernel panic and crash dumps'**
  String get targetCrashReportsDescription;

  /// targetTmpTitle
  ///
  /// In en, this message translates to:
  /// **'Temporary files'**
  String get targetTmpTitle;

  /// targetTmpDescription
  ///
  /// In en, this message translates to:
  /// **'Leftovers in /tmp and /var/tmp'**
  String get targetTmpDescription;

  /// targetHomeCacheTitle
  ///
  /// In en, this message translates to:
  /// **'User cache'**
  String get targetHomeCacheTitle;

  /// targetHomeCacheDescription
  ///
  /// In en, this message translates to:
  /// **'The cache folder of this account'**
  String get targetHomeCacheDescription;

  /// targetUserJournalTitle
  ///
  /// In en, this message translates to:
  /// **'Personal journal'**
  String get targetUserJournalTitle;

  /// targetUserJournalDescription
  ///
  /// In en, this message translates to:
  /// **'Logs owned by this account only'**
  String get targetUserJournalDescription;

  /// targetTrashTitle
  ///
  /// In en, this message translates to:
  /// **'Trash'**
  String get targetTrashTitle;

  /// targetTrashDescription
  ///
  /// In en, this message translates to:
  /// **'Deleted files still waiting in the bin'**
  String get targetTrashDescription;

  /// targetFlatpakCacheTitle
  ///
  /// In en, this message translates to:
  /// **'Flatpak cache'**
  String get targetFlatpakCacheTitle;

  /// targetFlatpakCacheDescription
  ///
  /// In en, this message translates to:
  /// **'Downloaded bundles and build leftovers'**
  String get targetFlatpakCacheDescription;

  /// targetThumbnailsTitle
  ///
  /// In en, this message translates to:
  /// **'Thumbnails'**
  String get targetThumbnailsTitle;

  /// targetThumbnailsDescription
  ///
  /// In en, this message translates to:
  /// **'Preview images for files you already have'**
  String get targetThumbnailsDescription;

  /// targetUserTempTitle
  ///
  /// In en, this message translates to:
  /// **'User temporary files'**
  String get targetUserTempTitle;

  /// targetUserTempDescription
  ///
  /// In en, this message translates to:
  /// **'The Temp folder of your profile'**
  String get targetUserTempDescription;

  /// targetWindowsTempTitle
  ///
  /// In en, this message translates to:
  /// **'Windows temporary files'**
  String get targetWindowsTempTitle;

  /// targetWindowsTempDescription
  ///
  /// In en, this message translates to:
  /// **'C:\\Windows\\Temp'**
  String get targetWindowsTempDescription;

  /// targetEdgeCacheTitle
  ///
  /// In en, this message translates to:
  /// **'Microsoft Edge cache'**
  String get targetEdgeCacheTitle;

  /// targetEdgeCacheDescription
  ///
  /// In en, this message translates to:
  /// **'Browsing data that can be rebuilt'**
  String get targetEdgeCacheDescription;

  /// targetChromeCacheTitle
  ///
  /// In en, this message translates to:
  /// **'Google Chrome cache'**
  String get targetChromeCacheTitle;

  /// targetChromeCacheDescription
  ///
  /// In en, this message translates to:
  /// **'Browsing data that can be rebuilt'**
  String get targetChromeCacheDescription;

  /// targetFirefoxCacheTitle
  ///
  /// In en, this message translates to:
  /// **'Firefox cache'**
  String get targetFirefoxCacheTitle;

  /// targetFirefoxCacheDescription
  ///
  /// In en, this message translates to:
  /// **'Disk cache of the installed profiles'**
  String get targetFirefoxCacheDescription;

  /// targetEventLogsTitle
  ///
  /// In en, this message translates to:
  /// **'Event logs'**
  String get targetEventLogsTitle;

  /// targetEventLogsDescription
  ///
  /// In en, this message translates to:
  /// **'Archived Windows event log records'**
  String get targetEventLogsDescription;

  /// targetErrorReportingTitle
  ///
  /// In en, this message translates to:
  /// **'Error reports'**
  String get targetErrorReportingTitle;

  /// targetErrorReportingDescription
  ///
  /// In en, this message translates to:
  /// **'Files queued for Windows Error Reporting'**
  String get targetErrorReportingDescription;

  /// targetMinidumpsTitle
  ///
  /// In en, this message translates to:
  /// **'Small memory dumps'**
  String get targetMinidumpsTitle;

  /// targetMinidumpsDescription
  ///
  /// In en, this message translates to:
  /// **'Minidumps written after a blue screen'**
  String get targetMinidumpsDescription;

  /// targetUpdateDownloadTitle
  ///
  /// In en, this message translates to:
  /// **'Windows Update downloads'**
  String get targetUpdateDownloadTitle;

  /// targetUpdateDownloadDescription
  ///
  /// In en, this message translates to:
  /// **'Package downloads waiting to install'**
  String get targetUpdateDownloadDescription;

  /// targetDeliveryOptimizationTitle
  ///
  /// In en, this message translates to:
  /// **'Delivery Optimization'**
  String get targetDeliveryOptimizationTitle;

  /// targetDeliveryOptimizationDescription
  ///
  /// In en, this message translates to:
  /// **'Peer-to-peer update cache'**
  String get targetDeliveryOptimizationDescription;

  /// targetInstallerPendingTitle
  ///
  /// In en, this message translates to:
  /// **'Pending installs'**
  String get targetInstallerPendingTitle;

  /// targetInstallerPendingDescription
  ///
  /// In en, this message translates to:
  /// **'Installer work queued for a reboot'**
  String get targetInstallerPendingDescription;

  /// targetSetupLogsTitle
  ///
  /// In en, this message translates to:
  /// **'Setup logs'**
  String get targetSetupLogsTitle;

  /// targetSetupLogsDescription
  ///
  /// In en, this message translates to:
  /// **'Logs from the last Windows installation'**
  String get targetSetupLogsDescription;

  /// targetAppCacheRootTitle
  ///
  /// In en, this message translates to:
  /// **'All app caches'**
  String get targetAppCacheRootTitle;

  /// targetAppCacheRootDescription
  ///
  /// In en, this message translates to:
  /// **'Caches of every installed app'**
  String get targetAppCacheRootDescription;

  /// targetAppCacheSelfTitle
  ///
  /// In en, this message translates to:
  /// **'OmniClean cache'**
  String get targetAppCacheSelfTitle;

  /// targetAppCacheSelfDescription
  ///
  /// In en, this message translates to:
  /// **'This application working files'**
  String get targetAppCacheSelfDescription;

  /// targetDownloadsJunkTitle
  ///
  /// In en, this message translates to:
  /// **'Downloads junk'**
  String get targetDownloadsJunkTitle;

  /// targetDownloadsJunkDescription
  ///
  /// In en, this message translates to:
  /// **'Interrupted and obsolete installers'**
  String get targetDownloadsJunkDescription;

  /// targetObbLeftoversTitle
  ///
  /// In en, this message translates to:
  /// **'Expansion leftovers'**
  String get targetObbLeftoversTitle;

  /// targetObbLeftoversDescription
  ///
  /// In en, this message translates to:
  /// **'Data packs of apps you uninstalled'**
  String get targetObbLeftoversDescription;

  /// targetMediaThumbnailsTitle
  ///
  /// In en, this message translates to:
  /// **'Media thumbnails'**
  String get targetMediaThumbnailsTitle;

  /// targetMediaThumbnailsDescription
  ///
  /// In en, this message translates to:
  /// **'Thumbnails for photos and videos'**
  String get targetMediaThumbnailsDescription;
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
      <String>['ar', 'en'].contains(locale.languageCode);

  @override
  bool shouldReload(_AppLocalizationsDelegate old) => false;
}

AppLocalizations lookupAppLocalizations(Locale locale) {
  // Lookup logic when only language code is specified.
  switch (locale.languageCode) {
    case 'ar':
      return AppLocalizationsAr();
    case 'en':
      return AppLocalizationsEn();
  }

  throw FlutterError(
    'AppLocalizations.delegate failed to load unsupported locale "$locale". This is likely '
    'an issue with the localizations generation tool. Please file an issue '
    'on GitHub with a reproducible sample app and the gen-l10n configuration '
    'that was used.',
  );
}
