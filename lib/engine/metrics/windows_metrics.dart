import 'dart:convert';

import 'parsers.dart';

/// The PowerShell command used to sample Windows.
///
/// It is a single round trip on purpose: starting PowerShell costs hundreds of
/// milliseconds, so CPU, memory and every fixed drive must arrive together in
/// one JSON document rather than in three separate processes.
const String windowsMetricsCommand =
    'Get-CimInstance OmniCleanMetrics | ConvertTo-Json -Compress';

/// The exact argument vector [windowsMetricsCommand] is invoked with.
const List<String> windowsMetricsArgs = <String>[
  '-NoProfile',
  '-NonInteractive',
  '-Command',
  windowsMetricsCommand,
];

/// One fixed drive as reported by `Win32_LogicalDisk`.
class WindowsDisk {
  const WindowsDisk({
    required this.device,
    required this.totalBytes,
    required this.freeBytes,
  });

  final String device;
  final int totalBytes;
  final int freeBytes;

  int get usedBytes => (totalBytes - freeBytes).clamp(0, totalBytes);
  bool get isValid => totalBytes > 0;
}

/// Everything we managed to scrape out of one PowerShell response.
class WindowsMetricsPayload {
  const WindowsMetricsPayload({
    required this.cpuPercent,
    required this.cpuCores,
    required this.memory,
    required this.disks,
  });

  final double cpuPercent;
  final int cpuCores;
  final MemorySample memory;
  final List<WindowsDisk> disks;
}

/// Parses the JSON produced by [windowsMetricsCommand].
///
/// Returns null — never throws — when the payload is not a usable object, so a
/// locked-down machine that refuses `Win32_Processor` simply shows no numbers.
WindowsMetricsPayload? parseWindowsMetricsJson(String text) {
  if (text.trim().isEmpty) return null;

  Object? decoded;
  try {
    decoded = jsonDecode(text);
  } on FormatException {
    return null;
  }
  if (decoded is! Map) return null;

  final cpu = _asDouble(decoded['cpu']);
  final cores = _asInt(decoded['cores']);
  final memTotal = _asInt(decoded['memTotal']);
  final memFree = _asInt(decoded['memFree']);
  if (cpu == null && cores == null && memTotal == null) return null;

  final disks = <WindowsDisk>[];
  final rawDisks = decoded['disks'];
  if (rawDisks is List) {
    for (final entry in rawDisks) {
      if (entry is! Map) continue;
      final device = entry['device'];
      final total = _asInt(entry['total']);
      final free = _asInt(entry['free']);
      if (device is! String || device.trim().isEmpty) continue;
      if (total == null || free == null) continue;
      final disk = WindowsDisk(
        device: device.trim(),
        totalBytes: total < 0 ? 0 : total,
        freeBytes: free < 0 ? 0 : free,
      );
      if (disk.isValid) disks.add(disk);
    }
  }

  return WindowsMetricsPayload(
    cpuPercent: (cpu ?? 0).clamp(0, 100).toDouble(),
    cpuCores: cores == null || cores < 0 ? 0 : cores,
    memory: MemorySample(
      totalBytes: memTotal == null || memTotal < 0 ? 0 : memTotal,
      // Windows has no `MemAvailable`, but the free figure is the honest
      // stand-in: it is what the system can hand back without paging.
      availableBytes: memFree == null || memFree < 0 ? 0 : memFree,
      freeBytes: memFree == null || memFree < 0 ? 0 : memFree,
    ),
    disks: List<WindowsDisk>.unmodifiable(disks),
  );
}

double? _asDouble(Object? value) {
  if (value is num) return value.toDouble();
  if (value is String) return double.tryParse(value);
  return null;
}

int? _asInt(Object? value) {
  if (value is int) return value;
  if (value is num) return value.toInt();
  if (value is String) return int.tryParse(value);
  return null;
}
