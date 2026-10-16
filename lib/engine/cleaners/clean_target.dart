import 'package:flutter/foundation.dart';

/// Coarse grouping used by the UI to colour and order modules.
enum CleanCategory {
  packageCache,
  temp,
  logs,
  browser,
  updates,
  dumps,
  memory,
  junk,
  downloads,
  appCache,
}

/// How much damage a mistake here would do. The UI refuses to auto-select
/// [elevated] targets and always shows them last.
enum RiskLevel {
  safe,
  moderate,
  elevated;

  bool get needsConfirmation => this != RiskLevel.safe;
}

/// Everything a cleaner module needs to know about one reclaimable location.
///
/// A target is pure declarative data on purpose: the sweeping logic lives in
/// [DirectorySweeper] and the destruction logic lives in `SafeDelete`, so a
/// module author cannot accidentally invent a third, unsafe way to delete.
@immutable
class CleanTarget {
  const CleanTarget({
    required this.id,
    required this.titleKey,
    required this.descriptionKey,
    required this.category,
    this.risk = RiskLevel.safe,
    this.requiresPrivilege = false,
    this.roots = const <String>[],
    this.minAge = const Duration(hours: 1),
    this.includeHidden = true,
    this.excludeDirectories = const <String>{},
    this.extensions = const <String>{},
    this.excludeExtensions = const <String>{},
    this.maxDepth = 16,
    this.capBytes = 0,
  });

  final String id;
  final String titleKey;
  final String descriptionKey;
  final CleanCategory category;
  final RiskLevel risk;
  final bool requiresPrivilege;
  final List<String> roots;
  final Duration minAge;
  final bool includeHidden;
  final Set<String> excludeDirectories;
  final Set<String> extensions;
  final Set<String> excludeExtensions;
  final int maxDepth;

  /// Hard ceiling on how much this target may reclaim in one run; 0 = no cap.
  final int capBytes;

  bool get isCapped => capBytes > 0;
  int? get maxBytes => isCapped ? capBytes : null;

  bool get hasRoots => roots.isNotEmpty;

  @override
  String toString() => 'CleanTarget($id, ${roots.length} roots, $risk)';
}

/// A module's target list, guarded against the copy-paste bug that produces two
/// entries fighting over the same directory and double-counting the total.
class CleanTargetSet {
  CleanTargetSet(List<CleanTarget> targets)
      : targets = List<CleanTarget>.unmodifiable(targets) {
    final seen = <String>{};
    for (final t in this.targets) {
      if (!seen.add(t.id)) {
        throw ArgumentError('duplicate CleanTarget id: ${t.id}');
      }
    }
  }

  final List<CleanTarget> targets;

  Iterable<CleanTarget> byRisk(RiskLevel risk) =>
      targets.where((t) => t.risk == risk);

  int get count => targets.length;
}

/// What a scan found inside one target.
@immutable
class CleanFinding {
  const CleanFinding({
    required this.target,
    required this.fileCount,
    required this.totalBytes,
    this.samples = const <String>[],
    this.capped = false,
  });

  final CleanTarget target;
  final int fileCount;
  final int totalBytes;
  final List<String> samples;
  final bool capped;

  bool get isEmpty => fileCount == 0 || totalBytes == 0;
}

extension CleanFindingListX on List<CleanFinding> {
  int get totalBytes =>
      fold<int>(0, (sum, f) => sum + f.totalBytes);
  int get totalFiles => fold<int>(0, (sum, f) => sum + f.fileCount);
}

/// Immutable result of one scan/clean pass over a module.
@immutable
class ScanReport {
  const ScanReport({
    required this.findings,
    this.cancelled = false,
    this.elapsed = Duration.zero,
  });

  final List<CleanFinding> findings;
  final bool cancelled;
  final Duration elapsed;

  int get totalBytes => findings.totalBytes;
  int get totalFiles => findings.totalFiles;
  bool get isEmpty => findings.isEmpty;
  bool get isNotEmpty => findings.isNotEmpty;

  Iterable<CleanFinding> ofCategory(CleanCategory category) =>
      findings.where((f) => f.target.category == category);
}

/// The coarse lifecycle every screen binds to.
enum CleanPhase { idle, scanning, cleaning, done, failed }