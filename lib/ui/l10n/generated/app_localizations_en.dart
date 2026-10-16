// ignore: unused_import
import 'package:intl/intl.dart' as intl;
import 'app_localizations.dart';

// ignore_for_file: type=lint

/// The translations for English (`en`).
class AppLocalizationsEn extends AppLocalizations {
  AppLocalizationsEn([String locale = 'en']) : super(locale);

  @override
  String get appTitle => 'OmniClean Engine';

  @override
  String get navDashboard => 'Dashboard';

  @override
  String get navCleaner => 'Cleaner';

  @override
  String get navDuplicates => 'Duplicates';

  @override
  String get navQuarantine => 'Quarantine';

  @override
  String get navSettings => 'Settings';

  @override
  String get actionCancel => 'Cancel';

  @override
  String get actionClose => 'Close';

  @override
  String get actionConfirm => 'Confirm';

  @override
  String get actionContinue => 'Continue';

  @override
  String get actionRestore => 'Restore';

  @override
  String get actionPurge => 'Delete forever';

  @override
  String get actionOk => 'OK';

  @override
  String get dashboardTitle => 'Command centre';

  @override
  String get dashboardSubtitle =>
      'Live health of this machine and everything it can reclaim.';

  @override
  String get dashboardReclaimable => 'Reclaimable now';

  @override
  String get dashboardHeldBack => 'Held back by running apps';

  @override
  String get dashboardScanAll => 'Scan everything';

  @override
  String get dashboardCleanSelected => 'Clean selected';

  @override
  String get dashboardNothingScanned =>
      'No scan yet. Start one to see what this machine can reclaim.';

  @override
  String dashboardScanDuration(Object seconds) {
    return 'Scan finished in ${seconds}s';
  }

  @override
  String get dashboardCancelled => 'Scan cancelled — results are incomplete';

  @override
  String dashboardFilesCount(int count) {
    String _temp0 = intl.Intl.pluralLogic(
      count,
      locale: localeName,
      other: '$count files',
      one: '1 file',
      zero: 'No files',
    );
    return '$_temp0';
  }

  @override
  String get dashboardActivityLog => 'Activity log';

  @override
  String get dashboardLogEmpty => 'Nothing logged yet.';

  @override
  String get dashboardLoadAverage => 'Load average';

  @override
  String get dashboardUptime => 'Uptime';

  @override
  String dashboardCores(int count) {
    String _temp0 = intl.Intl.pluralLogic(
      count,
      locale: localeName,
      other: '$count cores',
      one: '1 core',
    );
    return '$_temp0';
  }

  @override
  String get dashboardStorage => 'Storage';

  @override
  String dashboardStorageFree(String bytes, String total) {
    return '$bytes free of $total';
  }

  @override
  String dashboardMoreDisks(int count) {
    return '+$count more';
  }

  @override
  String get gaugeCpu => 'CPU';

  @override
  String get gaugeMemory => 'Memory';

  @override
  String get gaugeSwap => 'Swap';

  @override
  String get unavailable => 'unavailable';

  @override
  String get cleanerTitle => 'Cleaner';

  @override
  String get cleanerSubtitle =>
      'Nothing is deleted here. Everything moves to quarantine and stays restorable.';

  @override
  String get cleanerScanAll => 'Scan all modules';

  @override
  String get cleanerRescan => 'Rescan';

  @override
  String get cleanerCleanSelected => 'Clean selected';

  @override
  String get cleanerSelectAll => 'Select all';

  @override
  String get cleanerSelectNone => 'Clear selection';

  @override
  String get cleanerNothingFound => 'Nothing to clean in this module.';

  @override
  String get cleanerNothingScanned =>
      'Run a scan to measure every module first.';

  @override
  String get cleanerRequiresRoot => 'Administrator rights required';

  @override
  String get cleanerRootPrompt =>
      'OmniClean needs administrator rights to clean system caches.';

  @override
  String get cleanerIdling => 'Idle';

  @override
  String get cleanerScanning => 'Scanning…';

  @override
  String get cleanerCleaning => 'Cleaning…';

  @override
  String get cleanerDone => 'Done';

  @override
  String get cleanerFailed => 'Failed';

  @override
  String get riskSafe => 'Safe';

  @override
  String get riskModerate => 'Moderate';

  @override
  String get riskElevated => 'Elevated';

  @override
  String get cleanerConfirmTitle => 'Move to quarantine?';

  @override
  String cleanerConfirmBody(int files, String bytes) {
    String _temp0 = intl.Intl.pluralLogic(
      files,
      locale: localeName,
      other: '$files files',
      one: '1 file',
    );
    return '$_temp0 · $bytes will be moved to quarantine. You can restore every item from the Quarantine screen.';
  }

  @override
  String get cleanerConfirmProceed => 'Move to quarantine';

  @override
  String cleanerResultBody(String bytes, int files) {
    String _temp0 = intl.Intl.pluralLogic(
      files,
      locale: localeName,
      other: '$files files',
      one: '1 file',
    );
    return 'Reclaimed $bytes from $_temp0.';
  }

  @override
  String cleanerSkippedNote(int count) {
    String _temp0 = intl.Intl.pluralLogic(
      count,
      locale: localeName,
      other: '$count items were held back',
      one: '1 item was held back',
    );
    return '$_temp0 by the safety gate.';
  }

  @override
  String cleanerProgress(int done, int total) {
    return '$done of $total';
  }

  @override
  String cleanerHeldBack(String bytes) {
    return '$bytes held back (still in use)';
  }

  @override
  String get duplicatesTitle => 'Duplicate finder';

  @override
  String get duplicatesSubtitle =>
      'Content-based, never name-based. Every file is verified with SHA-256.';

  @override
  String get duplicatesRoots => 'Folders to scan';

  @override
  String get duplicatesRootHint => '/home/you/Downloads';

  @override
  String get duplicatesAddRoot => 'Add folder';

  @override
  String get duplicatesRemoveRoot => 'Remove';

  @override
  String get duplicatesNoRoots => 'Add at least one folder to scan.';

  @override
  String get duplicatesFind => 'Find duplicates';

  @override
  String get duplicatesCancelScan => 'Stop scan';

  @override
  String get duplicatesPhaseWalking => 'Walking folders…';

  @override
  String get duplicatesPhasePreFiltering => 'Comparing sizes…';

  @override
  String get duplicatesPhaseHashing => 'Hashing contents…';

  @override
  String get duplicatesPhaseDone => 'Done';

  @override
  String duplicatesSummary(int groups, String bytes) {
    String _temp0 = intl.Intl.pluralLogic(
      groups,
      locale: localeName,
      other: '$groups groups',
      one: '1 group',
      zero: 'No duplicate groups',
    );
    return '$_temp0 · $bytes wasted';
  }

  @override
  String duplicatesCopies(int count) {
    String _temp0 = intl.Intl.pluralLogic(
      count,
      locale: localeName,
      other: '$count copies',
      one: '1 copy',
    );
    return '$_temp0';
  }

  @override
  String get duplicatesKeep => 'Keep';

  @override
  String get duplicatesCopiesLabel => 'Copies to keep';

  @override
  String get duplicatesDeleteDuplicates => 'Delete the rest';

  @override
  String duplicatesSelectedCount(int count) {
    String _temp0 = intl.Intl.pluralLogic(
      count,
      locale: localeName,
      other: '$count files selected',
      one: '1 file selected',
      zero: 'Nothing selected',
    );
    return '$_temp0';
  }

  @override
  String duplicatesConfirmTitle(int count) {
    String _temp0 = intl.Intl.pluralLogic(
      count,
      locale: localeName,
      other: '$count copies',
      one: '1 copy',
    );
    return 'Delete $_temp0?';
  }

  @override
  String get duplicatesConfirmBody =>
      'The copy you kept stays untouched. The rest moves to quarantine and can be restored at any time.';

  @override
  String get duplicatesSuggested => 'Suggested keeper';

  @override
  String duplicatesHashPrefix(String prefix) {
    return 'SHA-256 $prefix…';
  }

  @override
  String get quarantineTitle => 'Quarantine';

  @override
  String get quarantineSubtitle =>
      'Nothing OmniClean removes is ever destroyed. It waits here until you restore or purge it.';

  @override
  String get quarantineEmpty => 'The quarantine is empty.';

  @override
  String quarantineHolding(String bytes) {
    return 'Holding $bytes';
  }

  @override
  String quarantineItemCount(int count) {
    String _temp0 = intl.Intl.pluralLogic(
      count,
      locale: localeName,
      other: '$count items',
      one: '1 item',
      zero: 'No items',
    );
    return '$_temp0';
  }

  @override
  String quarantineFrom(String module) {
    return 'From $module';
  }

  @override
  String quarantineWhen(String when) {
    return 'Quarantined $when';
  }

  @override
  String get quarantineRestoreOne => 'Item restored.';

  @override
  String get quarantinePurgeOne => 'Item deleted forever.';

  @override
  String get quarantinePurgeTitle => 'Delete forever?';

  @override
  String quarantinePurgeBody(int count) {
    String _temp0 = intl.Intl.pluralLogic(
      count,
      locale: localeName,
      other: '$count quarantined items',
      one: '1 quarantined item',
    );
    return '$_temp0 will be permanently deleted. This cannot be undone.';
  }

  @override
  String get quarantinePurgeAll => 'Purge everything';

  @override
  String quarantineExpiredNote(int count) {
    String _temp0 = intl.Intl.pluralLogic(
      count,
      locale: localeName,
      other: '$count items are past their restore window',
      one: '1 item is past its restore window',
      zero: 'Nothing past its restore window',
    );
    return '$_temp0';
  }

  @override
  String quarantineRetention(int days) {
    String _temp0 = intl.Intl.pluralLogic(
      days,
      locale: localeName,
      other: '$days days',
      one: '1 day',
    );
    return 'Restore window: $_temp0';
  }

  @override
  String get settingsTitle => 'Settings';

  @override
  String get settingsAppearance => 'Appearance';

  @override
  String get settingsAccent => 'Accent theme';

  @override
  String get themeCyber => 'Cyber Green';

  @override
  String get themeCrimson => 'Deep Crimson';

  @override
  String get themeCyberHint => 'Green signal. The classic terminal.';

  @override
  String get themeCrimsonHint => 'Red alert. For the loud ones.';

  @override
  String get settingsLanguageSection => 'Language';

  @override
  String get settingsLanguage => 'App language';

  @override
  String get langSystem => 'Follow the system';

  @override
  String get langEnglish => 'English';

  @override
  String get langArabic => 'العربية';

  @override
  String get settingsSafety => 'Safety';

  @override
  String get settingsMinAge => 'Minimum file age';

  @override
  String settingsMinAgeValue(int hours) {
    String _temp0 = intl.Intl.pluralLogic(
      hours,
      locale: localeName,
      other: '$hours hours',
      one: '1 hour',
    );
    return '$_temp0';
  }

  @override
  String get settingsMinAgeHint =>
      'Files touched more recently than this are never touched — a running app may still need them.';

  @override
  String get settingsRetention => 'Restore window';

  @override
  String get settingsRetentionHint =>
      'Quarantined items older than this are offered for permanent deletion.';

  @override
  String get settingsQuarantinePath => 'Quarantine location';

  @override
  String get settingsDiagnostics => 'Diagnostics';

  @override
  String get settingsRootAccess => 'Administrator access';

  @override
  String get rootAvailable => 'Available';

  @override
  String get rootUnavailable => 'Not available';

  @override
  String get rootUnavailableHint =>
      'System modules will report that they need elevation.';

  @override
  String get settingsOpenLog => 'Activity log';

  @override
  String get settingsAbout => 'About';

  @override
  String get aboutHeadline => 'A cross-platform cleaner that refuses to lie.';

  @override
  String get aboutBody =>
      'OmniClean never unlinks a file. Everything it collects moves into a quarantine you control, and a hard deny-list blocks system paths, credentials and databases before a single byte is read.';

  @override
  String versionLabel(String version, String build) {
    return 'Version $version ($build)';
  }

  @override
  String get settingsReset => 'Reset to defaults';

  @override
  String get settingsResetDone => 'Settings reset.';

  @override
  String platformLabel(String platform) {
    return 'Detected platform: $platform';
  }

  @override
  String get riskWhyElevated =>
      'Touches system-owned files. Run as administrator.';

  @override
  String get riskWhyModerate =>
      'Removes files that a running app may still recreate.';

  @override
  String get riskWhySafe => 'Only regenerable caches and temporary data.';

  @override
  String errorGeneric(String message) {
    return 'Something went wrong: $message';
  }

  @override
  String get targetAptArchiveTitle => 'APT package archive';

  @override
  String get targetAptArchiveDescription =>
      'Downloaded .deb files kept for reinstall';

  @override
  String get targetAptListsTitle => 'APT package lists';

  @override
  String get targetAptListsDescription =>
      'Indexes apt refreshes from the network';

  @override
  String get targetJournalTitle => 'System journal';

  @override
  String get targetJournalDescription => 'systemd logs for the whole machine';

  @override
  String get targetCrashReportsTitle => 'Crash reports';

  @override
  String get targetCrashReportsDescription =>
      'Saved kernel panic and crash dumps';

  @override
  String get targetTmpTitle => 'Temporary files';

  @override
  String get targetTmpDescription => 'Leftovers in /tmp and /var/tmp';

  @override
  String get targetHomeCacheTitle => 'User cache';

  @override
  String get targetHomeCacheDescription => 'The cache folder of this account';

  @override
  String get targetUserJournalTitle => 'Personal journal';

  @override
  String get targetUserJournalDescription => 'Logs owned by this account only';

  @override
  String get targetTrashTitle => 'Trash';

  @override
  String get targetTrashDescription => 'Deleted files still waiting in the bin';

  @override
  String get targetFlatpakCacheTitle => 'Flatpak cache';

  @override
  String get targetFlatpakCacheDescription =>
      'Downloaded bundles and build leftovers';

  @override
  String get targetThumbnailsTitle => 'Thumbnails';

  @override
  String get targetThumbnailsDescription =>
      'Preview images for files you already have';

  @override
  String get targetUserTempTitle => 'User temporary files';

  @override
  String get targetUserTempDescription => 'The Temp folder of your profile';

  @override
  String get targetWindowsTempTitle => 'Windows temporary files';

  @override
  String get targetWindowsTempDescription => 'C:\\Windows\\Temp';

  @override
  String get targetEdgeCacheTitle => 'Microsoft Edge cache';

  @override
  String get targetEdgeCacheDescription => 'Browsing data that can be rebuilt';

  @override
  String get targetChromeCacheTitle => 'Google Chrome cache';

  @override
  String get targetChromeCacheDescription =>
      'Browsing data that can be rebuilt';

  @override
  String get targetFirefoxCacheTitle => 'Firefox cache';

  @override
  String get targetFirefoxCacheDescription =>
      'Disk cache of the installed profiles';

  @override
  String get targetEventLogsTitle => 'Event logs';

  @override
  String get targetEventLogsDescription => 'Archived Windows event log records';

  @override
  String get targetErrorReportingTitle => 'Error reports';

  @override
  String get targetErrorReportingDescription =>
      'Files queued for Windows Error Reporting';

  @override
  String get targetMinidumpsTitle => 'Small memory dumps';

  @override
  String get targetMinidumpsDescription =>
      'Minidumps written after a blue screen';

  @override
  String get targetUpdateDownloadTitle => 'Windows Update downloads';

  @override
  String get targetUpdateDownloadDescription =>
      'Package downloads waiting to install';

  @override
  String get targetDeliveryOptimizationTitle => 'Delivery Optimization';

  @override
  String get targetDeliveryOptimizationDescription =>
      'Peer-to-peer update cache';

  @override
  String get targetInstallerPendingTitle => 'Pending installs';

  @override
  String get targetInstallerPendingDescription =>
      'Installer work queued for a reboot';

  @override
  String get targetSetupLogsTitle => 'Setup logs';

  @override
  String get targetSetupLogsDescription =>
      'Logs from the last Windows installation';

  @override
  String get targetAppCacheRootTitle => 'All app caches';

  @override
  String get targetAppCacheRootDescription => 'Caches of every installed app';

  @override
  String get targetAppCacheSelfTitle => 'OmniClean cache';

  @override
  String get targetAppCacheSelfDescription => 'This application working files';

  @override
  String get targetDownloadsJunkTitle => 'Downloads junk';

  @override
  String get targetDownloadsJunkDescription =>
      'Interrupted and obsolete installers';

  @override
  String get targetObbLeftoversTitle => 'Expansion leftovers';

  @override
  String get targetObbLeftoversDescription =>
      'Data packs of apps you uninstalled';

  @override
  String get targetMediaThumbnailsTitle => 'Media thumbnails';

  @override
  String get targetMediaThumbnailsDescription =>
      'Thumbnails for photos and videos';

  @override
  String get navLibrary => 'Library';

  @override
  String get libraryTitle => 'Library';

  @override
  String get librarySubtitle =>
      'Every photo, video and file the device holds — sorted newest first.';

  @override
  String get libraryLoad => 'Load';

  @override
  String get libraryReloading => 'Reloading';

  @override
  String get libraryKindPhotos => 'Photos';

  @override
  String get libraryKindVideos => 'Videos';

  @override
  String get libraryKindAudio => 'Audio';

  @override
  String get libraryKindDocuments => 'Documents';

  @override
  String get libraryKindDownloads => 'Downloads';

  @override
  String get libraryKindAllFiles => 'All files';

  @override
  String get libraryEmpty => 'Nothing here yet.';

  @override
  String get libraryBlind => 'Storage access needed';

  @override
  String get libraryBlindHint =>
      'OmniClean needs permission to read your photos and files. Nothing is uploaded — the scan runs entirely on this device.';

  @override
  String get libraryGrant => 'Grant access';

  @override
  String libraryCount(int count, String size) {
    return '$count items · $size';
  }

  @override
  String libraryResolution(int width, int height) {
    return '$width x $height';
  }

  @override
  String get libraryFailed => 'The device library could not be read.';

  @override
  String get libraryUseDuplicates => 'Find duplicates';

  @override
  String get navApps => 'Apps';

  @override
  String get unusedAppsTitle => 'Unused apps';

  @override
  String get unusedAppsSubtitle =>
      'Apps you stopped opening, with everything they left behind.';

  @override
  String get unusedAppsLoad => 'Scan my apps';

  @override
  String get unusedAppsRefreshing => 'Reading usage data…';

  @override
  String get unusedAppsIdle =>
      'Nothing is scanned yet. Press the button above and OmniClean will ask the system which apps you stopped opening.';

  @override
  String get unusedAppsEmpty =>
      'No unused apps at this threshold. Raise the threshold to look further back.';

  @override
  String unusedAppsCount(Object count, Object size) {
    return '$count apps · $size';
  }

  @override
  String get unusedAppsNeverOpened => 'Never opened';

  @override
  String unusedAppsIdleDays(Object days) {
    return '$days days idle';
  }

  @override
  String get unusedAppsUninstall => 'Uninstall';

  @override
  String get unusedAppsUninstalling => 'Opening the system uninstaller…';

  @override
  String unusedAppsUninstalled(Object name) {
    return '$name was handed to the system uninstaller.';
  }

  @override
  String get unusedAppsBlind =>
      'Usage access is required. Android only knows which apps you stopped opening if you let it observe usage stats.';

  @override
  String get unusedAppsGrant => 'Allow usage access';

  @override
  String get unusedAppsSystemHidden =>
      'System apps are never suggested for removal.';

  @override
  String get unusedAppsCannotUninstall =>
      'This device does not allow apps to uninstall other apps.';

  @override
  String get unusedAppsThreshold => 'Idle for';

  @override
  String unusedAppsSelected(Object count, Object size) {
    return '$count selected · $size';
  }

  @override
  String get unusedAppsRemoveSelected => 'Uninstall selected';

  @override
  String unusedAppsConfirmTitle(Object count) {
    return 'Uninstall $count apps?';
  }

  @override
  String get unusedAppsConfirmBody =>
      'The system uninstaller opens one app at a time, and you confirm each removal. OmniClean never deletes app data itself.';

  @override
  String get unusedAppsFailed => 'Could not read the app list. Try again.';

  @override
  String get navBoost => 'Boost';

  @override
  String get boostTitle => 'Boost';

  @override
  String get boostSubtitle =>
      'One tap. Real system changes, each one reported back with what the machine actually did.';

  @override
  String get boostRun => 'Boost now';

  @override
  String get boostRunning => 'Boosting…';

  @override
  String get boostRerun => 'Boost again';

  @override
  String get boostNothingAvailable =>
      'Boost needs administrator rights on this platform, so there is nothing here it can honestly promise.';

  @override
  String boostResultHeadline(int done, int total) {
    return '$done of $total steps applied';
  }

  @override
  String get boostNothingChanged =>
      'Nothing changed. Every step below is what the system refused.';

  @override
  String get boostActionAndroidTitle => 'Trim and trim the whole system';

  @override
  String get boostActionAndroidDescription =>
      'Asks Android to release app caches, trims this app\'s memory, and lifts the doze restriction so the launcher stays fast.';

  @override
  String get boostActionPowerPlanTitle =>
      'Switch to the high performance power plan';

  @override
  String get boostActionPowerPlanDescription =>
      'Stops Windows from down-clocking the CPU and GPU to save power while you are working.';

  @override
  String get boostActionWorkingSetsTitle =>
      'Release idle memory from every app';

  @override
  String get boostActionWorkingSetsDescription =>
      'Asks each process to hand back the pages it is holding but not using, which is what stalls a game.';

  @override
  String get boostActionIndexerTitle => 'Pause the search indexer';

  @override
  String get boostActionIndexerDescription =>
      'The indexer re-scans your files in the background and eats the same disk and CPU a game needs.';

  @override
  String get boostActionGovernorTitle => 'Pin the CPU to performance mode';

  @override
  String get boostActionGovernorDescription =>
      'Replaces the power-saving governor so the cores stay at full clock instead of dropping and climbing all game long.';

  @override
  String get boostActionSwappinessTitle => 'Stop the kernel from swapping';

  @override
  String get boostActionSwappinessDescription =>
      'Lower swappiness makes the kernel use your free RAM instead of the slow disk, which is where frame stutter comes from.';

  @override
  String get boostActionDropCachesTitle =>
      'Release the page cache back to the kernel';

  @override
  String get boostActionDropCachesDescription =>
      'Frees the cached file pages so the whole cache is cold and every read after this is a real read.';

  @override
  String get boostActionTrimTitle => 'Trim the SSD';

  @override
  String get boostActionTrimDescription =>
      'Tells the drive which blocks are already deleted, so it stops queueing writes over them.';

  @override
  String get boostImpactFrames => 'Frame rate';

  @override
  String get boostImpactMemory => 'Memory';

  @override
  String get boostImpactLatency => 'Disk latency';

  @override
  String get boostImpactStorage => 'Storage';

  @override
  String get boostRequiresPrivilege => 'Administrator';
}
