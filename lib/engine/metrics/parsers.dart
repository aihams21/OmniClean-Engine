/// Pure, platform-independent parsers for the OS metric sources OmniClean
/// reads. Kept free of `dart:io` and Flutter so they are directly unit
/// testable and reusable across every platform module.
library;

import 'dart:convert';
import 'dart:math' as math;

/// Jiffies consumed by the aggregate `cpu` line of `/proc/stat`.
class CpuTimes {
  const CpuTimes({required this.total, required this.idle});

  /// Sum of every column (user, nice, system, idle, iowait, irq, softirq, ...).
  final int total;

  /// Idle + iowait, i.e. the columns where the CPU was not doing work.
  final int idle;

  static const CpuTimes zero = CpuTimes(total: 0, idle: 0);
}

/// Parses a single `/proc/stat` line. Returns `null` for per-core (`cpu0`)
/// and non-cpu lines, so callers can feed the whole file line by line.
CpuTimes? parseCpuLine(String line) {
  final String trimmed = line.trim();
  if (!trimmed.startsWith('cpu ')) return null;
  final List<String> parts = trimmed.split(RegExp(r'\s+'));
  if (parts.length < 5) return null;
  int total = 0;
  for (int i = 1; i < parts.length; i++) {
    total += int.tryParse(parts[i]) ?? 0;
  }
  final int idle = (int.tryParse(parts[4]) ?? 0) +
      (parts.length > 5 ? int.tryParse(parts[5]) ?? 0 : 0);
  return CpuTimes(total: total, idle: idle);
}

/// Busy fraction in `0..1` between two samples. A zero or negative elapsed
/// window (first sample, or a stalled counter) reports `0` rather than NaN.
double cpuUsageBetween(CpuTimes previous, CpuTimes current) {
  final int totalDelta = current.total - previous.total;
  final int idleDelta = current.idle - previous.idle;
  if (totalDelta <= 0) return 0;
  final double ratio = (totalDelta - idleDelta) / totalDelta;
  return ratio.clamp(0.0, 1.0).toDouble();
}

/// Snapshot of `/proc/meminfo`, normalised to bytes.
class MemorySample {
  const MemorySample({
    this.totalBytes = 0,
    this.availableBytes = 0,
    this.freeBytes = 0,
    this.buffersBytes = 0,
    this.cachedBytes = 0,
    this.swapTotalBytes = 0,
    this.swapFreeBytes = 0,
  });

  static const MemorySample empty = MemorySample();

  final int totalBytes;
  final int availableBytes;
  final int freeBytes;
  final int buffersBytes;
  final int cachedBytes;
  final int swapTotalBytes;
  final int swapFreeBytes;

  int get usedBytes => math.max(0, totalBytes - availableBytes);
  int get freeAndCacheBytes =>
      math.max(0, freeBytes + buffersBytes + cachedBytes);
  int get swapUsedBytes => math.max(0, swapTotalBytes - swapFreeBytes);
  double get usedFraction =>
      totalBytes <= 0 ? 0 : (usedBytes / totalBytes).clamp(0.0, 1.0).toDouble();
  double get swapUsedFraction => swapTotalBytes <= 0
      ? 0
      : (swapUsedBytes / swapTotalBytes).clamp(0.0, 1.0).toDouble();

  /// Memory the kernel can hand back on demand without swapping. This is what
  /// a "clean RAM" action can honestly promise, and nothing more.
  int get reclaimableBytes => math.max(0, availableBytes);

  /// False when the probe never produced a usable line, so the UI can say
  /// "unavailable" instead of drawing a confident "0 % used".
  bool get hasReading => totalBytes > 0;

  @override
  bool operator ==(Object other) =>
      other is MemorySample &&
      other.totalBytes == totalBytes &&
      other.availableBytes == availableBytes &&
      other.freeBytes == freeBytes &&
      other.buffersBytes == buffersBytes &&
      other.cachedBytes == cachedBytes &&
      other.swapTotalBytes == swapTotalBytes &&
      other.swapFreeBytes == swapFreeBytes;

  @override
  int get hashCode => Object.hash(totalBytes, availableBytes, freeBytes,
      buffersBytes, cachedBytes, swapTotalBytes, swapFreeBytes);
}

/// Parses `/proc/meminfo` (and Android's near-identical copy). Missing keys
/// degrade to zero instead of throwing, so an unexpected kernel stays usable.
MemorySample parseMemInfo(String text) {
  int kb(String key) {
    final RegExpMatch? m =
        RegExp('^${RegExp.escape(key)}:\\s+(\\d+)', multiLine: true)
            .firstMatch(text);
    return int.tryParse(m?.group(1) ?? '') ?? 0;
  }

  return MemorySample(
    totalBytes: kb('MemTotal') * 1024,
    availableBytes: kb('MemAvailable') * 1024,
    freeBytes: kb('MemFree') * 1024,
    buffersBytes: kb('Buffers') * 1024,
    cachedBytes: kb('Cached') * 1024,
    swapTotalBytes: kb('SwapTotal') * 1024,
    swapFreeBytes: kb('SwapFree') * 1024,
  );
}

/// Space accounting for the filesystem that holds a path.
class DiskSample {
  const DiskSample({
    this.device = '',
    this.totalBytes = 0,
    this.usedBytes = 0,
    this.freeBytes = 0,
  });

  static const DiskSample empty = DiskSample();

  /// Block device or mount point the numbers belong to; empty when the probe
  /// could not name it.
  final String device;

  final int totalBytes;
  final int usedBytes;
  final int freeBytes;

  double get usedFraction =>
      totalBytes <= 0 ? 0 : (usedBytes / totalBytes).clamp(0.0, 1.0).toDouble();
  int get usedPercent => (usedFraction * 100).round();

  bool get hasReading => totalBytes > 0;

  @override
  bool operator ==(Object other) =>
      other is DiskSample &&
      other.device == device &&
      other.totalBytes == totalBytes &&
      other.usedBytes == usedBytes &&
      other.freeBytes == freeBytes;

  @override
  int get hashCode => Object.hash(device, totalBytes, usedBytes, freeBytes);
}

const Set<String> _pseudoFileSystems = {
  'tmpfs',
  'devtmpfs',
  'squashfs',
  'overlay',
  'proc',
  'sysfs',
  'devfs',
  'cgroup',
  'cgroup2',
  'none',
  'ramfs',
  'efivarfs',
  'fusectl',
  'mqueue',
  'securityfs',
  'debugfs',
  'tracefs',
  'configfs',
  'pstore',
  'bpf',
  'hugetlbfs',
  'autofs',
  'nsfs',
  'binfmt_misc',
  'rpc_pipefs',
};

bool _isPseudo(String device) {
  final String d = device.trim().toLowerCase();
  if (d.isEmpty) return true;
  if (d.startsWith('/dev/loop') || d.startsWith('loop')) return true;
  for (final String fs in _pseudoFileSystems) {
    if (d == fs) return true;
  }
  return false;
}

/// Reads the block unit out of a `df` header (`1B-blocks`, `1024-blocks`,
/// `1K-blocks`, `1M-blocks`, ...). A missing or unrecognised header means the
/// caller asked for bytes, so the multiplier is 1.
int _dfBlockSize(String text) {
  final RegExpMatch? m =
      RegExp(r'(\d+)([BKMGTPE]?)-blocks', caseSensitive: false)
          .firstMatch(text);
  if (m == null) return 1;
  final int n = int.tryParse(m.group(1)!) ?? 1;
  const Map<String, int> power = {
    '': 1,
    'B': 1,
    'K': 1024,
    'M': 1024 * 1024,
    'G': 1024 * 1024 * 1024,
    'T': 1024 * 1024 * 1024 * 1024,
    'P': 1024 * 1024 * 1024 * 1024 * 1024,
    'E': 1024 * 1024 * 1024 * 1024 * 1024 * 1024,
  };
  return n * (power[m.group(2)!.toUpperCase()] ?? 1);
}

/// Parses either `df -B1 --output=size,used,avail` or classic `df -k`
/// (including the wrapped-device-name form used by long LVM names), and
/// keeps only the first real block device it can read.
DiskSample parseDfOutput(String text) {
  final int block = _dfBlockSize(text);
  const LineSplitter lineSplitter = LineSplitter();
  for (final String raw in lineSplitter.convert(text)) {
    final String line = raw.trim();
    if (line.isEmpty) continue;
    List<String> cols = line.split(RegExp(r'\s+'));
    if (cols.length < 4) continue;
    // `df -k` wraps a long device name onto its own line, leaving the numeric
    // columns of the same record one slot to the left with no device token.
    if (cols.length >= 5 && int.tryParse(cols[0]) != null) {
      cols = ['', ...cols];
    }
    final String device = cols[0];
    if (device.isEmpty ? cols.length < 5 : _isPseudo(device)) continue;
    final int? total = int.tryParse(cols[1]);
    final int? used = int.tryParse(cols[2]);
    final int? avail = int.tryParse(cols[3]);
    if (total == null || used == null || avail == null) continue;
    return DiskSample(
      device: device.isEmpty ? cols[5] : device,
      totalBytes: total * block,
      usedBytes: used * block,
      freeBytes: avail * block,
    );
  }
  return DiskSample.empty;
}

/// First three load averages from `/proc/loadavg`.
List<double> parseLoadAvg(String text) {
  final List<String> parts = text.trim().split(RegExp(r'\s+'));
  if (parts.length < 3) return const [0, 0, 0];
  return List<double>.generate(3, (int i) => double.tryParse(parts[i]) ?? 0,
      growable: false);
}

/// Seconds of uptime from `/proc/uptime`.
double parseUptime(String text) {
  final String? first = text.trim().split(RegExp(r'\s+')).firstOrNull;
  return double.tryParse(first ?? '') ?? 0;
}
