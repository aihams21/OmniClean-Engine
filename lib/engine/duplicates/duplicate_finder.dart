import 'dart:io';
import 'dart:isolate';

import 'package:path/path.dart' as p;

import '../../core/util/logger.dart';
import 'hasher.dart';

/// Cooperative cancellation shared with the UI's "Stop" button.
class CancelToken {
  bool _cancelled = false;

  bool get isCancelled => _cancelled;

  void cancel() => _cancelled = true;
}

/// One file participating in a duplicate group.
class DuplicateFile {
  DuplicateFile({
    required this.path,
    required this.sizeBytes,
    required this.modified,
    required this.sha256,
  });

  final String path;
  final int sizeBytes;
  final DateTime modified;
  final String sha256;

  String get name => p.basename(path);
}

/// A set of byte-identical files.
class DuplicateGroup {
  DuplicateGroup({
    required this.sha256,
    required this.sizeBytes,
    required this.files,
  });

  final String sha256;
  final int sizeBytes;
  final List<DuplicateFile> files;

  /// Bytes recoverable while keeping exactly one copy.
  int get wastedBytes => sizeBytes * (files.length - 1);

  /// The file OmniClean proposes to keep: the oldest one, because the newest
  /// is the one most likely mid-edit and the oldest is the one most likely
  /// already backed up somewhere else.
  DuplicateFile? get keepSuggestion {
    if (files.length < 2) return null;
    final sorted = [...files]..sort((a, b) => a.modified.compareTo(b.modified));
    return sorted.first;
  }
}

/// Hashing stages, reported so the UI can show *why* a scan takes time.
enum HashPhase { walking, preFiltering, hashing, done }

/// Three-pass duplicate finder.
///
/// 1. **Size** — bucket by byte length, discard every size that appears once.
///    ~99% of a typical tree dies here without opening a single file.
/// 2. **Partial hash** — head+tail SHA-256 inside a size bucket.
/// 3. **Full SHA-256** — only for survivors.
///
/// Stages 2 and 3 fan out over isolates, so a multi-core machine does the
/// work in parallel and the UI thread never blocks.
class DuplicateFinder {
  const DuplicateFinder({this.isolateBudget = 0});

  /// 0 means "auto" (`cores - 1`, clamped to 1..8).
  final int isolateBudget;

  int get _budget {
    if (isolateBudget > 0) return isolateBudget;
    final cores = Platform.numberOfProcessors;
    return (cores - 1).clamp(1, 8);
  }

  Future<List<DuplicateGroup>> find({
    required List<String> roots,
    int minSizeBytes = 4 * 1024,
    int? maxFiles,
    Set<String>? extensions,
    int partialWindow = 64 * 1024,
    CancelToken? cancel,
    void Function(int done, int total, HashPhase phase)? onProgress,
  }) async {
    final total = <_Candidate>[];

    // ---- Stage 1: walk ----------------------------------------------------
    for (final root in roots) {
      if (cancel?.isCancelled ?? false) return const [];
      await _walk(root, (c) => total.add(c), extensions);
    }
    if (cancel?.isCancelled ?? false) return const [];

    final bySize = <int, List<_Candidate>>{};
    for (final c in total) {
      if (c.size < minSizeBytes) continue;
      bySize.putIfAbsent(c.size, () => []).add(c);
    }

    var capped = bySize.values.expand((e) => e).toList();
    if (maxFiles != null && capped.length > maxFiles) {
      // Keep the largest files: they are the ones that actually free space.
      capped.sort((a, b) => b.size.compareTo(a.size));
      final sizes = capped.take(maxFiles).map((c) => c.size).toSet();
      bySize.removeWhere((s, _) => !sizes.contains(s));
    }

    var survivors = bySize.values.where((l) => l.length > 1).expand((l) => l).toList();
    if (survivors.length < 2) return const [];
    onProgress?.call(0, survivors.length, HashPhase.preFiltering);

    // ---- Stage 2: partial hash -------------------------------------------
    final partialJobs = survivors
        .map((c) => _HashJob(c.path, partialWindow, c.size))
        .toList(growable: false);
    final partials = await _mapHashes(partialJobs, cancel);
    if (cancel?.isCancelled ?? false) return const [];

    final byPartial = <String, List<_Candidate>>{};
    for (var i = 0; i < survivors.length; i++) {
      byPartial.putIfAbsent(partials[i], () => []).add(survivors[i]);
    }
    survivors = byPartial.values.where((l) => l.length > 1).expand((l) => l).toList();
    if (survivors.length < 2) {
      onProgress?.call(1, 1, HashPhase.done);
      return const [];
    }

    // ---- Stage 3: full SHA-256 -------------------------------------------
    onProgress?.call(0, survivors.length, HashPhase.hashing);
    final fullJobs = survivors
        .map((c) => _HashJob(c.path, 0, c.size))
        .toList(growable: false);
    final full = await _mapHashes(fullJobs, cancel);
    if (cancel?.isCancelled ?? false) return const [];

    final byHash = <String, List<DuplicateFile>>{};
    final sizeOf = <String, int>{};
    for (var i = 0; i < survivors.length; i++) {
      final c = survivors[i];
      byHash.putIfAbsent(full[i], () => []).add(DuplicateFile(
            path: c.path,
            sizeBytes: c.size,
            modified: c.modified,
            sha256: full[i],
          ));
      sizeOf[full[i]] = c.size;
    }

    final groups = <DuplicateGroup>[];
    byHash.forEach((hash, files) {
      if (files.length < 2) return;
      groups.add(DuplicateGroup(
        sha256: hash,
        sizeBytes: sizeOf[hash] ?? files.first.sizeBytes,
        files: files,
      ));
    });

    groups.sort((a, b) => b.wastedBytes.compareTo(a.wastedBytes));
    onProgress?.call(survivors.length, survivors.length, HashPhase.done);
    log.info('duplicate scan: ${groups.length} groups from ${roots.length} roots');
    return groups;
  }

  /// Depth-first walk that never follows symlinks (a loop would otherwise hang
  /// the scan) and never descends into the deny-list.
  Future<void> _walk(
    String root,
    void Function(_Candidate) onFile,
    Set<String>? extensions,
  ) async {
    if (!Directory(root).existsSync()) return;

    Future<void> descend(Directory dir, int depth) async {
      if (depth > 32) return;
      List<FileSystemEntity> entries;
      try {
        entries = dir.listSync(followLinks: false);
      } on FileSystemException {
        return;
      }
      for (final entity in entries) {
        final type = FileSystemEntity.typeSync(entity.path, followLinks: false);
        if (type == FileSystemEntityType.directory) {
          await descend(Directory(entity.path), depth + 1);
        } else if (type == FileSystemEntityType.file) {
          if (extensions != null && extensions.isNotEmpty) {
            final ext = p.extension(entity.path).toLowerCase();
            if (!extensions.contains(ext)) continue;
          }
          try {
            final stat = File(entity.path).statSync();
            onFile(_Candidate(
              path: entity.path,
              size: stat.size,
              modified: stat.modified,
            ));
          } on FileSystemException {
            // Vanished or unreadable between listing and stat.
          }
        }
      }
    }

    await descend(Directory(root), 0);
  }

  /// Runs hashing in parallel across isolates.
  Future<List<String>> _mapHashes(List<_HashJob> jobs, CancelToken? cancel) async {
    final workers = _budget;
    final chunk = (jobs.length / workers).ceil().clamp(1, jobs.length);
    final batches = <List<_HashJob>>[];
    for (var i = 0; i < jobs.length; i += chunk) {
      batches.add(jobs.sublist(i, (i + chunk).clamp(0, jobs.length)));
    }

    final results = await Future.wait(batches.map((batch) async {
      if (cancel?.isCancelled ?? false) return <String>[];
      try {
        return await Isolate.run(() => _hashBatch(batch));
      } catch (e) {
        log.warn('hash batch failed: $e');
        return <String>[];
      }
    }));

    if (cancel?.isCancelled ?? false) return const [];
    return results.expand((r) => r).toList(growable: false);
  }
}

class _Candidate {
  _Candidate({required this.path, required this.size, required this.modified});

  final String path;
  final int size;
  final DateTime modified;
}

class _HashJob {
  _HashJob(this.path, this.window, this.size);

  final String path;
  final int window;
  final int size;
}

/// Isolate entry point: must be a top-level function.
List<String> _hashBatch(List<_HashJob> jobs) {
  final out = <String>[];
  for (final job in jobs) {
    try {
      if (job.window > 0) {
        // Hashing is CPU-bound; the isolate already isolates it from the UI.
        out.add(Sha256FileHasher.partialHashSync(job.path, job.window));
      } else {
        out.add(Sha256FileHasher.hashFileSync(job.path));
      }
    } catch (_) {
      // A file that cannot be read simply drops out of the run.
    }
  }
  return out;
}