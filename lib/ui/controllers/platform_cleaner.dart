import '../../core/safety/safe_delete.dart';
import '../../core/util/logger.dart';
import '../../engine/cleaners/clean_target.dart';
import '../../engine/cleaners/directory_sweeper.dart';
import '../../engine/platform/storage_gateway.dart';

/// The clean targets Android exposes through the storage bridge.
///
/// `dart:io` cannot see MediaStore or the scoped-storage tree on Android 11+,
/// so the Android cleaner cannot be built from directory roots the way the
/// desktop modules are. Instead each target maps onto one [JunkKind] the native
/// side knows how to find, and the id is the contract the localized title
/// lookup keys on.
/// Even the recycle bin gets a grace period. Android keeps trashed files for
/// thirty days and shows them in Files, so an hour costs the user nothing
/// while still refusing to remove something the Gallery is still indexing.
const Duration _trashAge = Duration(hours: 1);

List<CleanTarget> androidStorageTargets() {
  const age = Duration(days: 7);
  const storageRoot = '/storage/emulated/0';
  return <CleanTarget>[
    CleanTarget(
      id: 'android_trashed',
      titleKey: 'androidTrashTitle',
      descriptionKey: 'androidTrashDescription',
      category: CleanCategory.temp,
      roots: <String>[storageRoot],
      minAge: _trashAge,
    ),
    CleanTarget(
      id: 'android_obsolete_installers',
      titleKey: 'androidInstallersTitle',
      descriptionKey: 'androidInstallersDescription',
      category: CleanCategory.temp,
      risk: RiskLevel.moderate,
      roots: <String>['$storageRoot/Download'],
      minAge: Duration(days: 30),
    ),
    CleanTarget(
      id: 'android_partial_downloads',
      titleKey: 'androidPartialDownloadsTitle',
      descriptionKey: 'androidPartialDownloadsDescription',
      category: CleanCategory.temp,
      roots: <String>[storageRoot],
      minAge: age,
    ),
    CleanTarget(
      id: 'android_app_residue',
      titleKey: 'androidAppResidueTitle',
      descriptionKey: 'androidAppResidueDescription',
      category: CleanCategory.junk,
      risk: RiskLevel.moderate,
      roots: <String>['$storageRoot/Android'],
      minAge: Duration(days: 14),
    ),
    CleanTarget(
      id: 'android_screenshots',
      titleKey: 'androidScreenshotsTitle',
      descriptionKey: 'androidScreenshotsDescription',
      category: CleanCategory.junk,
      roots: <String>['$storageRoot/Pictures/Screenshots'],
      minAge: Duration(days: 30),
    ),
    CleanTarget(
      id: 'android_duplicate_media',
      titleKey: 'androidDuplicateMediaTitle',
      descriptionKey: 'androidDuplicateMediaDescription',
      category: CleanCategory.junk,
      roots: <String>[storageRoot],
      minAge: age,
    ),
    CleanTarget(
      id: 'android_empty_folders',
      titleKey: 'androidEmptyFoldersTitle',
      descriptionKey: 'androidEmptyFoldersDescription',
      category: CleanCategory.junk,
      roots: <String>[storageRoot],
      minAge: Duration(days: 30),
    ),
    CleanTarget(
      id: 'android_logs',
      titleKey: 'androidLogsTitle',
      descriptionKey: 'androidLogsDescription',
      category: CleanCategory.logs,
      roots: <String>[storageRoot],
      minAge: age,
    ),
  ];
}

CleanTarget _targetForKind(JunkKind kind) {
  final id = switch (kind) {
    JunkKind.trashed => 'android_trashed',
    JunkKind.obsoleteInstaller => 'android_obsolete_installers',
    JunkKind.partialDownload => 'android_partial_downloads',
    JunkKind.appResidue => 'android_app_residue',
    JunkKind.screenshots => 'android_screenshots',
    JunkKind.duplicateMedia => 'android_duplicate_media',
    JunkKind.emptyFolder => 'android_empty_folders',
    JunkKind.logs => 'android_logs',
  };
  return androidStorageTargets().firstWhere((t) => t.id == id);
}

/// Drives the platform cleaner off the storage bridge.
///
/// It mirrors [DirectorySweeper]'s contract exactly — measure with [scan],
/// act with [clean] — so [CleanerController] can accept either implementation
/// without knowing which platform it is on. There is deliberately no deletion
/// logic of its own: every removal is delegated to the native side, and the
/// bridge is asked for permission first, because a number it may not act on is
/// worse than showing nothing.
class StorageCleaner {
  const StorageCleaner(this.gateway);

  final StorageGateway gateway;

  Future<List<CleanFinding>> scan() async {
    if (!(await gateway.capabilities()).canReadAnything) {
      log.info('storage cleaner: the platform bridge cannot see storage yet');
      return const <CleanFinding>[];
    }

    final summary = await gateway.scanJunk();
    final now = DateTime.now();
    final grouped = <JunkKind, List<StorageEntry>>{};
    for (final entry in summary.entries) {
      grouped.putIfAbsent(entry.kind, () => <StorageEntry>[]).add(entry);
    }

    final findings = <CleanFinding>[];
    for (final kind in JunkKind.values) {
      final entries = grouped[kind];
      if (entries == null || entries.isEmpty) continue;

      final target = _targetForKind(kind);
      // The age gate lives here rather than in the native query because it is
      // a safety rule, not a platform fact: a file a running app just wrote is
      // not junk yet even if it matches the pattern.
      final old = entries
          .where((e) => now.difference(e.modified.toUtc()) >= target.minAge)
          .toList();
      if (old.isEmpty) continue;

      findings.add(
        CleanFinding(
          target: target,
          fileCount: old.length,
          totalBytes: old.fold<int>(0, (sum, e) => sum + e.sizeBytes),
          capped: summary.capped,
        ),
      );
    }
    return findings;
  }

  Future<CleanOutcome> clean(
    List<CleanFinding> findings, {
    void Function(int done, int total)? onProgress,
  }) async {
    if (findings.isEmpty) {
      return CleanOutcome(
        cleaned: <String>[],
        skipped: <String>[],
        bytesFreed: 0,
        errors: <String>[],
        failedPaths: <String>[],
      );
    }
    if (!(await gateway.capabilities()).canClean) {
      log.warn('storage cleaner: delete refused — no storage access');
      return CleanOutcome(
        cleaned: const <String>[],
        skipped: <String>[
          for (final f in findings) ...f.samples,
        ],
        bytesFreed: 0,
        errors: const <String>[],
        failedPaths: const <String>[],
      );
    }

    final summary = await gateway.scanJunk();
    final wanted = <String, int>{
      for (final f in findings) f.target.id: f.fileCount,
    };
    final picked = <String>[];
    var planned = 0;
    for (final entry in summary.entries) {
      if (wanted[_targetForKind(entry.kind).id] == null) continue;
      picked.add(entry.id);
      planned++;
      onProgress?.call(picked.length, planned);
    }

    final freed = summary.entries
        .where((e) => wanted[_targetForKind(e.kind).id] != null)
        .fold<int>(0, (sum, e) => sum + e.sizeBytes);
    await gateway.deleteEntries(picked);

    return CleanOutcome(
      cleaned: picked,
      skipped: const <String>[],
      bytesFreed: freed,
      errors: const <String>[],
      failedPaths: const <String>[],
    );
  }
}
