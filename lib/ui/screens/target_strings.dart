import '../l10n/generated/app_localizations.dart';

/// Resolves the `titleKey` / `descriptionKey` carried by every [CleanTarget]
/// into a localized string.
///
/// The engine never imports the UI, so modules describe themselves with opaque
/// keys. This is the single place that knows how to turn a key into a sentence
/// — which is what keeps the Arabic build from leaking English identifiers.
extension TargetStrings on AppLocalizations {
  String targetTitle(String key) {
    switch (key) {
      case 'targetAptArchiveTitle':
        return targetAptArchiveTitle;
      case 'targetAptListsTitle':
        return targetAptListsTitle;
      case 'targetJournalTitle':
        return targetJournalTitle;
      case 'targetCrashReportsTitle':
        return targetCrashReportsTitle;
      case 'targetTmpTitle':
        return targetTmpTitle;
      case 'targetHomeCacheTitle':
        return targetHomeCacheTitle;
      case 'targetUserJournalTitle':
        return targetUserJournalTitle;
      case 'targetTrashTitle':
        return targetTrashTitle;
      case 'targetFlatpakCacheTitle':
        return targetFlatpakCacheTitle;
      case 'targetThumbnailsTitle':
        return targetThumbnailsTitle;
      case 'targetUserTempTitle':
        return targetUserTempTitle;
      case 'targetWindowsTempTitle':
        return targetWindowsTempTitle;
      case 'targetEdgeCacheTitle':
        return targetEdgeCacheTitle;
      case 'targetChromeCacheTitle':
        return targetChromeCacheTitle;
      case 'targetFirefoxCacheTitle':
        return targetFirefoxCacheTitle;
      case 'targetEventLogsTitle':
        return targetEventLogsTitle;
      case 'targetErrorReportingTitle':
        return targetErrorReportingTitle;
      case 'targetMinidumpsTitle':
        return targetMinidumpsTitle;
      case 'targetUpdateDownloadTitle':
        return targetUpdateDownloadTitle;
      case 'targetDeliveryOptimizationTitle':
        return targetDeliveryOptimizationTitle;
      case 'targetInstallerPendingTitle':
        return targetInstallerPendingTitle;
      case 'targetSetupLogsTitle':
        return targetSetupLogsTitle;
      case 'targetAppCacheRootTitle':
        return targetAppCacheRootTitle;
      case 'targetAppCacheSelfTitle':
        return targetAppCacheSelfTitle;
      case 'targetDownloadsJunkTitle':
        return targetDownloadsJunkTitle;
      case 'targetObbLeftoversTitle':
        return targetObbLeftoversTitle;
      case 'targetMediaThumbnailsTitle':
        return targetMediaThumbnailsTitle;
      default:
        return key;
    }
  }

  String targetDescription(String key) {
    switch (key) {
      case 'targetAptArchiveDescription':
        return targetAptArchiveDescription;
      case 'targetAptListsDescription':
        return targetAptListsDescription;
      case 'targetJournalDescription':
        return targetJournalDescription;
      case 'targetCrashReportsDescription':
        return targetCrashReportsDescription;
      case 'targetTmpDescription':
        return targetTmpDescription;
      case 'targetHomeCacheDescription':
        return targetHomeCacheDescription;
      case 'targetUserJournalDescription':
        return targetUserJournalDescription;
      case 'targetTrashDescription':
        return targetTrashDescription;
      case 'targetFlatpakCacheDescription':
        return targetFlatpakCacheDescription;
      case 'targetThumbnailsDescription':
        return targetThumbnailsDescription;
      case 'targetUserTempDescription':
        return targetUserTempDescription;
      case 'targetWindowsTempDescription':
        return targetWindowsTempDescription;
      case 'targetEdgeCacheDescription':
        return targetEdgeCacheDescription;
      case 'targetChromeCacheDescription':
        return targetChromeCacheDescription;
      case 'targetFirefoxCacheDescription':
        return targetFirefoxCacheDescription;
      case 'targetEventLogsDescription':
        return targetEventLogsDescription;
      case 'targetErrorReportingDescription':
        return targetErrorReportingDescription;
      case 'targetMinidumpsDescription':
        return targetMinidumpsDescription;
      case 'targetUpdateDownloadDescription':
        return targetUpdateDownloadDescription;
      case 'targetDeliveryOptimizationDescription':
        return targetDeliveryOptimizationDescription;
      case 'targetInstallerPendingDescription':
        return targetInstallerPendingDescription;
      case 'targetSetupLogsDescription':
        return targetSetupLogsDescription;
      case 'targetAppCacheRootDescription':
        return targetAppCacheRootDescription;
      case 'targetAppCacheSelfDescription':
        return targetAppCacheSelfDescription;
      case 'targetDownloadsJunkDescription':
        return targetDownloadsJunkDescription;
      case 'targetObbLeftoversDescription':
        return targetObbLeftoversDescription;
      case 'targetMediaThumbnailsDescription':
        return targetMediaThumbnailsDescription;
      default:
        return '';
    }
  }
}
