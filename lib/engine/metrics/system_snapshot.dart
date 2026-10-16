import 'package:flutter/foundation.dart';

import 'parsers.dart';

/// The three operating systems this app actually supports, plus an honest
/// "I do not know how to measure this machine" bucket.
enum MetricsPlatform { linux, windows, android, unsupported }

/// Chooses a [MetricsPlatform] from an operating-system name and an
/// environment map, so the decision is testable without touching `dart:io`.
MetricsPlatform metricsPlatformFor({
  required String os,
  required Map<String, String> environment,
}) {
  final lower = os.toLowerCase();
  if (lower.contains('android')) return MetricsPlatform.android;
  if (lower.startsWith('win')) return MetricsPlatform.windows;
  if (lower.contains('linux')) {
    // A Linux kernel under Android still answers /proc, but the user-visible
    // platform is Android, so that is what the UI must label.
    if (environment.containsKey('ANDROID_ROOT') ||
        environment.containsKey('ANDROID_DATA')) {
      return MetricsPlatform.android;
    }
    return MetricsPlatform.linux;
  }
  return MetricsPlatform.unsupported;
}

/// One immutable reading of the whole machine.
///
/// Every field is already sanitised: percentages are clamped, core counts can
/// never go negative, and a subsystem that failed simply reports nothing rather
/// than a made-up zero that the UI would happily draw as "0 % free".
@immutable
class SystemSnapshot {
  const SystemSnapshot({
    required this.platform,
    required this.capturedAt,
    required this.cpuUsage,
    required int cpuCores,
    required this.memory,
    required this.disks,
    required this.loadAverage,
    required this.uptime,
  }) : cpuCores = cpuCores < 0 ? 0 : cpuCores;

  /// The "nothing worked" reading, used as the base for real captures and as
  /// the fallback when every probe failed.
  const SystemSnapshot.empty(MetricsPlatform platform)
      : this(
          platform: platform,
          capturedAt: null,
          cpuUsage: 0,
          cpuCores: 0,
          memory: MemorySample.empty,
          disks: const <DiskSample>[],
          loadAverage: const <double>[],
          uptime: Duration.zero,
        );

  final MetricsPlatform platform;

  /// Null only in [SystemSnapshot.empty]; set the moment a probe succeeded.
  final DateTime? capturedAt;

  /// Fraction of CPU time spent outside idle, `0..1`.
  final double cpuUsage;
  final int cpuCores;
  final MemorySample memory;
  final List<DiskSample> disks;

  /// 1/5/15-minute load averages; empty on platforms that do not publish them.
  final List<double> loadAverage;
  final Duration uptime;

  int get cpuPercent => _clampPercent(cpuUsage);

  int get memoryPercent =>
      memory.hasReading ? _clampPercent(memory.usedFraction) : 0;

  int get swapPercent =>
      memory.swapTotalBytes > 0 ? _clampPercent(memory.swapUsedFraction) : 0;

  /// What a cache-and-RAM action could honestly hand back right now.
  int get reclaimableBytes => memory.hasReading ? memory.reclaimableBytes : 0;

  bool get hasMemory => memory.hasReading;
  bool get hasDisks => disks.isNotEmpty;
  bool get hasLoadAverage => loadAverage.isNotEmpty;
  bool get hasUptime => uptime > Duration.zero;
  bool get isLive => capturedAt != null;

  /// The disk closest to filling up — the one worth warning about.
  DiskSample? get tightestDisk {
    DiskSample? worst;
    for (final disk in disks) {
      if (disk.totalBytes <= 0) continue;
      if (worst == null || disk.usedFraction > worst.usedFraction) {
        worst = disk;
      }
    }
    return worst;
  }

  @override
  bool operator ==(Object other) =>
      other is SystemSnapshot &&
      other.platform == platform &&
      other.capturedAt == capturedAt &&
      other.cpuUsage == cpuUsage &&
      other.cpuCores == cpuCores &&
      other.memory == memory &&
      other.uptime == uptime &&
      _sameList(other.disks, disks) &&
      _sameList(other.loadAverage, loadAverage);

  @override
  int get hashCode => Object.hash(
        platform,
        capturedAt,
        cpuUsage,
        cpuCores,
        memory,
        uptime,
        disks.length,
        loadAverage.length,
      );

  @override
  String toString() =>
      'SystemSnapshot(${platform.name}, cpu ${cpuPercent}%, ram $memoryPercent%, '
      '${disks.length} disk(s))';

  static int _clampPercent(double fraction) {
    if (fraction.isNaN) return 0;
    final scaled = (fraction * 100).round();
    if (scaled < 0) return 0;
    if (scaled > 100) return 100;
    return scaled;
  }
}

bool _sameList<T>(List<T> a, List<T> b) {
  if (identical(a, b)) return true;
  if (a.length != b.length) return false;
  for (var i = 0; i < a.length; i++) {
    if (a[i] != b[i]) return false;
  }
  return true;
}
