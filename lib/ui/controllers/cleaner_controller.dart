import 'dart:async';
import 'dart:io' show Platform;

import 'package:flutter/foundation.dart';

import '../../core/safety/safe_delete.dart';
import '../../core/util/logger.dart';
import '../../engine/cleaners/clean_target.dart';
import '../../engine/cleaners/directory_sweeper.dart';
import '../../engine/cleaners/linux_cleaner.dart';
import '../../engine/cleaners/windows_cleaner.dart';
import '../../engine/cleaners/android_cleaner.dart';
import '../../engine/duplicates/duplicate_finder.dart' show CancelToken;

/// Injection seam for the scan half of a module, so the controller can be
/// driven by a real [DirectorySweeper] or by a stub in tests.
typedef ModuleScanner = Future<List<CleanFinding>> Function(
  List<CleanTarget> targets, {
  CancelToken? cancel,
  void Function(CleanTarget target, SweepResult result)? onTarget,
});

/// Injection seam for the clean half of a single module.
typedef ModuleCleaner = Future<CleanOutcome> Function(
  CleanTarget target, {
  void Function(int done, int total)? onProgress,
});

/// One row in the cleaner list: the declared target plus whatever the last
/// scan measured for it.
@immutable
class ModuleStatus {
  const ModuleStatus({
    required this.target,
    this.finding,
    this.selected = false,
    this.cleaned = false,
    this.failed = false,
  });

  ModuleStatus copyWith({
    CleanFinding? finding,
    bool? selected,
    bool? cleaned,
    bool? failed,
  }) =>
      ModuleStatus(
        target: target,
        finding: finding ?? this.finding,
        selected: selected ?? this.selected,
        cleaned: cleaned ?? this.cleaned,
        failed: failed ?? this.failed,
      );

  final CleanTarget target;
  final CleanFinding? finding;
  final bool selected;
  final bool cleaned;
  final bool failed;

  int get bytes => finding?.totalBytes ?? 0;
  int get files => finding?.fileCount ?? 0;
  bool get isEmpty => bytes == 0 || files == 0;

  /// Pre-ticked after a scan so the common case is one tap. Elevated work is
  /// never auto-selected: it needs elevated rights and a deliberate opt-in.
  /// Moderate work *is* ticked, but [CleanerController.selectedNeedsConfirmation]
  /// forces the UI to ask before it runs.
  bool get autoSelectable => target.risk != RiskLevel.elevated && !isEmpty;

  @override
  bool operator ==(Object other) =>
      other is ModuleStatus &&
      other.target.id == target.id &&
      other.finding == finding &&
      other.selected == selected &&
      other.cleaned == cleaned &&
      other.failed == failed;

  @override
  int get hashCode => Object.hash(target.id, finding, selected, cleaned, failed);
}

/// Drives the whole cleaner screen: listing targets, scanning them, holding the
/// user's selection and running the selected modules through [SafeDelete].
///
/// The controller owns *no* filesystem logic. Every scan and every deletion is
/// delegated to the injected scanner/cleaner, and in production those are thin
/// wrappers over [DirectorySweeper].
class CleanerController extends ChangeNotifier {
  CleanerController({
    required this.targets,
    required this.safeDelete,
    ModuleScanner? scanner,
    ModuleCleaner? cleaner,
  })  : _scan = scanner ?? _defaultScanner,
        _clean = cleaner ?? _defaultCleaner(safeDelete),
        _modules = targets.targets
            .map((t) => ModuleStatus(target: t))
            .toList(growable: false);

  /// Builds a controller wired to the real sweeper and the target set that
  /// matches the host platform.
  factory CleanerController.forPlatform({
    required SafeDelete safeDelete,
    CleanTargetSet? targets,
  }) =>
      CleanerController(
        targets: targets ?? targetsForPlatform(),
        safeDelete: safeDelete,
      );

  static CleanTargetSet targetsForPlatform() {
    if (Platform.isAndroid) {
      return AndroidCleaner.targets;
    }
    if (Platform.isWindows) {
      return WindowsCleaner.targets;
    }
    return LinuxCleaner.targets;
  }

  final CleanTargetSet targets;
  final SafeDelete safeDelete;
  final ModuleScanner _scan;
  final ModuleCleaner _clean;

  static const DirectorySweeper _sweeper = DirectorySweeper();

  List<ModuleStatus> _modules;
  CleanPhase _phase = CleanPhase.idle;
  bool _hasScanned = false;
  bool _wasCancelled = false;
  CancelToken? _token;
  String? _activeModuleId;
  int _progressDone = 0;
  int _progressTotal = 0;
  int _bytesFreed = 0;
  int _filesCleaned = 0;
  int _filesSkipped = 0;
  List<String> _failedModules = const <String>[];

  List<ModuleStatus> get modules => _modules;
  CleanPhase get phase => _phase;
  bool get hasScanned => _hasScanned;
  bool get wasCancelled => _wasCancelled;
  bool get isBusy => _phase == CleanPhase.scanning || _phase == CleanPhase.cleaning;
  String? get activeModuleId => _activeModuleId;
  int get progressDone => _progressDone;
  int get progressTotal => _progressTotal;
  int get bytesFreed => _bytesFreed;
  int get filesCleaned => _filesCleaned;
  int get filesSkipped => _filesSkipped;
  List<String> get failedModules => _failedModules;

  Iterable<ModuleStatus> get _selected =>
      _modules.where((m) => m.selected);

  int get totalBytes => _modules.fold<int>(0, (sum, m) => sum + m.bytes);
  int get totalFiles => _modules.fold<int>(0, (sum, m) => sum + m.files);
  int get selectedBytes => _selected.fold<int>(0, (sum, m) => sum + m.bytes);
  int get selectedFiles => _selected.fold<int>(0, (sum, m) => sum + m.files);
  bool get selectedNeedsPrivilege =>
      _selected.any((m) => m.target.requiresPrivilege);
  bool get selectedNeedsConfirmation =>
      _selected.any((m) => m.target.risk.needsConfirmation);

  /// True only when there is something real to reclaim and nothing is running.
  bool get canClean => !isBusy && selectedBytes > 0 && _modules.isNotEmpty;

  /// Everything a first-time user can clear without reading the manual.
  int get safeBytes => _modules
      .where((m) => !m.target.risk.needsConfirmation)
      .fold<int>(0, (sum, m) => sum + m.bytes);

  void _seed() {
    if (_modules.isEmpty) {
      _modules = targets.targets
          .map((t) => ModuleStatus(target: t))
          .toList(growable: false);
    }
  }

  /// Measures every declared target. Never throws: a failure lands in
  /// [CleanPhase.failed] with the previous findings left intact.
  Future<void> scan({CancelToken? cancel}) async {
    _seed();
    _token?.cancel();
    final token = cancel ?? CancelToken();
    _token = token;
    _wasCancelled = false;
    _activeModuleId = null;
    _progressDone = 0;
    _progressTotal = _modules.length;
    _phase = CleanPhase.scanning;
    notifyListeners();

    List<CleanFinding> findings;
    try {
      findings = await _scan(
        targets.targets,
        cancel: token,
        onTarget: (target, result) {
          _applyFinding(target, result);
          notifyListeners();
        },
      );
    } catch (error) {
      log.error('cleaner: scan failed — $error');
      _wasCancelled = token.isCancelled;
      _phase = CleanPhase.failed;
      _progressDone = _progressTotal;
      _activeModuleId = null;
      _token = null;
      notifyListeners();
      return;
    }

    _wasCancelled = token.isCancelled;
    if (_wasCancelled) {
      // A partial walk produced partial numbers. Keeping them would let the user
      // act on a "reclaimable" figure that is missing whole subtrees, so the
      // cancelled scan is discarded rather than shown.
      _modules = <ModuleStatus>[
        for (final m in _modules) m.copyWith(finding: null, selected: false),
      ];
    } else {
      _modules = <ModuleStatus>[
        for (final status in _modules)
          if (findings.any((f) => f.target.id == status.target.id))
            _replaceFinding(
                status, findings.firstWhere((f) => f.target.id == status.target.id))
          else
            status,
      ];
    }

    _hasScanned = !_wasCancelled;
    _phase = CleanPhase.idle;
    _progressDone = _progressTotal;
    _activeModuleId = null;
    _token = null;
    notifyListeners();
  }

  /// Cancels the in-flight scan, if any.
  void cancelScan() {
    _token?.cancel();
  }

  void toggle(String id) {
    _seed();
    final index = _modules.indexWhere((m) => m.target.id == id);
    if (index < 0) return;
    _modules = List<ModuleStatus>.of(_modules)
      ..[index] = _modules[index].copyWith(
        selected: !_modules[index].selected,
      );
    notifyListeners();
  }

  void selectAll() {
    _seed();
    _modules = <ModuleStatus>[
      for (final m in _modules) m.copyWith(selected: true),
    ];
    notifyListeners();
  }

  void selectNone() {
    _seed();
    _modules = <ModuleStatus>[
      for (final m in _modules) m.copyWith(selected: false),
    ];
    notifyListeners();
  }

  /// Clears every result accumulated by the last [cleanSelected].
  void resetResults() {
    _bytesFreed = 0;
    _filesCleaned = 0;
    _filesSkipped = 0;
    _failedModules = const <String>[];
    _progressDone = 0;
    _progressTotal = 0;
    notifyListeners();
  }

  /// Quarantines everything the user selected.
  ///
  /// A module that throws is recorded in [failedModules] and the run continues:
  /// one locked-down directory must not strand the rest of the cleanup.
  Future<void> cleanSelected() async {
    _seed();
    if (isBusy) return;
    final work = _selected.toList(growable: false);
    if (work.isEmpty) return;

    _bytesFreed = 0;
    _filesCleaned = 0;
    _filesSkipped = 0;
    _failedModules = <String>[];
    _phase = CleanPhase.cleaning;

    for (final status in work) {
      _activeModuleId = status.target.id;
      _progressDone = 0;
      _progressTotal = status.files;
      notifyListeners();

      CleanOutcome outcome;
      try {
        outcome = await _clean(
          status.target,
          onProgress: (done, total) {
            _progressDone = done;
            if (total > 0) _progressTotal = total;
            notifyListeners();
          },
        );
      } catch (error) {
        log.error('cleaner: ${status.target.id} failed — $error');
        _failedModules = <String>[..._failedModules, status.target.id];
        _modules = _with(status.target.id, (m) => m.copyWith(failed: true));
        continue;
      }

      _bytesFreed += outcome.bytesFreed;
      _filesCleaned += outcome.cleaned.length;
      _filesSkipped += outcome.skipped.length;
      _modules = _with(
        status.target.id,
        (m) => m.copyWith(cleaned: outcome.cleaned.isNotEmpty, failed: false),
      );
      if (outcome.bytesFreed > 0) {
        _modules = _with(
          status.target.id,
          (m) => m.copyWith(
            finding: CleanFinding(
              target: status.target,
              fileCount: 0,
              totalBytes: 0,
            ),
            selected: false,
          ),
        );
      }
    }

    _activeModuleId = null;
    _progressDone = _progressTotal;
    _phase = CleanPhase.done;
    notifyListeners();
  }

  List<ModuleStatus> _with(
    String id,
    ModuleStatus Function(ModuleStatus) transform,
  ) =>
      <ModuleStatus>[
        for (final m in _modules) m.target.id == id ? transform(m) : m,
      ];

  ModuleStatus _replaceFinding(ModuleStatus status, CleanFinding finding) {
    final next = status.copyWith(
      finding: finding,
      cleaned: false,
      failed: false,
    );
    return next.copyWith(
      selected: !finding.isEmpty && next.autoSelectable,
    );
  }

  void _applyFinding(CleanTarget target, SweepResult result) {
    _modules = _with(
      target.id,
      (m) => m.copyWith(
        finding: CleanFinding(
          target: target,
          fileCount: result.selectableFiles,
          totalBytes: result.selectableBytes,
          capped: result.capped,
        ),
      ),
    );
  }

  static Future<List<CleanFinding>> _defaultScanner(
    List<CleanTarget> targets, {
    CancelToken? cancel,
    void Function(CleanTarget target, SweepResult result)? onTarget,
  }) =>
      _sweeper.scanAll(targets, cancel: cancel, onTarget: onTarget);

  static ModuleCleaner _defaultCleaner(SafeDelete safeDelete) {
    return (target, {onProgress}) => _sweeper.clean(
          target.roots,
          _sweeper.optionsFor(target),
          safeDelete: safeDelete,
          allowedRoots: target.roots,
          module: target.id,
          onProgress: onProgress,
        );
  }

  @override
  void dispose() {
    _token?.cancel();
    super.dispose();
  }
}
