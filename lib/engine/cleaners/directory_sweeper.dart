import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:omni_clean_engine/core/safety/safe_delete.dart';
import 'package:omni_clean_engine/core/util/logger.dart';
import 'package:omni_clean_engine/engine/cleaners/clean_target.dart';
import 'package:omni_clean_engine/engine/duplicates/duplicate_finder.dart'
    show CancelToken;

/// Declarative filter for one directory sweep.
///
/// Every field is a const-friendly literal so a module can declare its whole
/// policy inline and the test suite can build it with `const`.
@immutable
class SweepOptions {
  const SweepOptions({
    this.minAge = Duration.zero,
    this.includeHidden = true,
    this.excludeDirectories = const <String>{},
    this.excludePaths = const <String>{},
    this.extensions = const <String>{},
    this.excludeExtensions = const <String>{},
    this.maxDepth = 16,
    this.maxBytes = 0,
    this.maxSamples = 5,
  });

  /// Files touched more recently than this are counted but never selected.
  final Duration minAge;
  final bool includeHidden;

  /// Directory *names* (not paths) to prune wherever they appear.
  final Set<String> excludeDirectories;

  /// Absolute paths to skip outright, e.g. the quarantine vault itself.
  final Set<String> excludePaths;

  /// When non-empty, only these extensions are considered.
  final Set<String> extensions;

  /// Rejected even when listed in [extensions].
  final Set<String> excludeExtensions;

  final int maxDepth;

  /// When > 0, the sweep selects the largest files first until this budget is
  /// exhausted, so one enormous log can never eat the whole allowance.
  final int maxBytes;

  final int maxSamples;
}

/// One file the walk encountered.
class SweepSample {
  SweepSample(this.path, this.bytes, this.modified);

  final String path;
  final int bytes;
  final DateTime modified;

  String get name => path.split('/').last;
}

/// What one [DirectorySweeper.measure] pass learned.
class SweepResult {
  SweepResult({
    required this.fileCount,
    required this.bytes,
    required this.scannedDirectories,
    required this.symlinksSkipped,
    required this.skippedDirectories,
    required this.selectedSamples,
    required this.selectableBytes,
    required this.agedFiles,
    required this.agedBytes,
    required this.samples,
    required this.capped,
    required this.cancelled,
  });

  final int fileCount;
  final int bytes;
  final int scannedDirectories;
  final int symlinksSkipped;
  final int skippedDirectories;

  /// Everything that survived every *content* filter, largest first — the exact
  /// list that will be handed to the quarantine, in this exact order.
  final List<SweepSample> selectedSamples;

  /// Sum of [selectedPaths] before the byte cap was applied.
  final int selectableBytes;

  /// How much of [selectableBytes] is actually old enough to be reclaimed right
  /// now. The remainder is real junk that a live process may still hold open, so
  /// it will be reported as skipped rather than deleted.
  final int agedFiles;
  final int agedBytes;

  final List<SweepSample> samples;
  final bool capped;
  final bool cancelled;

  /// Bytes a running app is probably still using.
  int get heldBackBytes => selectableBytes - agedBytes;
  int get heldBackFiles => selectableFiles - agedFiles;

  int get selectableFiles => selectedSamples.length;

  List<String> get selectedPaths =>
      selectedSamples.map((s) => s.path).toList(growable: false);

  /// Basenames of what would be reclaimed, largest first — for tests and logs.
  List<String> get selected =>
      selectedSamples.map((s) => s.name).toList(growable: false);
}

/// Walks declared roots, measures what is reclaimable, and hands the survivors
/// to `SafeDelete`.
///
/// It deliberately has no deletion logic of its own: it can only *propose*
/// paths, and `SafeDelete` re-validates every single one of them independently.
/// A bug in the walk therefore cannot turn into a deletion outside the roots.
class DirectorySweeper {
  const DirectorySweeper();

  SweepOptions optionsFor(CleanTarget target) => SweepOptions(
        minAge: target.minAge,
        includeHidden: target.includeHidden,
        excludeDirectories: target.excludeDirectories,
        extensions: target.extensions,
        excludeExtensions: target.excludeExtensions,
        maxDepth: target.maxDepth,
        maxBytes: target.capBytes,
      );

  /// Counts what a sweep would find. Never mutates the filesystem.
  Future<SweepResult> measure(
    List<String> roots,
    SweepOptions options, {
    DateTime Function()? clock,
    CancelToken? cancel,
    void Function(SweepSample sample)? onFile,
  }) async {
    final now = (clock ?? DateTime.now)().toUtc();
    final skipped = <String>[...options.excludePaths];
    var fileCount = 0;
    var bytes = 0;
    var scannedDirectories = 0;
    var symlinksSkipped = 0;
    var skippedDirectories = 0;
    var cancelled = false;
    final all = <SweepSample>[];

    for (final root in roots) {
      if (cancel?.isCancelled ?? false) {
        cancelled = true;
        break;
      }
      final normalized = _normalize(root);
      final type = FileSystemEntity.typeSync(normalized, followLinks: false);
      if (type == FileSystemEntityType.notFound) {
        log.fine('sweep: root not found $normalized');
        continue;
      }
      if (type == FileSystemEntityType.link) {
        symlinksSkipped++;
        continue;
      }
      if (type == FileSystemEntityType.file) {
        final sample = _sampleOf(normalized);
        if (sample != null && _acceptsFile(sample, options, skipped)) {
          all.add(sample);
          fileCount++;
          bytes += sample.bytes;
          onFile?.call(sample);
        }
        continue;
      }
      await _walk(
        Directory(normalized),
        0,
        options,
        now,
        skipped,
        (sample) {
          all.add(sample);
          fileCount++;
          bytes += sample.bytes;
          onFile?.call(sample);
        },
        (dir) => scannedDirectories++,
        (link) => symlinksSkipped++,
        (dir) => skippedDirectories++,
        () => cancel?.isCancelled ?? false,
        () => cancelled = true,
      );
      if (cancelled) break;
    }

    final selectable = all.toList()..sort(_bySizeThenPath);

    // `minAge` stays a safety decision and is left to SafeDelete to enforce;
    // the sweep only reports how much of what it found is old enough today, so
    // the UI can say "X reclaimable now, Y held back by a running app".
    final aged = selectable
        .where((s) =>
            options.minAge == Duration.zero ||
            now.difference(s.modified.toUtc()) >= options.minAge)
        .toList();

    var capped = false;
    final selected = <SweepSample>[];
    var budget = options.maxBytes;
    for (final sample in selectable) {
      if (options.maxBytes > 0) {
        if (budget <= 0) {
          capped = true;
          break;
        }
        // The budget is strict: a file that does not fit is left alone. Half a
        // file is not a reclaim, so a file larger than the whole budget is
        // skipped and the smaller ones behind it are still taken.
        if (sample.bytes > budget) {
          capped = true;
          continue;
        }
        budget -= sample.bytes;
      }
      selected.add(sample);
    }

    final samples = all.toList()..sort(_bySizeThenPath);
    return SweepResult(
      fileCount: fileCount,
      bytes: bytes,
      scannedDirectories: scannedDirectories,
      symlinksSkipped: symlinksSkipped,
      skippedDirectories: skippedDirectories,
      selectedSamples: selected,
      selectableBytes: selectable.fold(0, (sum, s) => sum + s.bytes),
      agedFiles: aged.length,
      agedBytes: aged.fold(0, (sum, s) => sum + s.bytes),
      samples: samples.take(options.maxSamples).toList(growable: false),
      capped: capped,
      cancelled: cancelled,
    );
  }

  /// Sweeps and then quarantines, reporting progress as it goes.
  Future<CleanOutcome> clean(
    List<String> roots,
    SweepOptions options, {
    required SafeDelete safeDelete,
    required List<String> allowedRoots,
    required String module,
    DateTime Function()? clock,
    CancelToken? cancel,
    void Function(int done, int total)? onProgress,
  }) async {
    final measured = await measure(
      roots,
      options,
      clock: clock,
      cancel: cancel,
    );

    if (measured.selectedPaths.isEmpty) {
      return CleanOutcome(
        cleaned: const <String>[],
        skipped: const <String>[],
        bytesFreed: 0,
        errors: const <String>[],
        failedPaths: const <String>[],
      );
    }

    return safeDelete.quarantineAll(
      measured.selectedPaths,
      allowedRoots: allowedRoots,
      module: module,
      minAge: options.minAge,
      onProgress: onProgress,
    );
  }

  /// Scans every target in a module, de-duplicating files that more than one
  /// target claims so the headline "reclaimable" number is never inflated.
  Future<List<CleanFinding>> scanAll(
    List<CleanTarget> targets, {
    DateTime Function()? clock,
    CancelToken? cancel,
    void Function(CleanTarget target, SweepResult result)? onTarget,
  }) async {
    final findings = <CleanFinding>[];
    final claimed = <String>{};
    final now = (clock ?? DateTime.now)();

    for (final target in targets) {
      if (cancel?.isCancelled ?? false) break;
      final result = await measure(
        target.roots,
        optionsFor(target),
        clock: () => now,
        cancel: cancel,
      );
      onTarget?.call(target, result);

      final fresh =
          result.selectedSamples.where((s) => claimed.add(s.path)).toList();
      if (fresh.isEmpty) continue;

      findings.add(CleanFinding(
        target: target,
        fileCount: fresh.length,
        totalBytes: fresh.fold(0, (sum, s) => sum + s.bytes),
        samples: fresh.take(3).map((s) => s.path).toList(growable: false),
        capped: result.capped,
      ));
    }

    findings.sort((a, b) => b.totalBytes.compareTo(a.totalBytes));
    return findings;
  }

  Future<void> _walk(
    Directory dir,
    int depth,
    SweepOptions options,
    DateTime now,
    List<String> skipped,
    void Function(SweepSample) onFile,
    void Function(Directory) onDir,
    void Function(Link) onLink,
    void Function(Directory) onSkip,
    bool Function() isCancelled,
    void Function() setCancelled,
  ) async {
    if (isCancelled()) {
      setCancelled();
      return;
    }
    if (depth > options.maxDepth) return;
    onDir(dir);

    final children = <FileSystemEntity>[];
    try {
      children.addAll(dir.listSync(followLinks: false));
    } on FileSystemException catch (e) {
      log.warn(
          'sweep: cannot list ${dir.path} — ${e.osError?.message ?? e.message}');
      return;
    }

    // Deterministic order keeps selection reproducible across runs.
    children.sort((a, b) => a.path.compareTo(b.path));

    for (final child in children) {
      if (isCancelled()) {
        setCancelled();
        return;
      }
      final name = child.path.split('/').last;

      switch (FileSystemEntity.typeSync(child.path, followLinks: false)) {
        case FileSystemEntityType.link:
          onLink(child as Link);
          continue;
        case FileSystemEntityType.directory:
          final sub = child as Directory;
          if (_skipDirectory(name, sub.path, depth, options, skipped)) {
            onSkip(sub);
            continue;
          }
          await _walk(
            sub,
            depth + 1,
            options,
            now,
            skipped,
            onFile,
            onDir,
            onLink,
            onSkip,
            isCancelled,
            setCancelled,
          );
          continue;
        case FileSystemEntityType.file:
          final sample = _sampleOf(child.path);
          if (sample == null) continue;
          if (!_acceptsFile(sample, options, skipped)) continue;
          onFile(sample);
          continue;
        case FileSystemEntityType.notFound:
          continue;
      }
    }
  }

  bool _skipDirectory(
    String name,
    String path,
    int depth,
    SweepOptions options,
    List<String> skipped,
  ) {
    if (!options.includeHidden && name.startsWith('.')) return true;
    if (options.excludeDirectories
        .any((d) => d.toLowerCase() == name.toLowerCase())) {
      skipped.add(path);
      return true;
    }
    if (skipped.contains(path)) return true;
    return depth + 1 > options.maxDepth;
  }

  bool _acceptsFile(
    SweepSample sample,
    SweepOptions options,
    List<String> skipped,
  ) {
    final name = sample.name;
    if (!options.includeHidden && name.startsWith('.')) return false;
    if (skipped.contains(sample.path)) return false;
    final dot = name.lastIndexOf('.');
    final ext = dot <= 0 ? '' : name.substring(dot).toLowerCase();
    if (options.extensions.isNotEmpty && !options.extensions.contains(ext)) {
      return false;
    }
    if (options.excludeExtensions.contains(ext)) return false;
    return true;
  }

  SweepSample? _sampleOf(String path) {
    try {
      final stat = File(path).statSync();
      return SweepSample(path, stat.size, stat.modified);
    } on FileSystemException catch (e) {
      log.fine('sweep: cannot stat $path — ${e.osError?.message ?? e.message}');
      return null;
    }
  }

  static int _bySizeThenPath(SweepSample a, SweepSample b) {
    final bySize = b.bytes.compareTo(a.bytes);
    return bySize != 0 ? bySize : a.path.compareTo(b.path);
  }

  static String _normalize(String raw) {
    var p = raw.replaceAll('\\', '/');
    while (p.length > 1 && p.endsWith('/')) {
      p = p.substring(0, p.length - 1);
    }
    return p;
  }
}
