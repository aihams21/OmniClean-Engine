import 'dart:io';

import 'package:flutter/foundation.dart';

import '../../core/safety/protected_paths.dart';
import '../../core/safety/safe_delete.dart';
import '../../core/util/logger.dart';
import '../../engine/duplicates/duplicate_finder.dart';
import '../../engine/platform/storage_gateway.dart';

/// Runs a duplicate hunt. Injected so the controller can be tested without
/// touching a real disk.
typedef DuplicateScanner = Future<List<DuplicateGroup>> Function(
  List<String> roots, {
  CancelToken? cancel,
  void Function(int done, int total, HashPhase phase)? onProgress,
});

/// Coarse state of the duplicates screen.
enum DuplicatesPhase { idle, scanning, done, failed }

/// Drives the duplicates screen: the roots to search, the running SHA-256
/// hunt, the user's per-group decision and the final quarantining.
///
/// Nothing is deleted on the strength of a hash alone: the user must tick a
/// group, the group's oldest copy is always the one that stays, and the rest
/// still pass through [SafeDelete] before they are quarantined.
class DuplicatesController extends ChangeNotifier {
  DuplicatesController({
    required SafeDelete safeDelete,
    DuplicateScanner? scanner,
    List<String>? roots,
    StorageGateway? gateway,
  })  : _safeDelete = safeDelete,
        _gateway = gateway,
        _scanner = scanner ?? _defaultScanner,
        _roots = _normalize(roots ?? defaultRoots());

  /// The whole-library scan, used when the platform can enumerate media for us.
  ///
  /// On Android the media lives in a content provider that `dart:io` cannot
  /// read, so asking the user for a folder was the wrong question: the platform
  /// already knows every file it holds. The three verification passes are the
  /// same ones a disk walk runs, so the answer is exactly as trustworthy.
  static DuplicateScanner mediaScanner(StorageGateway gateway) {
    const finder = DuplicateFinder();
    return (
      List<String> roots, {
      CancelToken? cancel,
      void Function(int done, int total, HashPhase phase)? onProgress,
    }) async {
      final entries = await gateway.mediaFiles();
      onProgress?.call(0, entries.length, HashPhase.walking);
      return finder.scanFiles(
        entries
            .map((StorageEntry e) => DuplicateFile(
                  path: e.path,
                  sizeBytes: e.sizeBytes,
                  modified: e.modified,
                  sha256: '',
                ))
            .toList(growable: false),
        cancel: cancel,
        onProgress: onProgress,
      );
    };
  }

  static DuplicateScanner get _defaultScanner {
    const finder = DuplicateFinder();
    return (
      List<String> roots, {
      CancelToken? cancel,
      void Function(int done, int total, HashPhase phase)? onProgress,
    }) =>
        finder.find(roots: roots, cancel: cancel, onProgress: onProgress);
  }

  /// Search roots that make sense before the user narrows anything down.
  static List<String> defaultRoots() {
    final env = Platform.environment;
    if (Platform.isAndroid) {
      return const <String>[
        '/storage/emulated/0/Download',
        '/storage/emulated/0/Documents',
      ];
    }
    if (Platform.isWindows) {
      final profile = env['USERPROFILE'];
      return profile == null || profile.isEmpty
          ? const <String>[]
          : <String>[profile];
    }
    final home = env['HOME'];
    return home == null || home.isEmpty ? const <String>[] : <String>[home];
  }

  static List<String> _normalize(Iterable<String> raw) {
    final out = <String>[];
    for (final entry in raw) {
      var path = entry.trim();
      while (path.length > 1 && (path.endsWith('/') || path.endsWith('\\'))) {
        path = path.substring(0, path.length - 1);
      }
      if (path.isEmpty || out.contains(path)) continue;
      out.add(path);
    }
    return out;
  }

  final SafeDelete _safeDelete;

  /// The platform bridge, when one exists.
  ///
  /// Its presence is what makes the duplicate finder work with zero setup: the
  /// user never picks a folder, because the platform can hand over the whole
  /// library instead. Its absence is the normal desktop case, where walking the
  /// user's own directories is both possible and the right thing to do.
  final StorageGateway? _gateway;

  final DuplicateScanner _scanner;
  final List<String> _roots;

  /// The directories deletions are allowed inside.
  ///
  /// Normally that is exactly what the user picked. When the platform supplied
  /// the files instead, the roots the user never chose are the directories the
  /// platform reported them from — deriving them keeps the containment gate
  /// switched on rather than quietly switching it off.
  List<String> get _effectiveRoots {
    if (_roots.isNotEmpty) return List<String>.of(_roots);
    if (_gateway == null) return const <String>[];
    final derived = <String>{};
    for (final DuplicateGroup group in _groups) {
      for (final DuplicateFile file in group.files) {
        final segments = ProtectedPaths.normalize(file.path).split('/');
        if (segments.length < 2) continue;
        segments.removeLast();
        final parent = segments.join('/');
        if (parent.isNotEmpty) derived.add(parent);
      }
    }
    return derived.toList(growable: false);
  }

  List<DuplicateGroup> _groups = const <DuplicateGroup>[];
  final Set<String> _selected = <String>{};
  DuplicatesPhase _phase = DuplicatesPhase.idle;
  HashPhase? _hashPhase;
  CancelToken? _token;
  bool _wasCancelled = false;
  int _progressDone = 0;
  int _progressTotal = 0;
  CleanOutcome? _lastOutcome;

  List<String> get roots => List<String>.unmodifiable(_roots);
  List<DuplicateGroup> get groups => _groups;
  DuplicatesPhase get phase => _phase;
  HashPhase? get hashPhase => _hashPhase;
  bool get wasCancelled => _wasCancelled;
  bool get isScanning => _phase == DuplicatesPhase.scanning;
  int get progressDone => _progressDone;
  int get progressTotal => _progressTotal;
  CleanOutcome? get lastOutcome => _lastOutcome;

  Set<String> get selectedPaths => Set<String>.unmodifiable(_selected);
  int get selectedCount => _selected.length;

  /// Bytes that a full clean of the current selection would reclaim.
  int get wastedBytes =>
      _groups.fold<int>(0, (sum, group) => sum + group.wastedBytes);

  /// A platform-backed controller can always scan: there is no folder to
  /// choose first, which is the whole point of the media bridge.
  bool get canScan => (_roots.isNotEmpty || _gateway != null) && !isScanning;
  bool get canDelete => _selected.isNotEmpty && !isScanning;

  void addRoot(String raw) {
    final cleaned = _normalize(<String>[raw]);
    if (cleaned.isEmpty) return;
    final next = _normalize(<String>[..._roots, ...cleaned]);
    if (next.length == _roots.length) return;
    _roots
      ..clear()
      ..addAll(next);
    notifyListeners();
  }

  void removeRoot(String root) {
    if (!_roots.remove(root)) return;
    notifyListeners();
  }

  Future<void> scan() async {
    if (!canScan) return;
    _token?.cancel();
    final token = CancelToken();
    _token = token;
    _wasCancelled = false;
    _lastOutcome = null;
    _selected.clear();
    _groups = const <DuplicateGroup>[];
    _hashPhase = HashPhase.walking;
    _phase = DuplicatesPhase.scanning;
    _progressDone = 0;
    _progressTotal = 0;
    notifyListeners();

    List<DuplicateGroup> found;
    try {
      found = await _scanner(
        List<String>.of(_roots),
        cancel: token,
        onProgress: (done, total, phase) {
          _hashPhase = phase;
          _progressDone = done;
          _progressTotal = total;
          notifyListeners();
        },
      );
    } catch (error) {
      log.error('duplicates: scan failed — $error');
      _phase = DuplicatesPhase.failed;
      _token = null;
      notifyListeners();
      return;
    }

    if (token.isCancelled) {
      _groups = const <DuplicateGroup>[];
      _phase = DuplicatesPhase.idle;
    } else {
      _groups = List<DuplicateGroup>.unmodifiable(found);
      _phase = DuplicatesPhase.done;
    }
    _wasCancelled = token.isCancelled;
    _hashPhase = token.isCancelled ? null : HashPhase.done;
    _progressDone = 0;
    _progressTotal = 0;
    _token = null;
    notifyListeners();
  }

  void cancelScan() => _token?.cancel();

  /// The path a group keeps, or `null` for a group of one.
  String? keptPathFor(String sha) {
    for (final group in _groups) {
      if (group.sha256 == sha) return group.keepSuggestion?.path;
    }
    return null;
  }

  /// Paths that [selectGroup] would delete for [sha] — everything but the copy
  /// that stays.
  List<String> deletablePathsFor(String sha) {
    for (final group in _groups) {
      if (group.sha256 != sha) continue;
      final keep = group.keepSuggestion?.path;
      if (group.files.length < 2 || keep == null) return const <String>[];
      return group.files
          .map((f) => f.path)
          .where((path) => path != keep)
          .toList(growable: false);
    }
    return const <String>[];
  }

  void selectGroup(String sha) {
    final paths = deletablePathsFor(sha);
    if (paths.isEmpty) return;
    final already = paths.every(_selected.contains);
    for (final path in paths) {
      if (already) {
        _selected.remove(path);
      } else {
        _selected.add(path);
      }
    }
    notifyListeners();
  }

  void selectPath(String path) {
    if (_selected.add(path)) notifyListeners();
  }

  void deselectPath(String path) {
    if (_selected.remove(path)) notifyListeners();
  }

  void selectAll() {
    for (final group in _groups) {
      _selected.addAll(deletablePathsFor(group.sha256));
    }
    notifyListeners();
  }

  void selectNone() {
    if (_selected.isEmpty) return;
    _selected.clear();
    notifyListeners();
  }

  /// Quarantines every selected copy. The kept file is never in the list, and
  /// anything outside the declared roots is refused by [SafeDelete].
  Future<CleanOutcome> deleteSelected() async {
    if (_selected.isEmpty) return _emptyOutcome();
    final work = List<String>.of(_selected);
    _progressDone = 0;
    _progressTotal = work.length;
    notifyListeners();

    final outcome = await _safeDelete.quarantineAll(
      work,
      allowedRoots: _effectiveRoots,
      module: 'duplicates',
      onProgress: (done, total) {
        _progressDone = done;
        _progressTotal = total;
        notifyListeners();
      },
    );

    _lastOutcome = outcome;
    _selected.clear();
    _groups = const <DuplicateGroup>[];
    _progressDone = 0;
    _progressTotal = 0;
    _phase = DuplicatesPhase.done;
    notifyListeners();
    return outcome;
  }

  static CleanOutcome _emptyOutcome() => CleanOutcome(
        cleaned: const <String>[],
        skipped: const <String>[],
        bytesFreed: 0,
        errors: const <String>[],
        failedPaths: const <String>[],
      );

  @override
  void dispose() {
    _token?.cancel();
    super.dispose();
  }
}
