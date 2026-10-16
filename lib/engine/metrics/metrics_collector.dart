import 'dart:async';
import 'dart:io';

import '../../core/util/logger.dart';
import '../shell.dart';
import 'parsers.dart';
import 'system_snapshot.dart';
import 'windows_metrics.dart';

/// Reads a whole text file; returns null when it is missing or unreadable.
typedef MetricsFileReader = Future<String?> Function(String path);

/// Runs a process and returns its result. Injected so tests never shell out.
typedef MetricsCommandRunner = Future<ShellResult> Function(
  String executable,
  List<String> args,
);

/// Anything that can produce a [SystemSnapshot] for one machine.
abstract class MetricsSource {
  MetricsPlatform get platform;

  Future<SystemSnapshot> capture();
}

/// Samples Linux (and Android) from `/proc` and `df`.
///
/// CPU usage needs two readings, so the first [capture] legitimately reports
/// `0 %` — that is a real measurement of "no interval has elapsed yet", not a
/// failure.
class LinuxMetricsSource implements MetricsSource {
  LinuxMetricsSource({
    MetricsPlatform? platform,
    MetricsFileReader? readFile,
    MetricsCommandRunner? runCommand,
  })  : platform = platform ?? MetricsPlatform.linux,
        _readFile = readFile ?? _readFileFromDisk,
        _runCommand = runCommand ?? Shell.run;

  @override
  final MetricsPlatform platform;

  final MetricsFileReader _readFile;
  final MetricsCommandRunner _runCommand;

  CpuTimes? _previousCpu;

  static Future<String?> _readFileFromDisk(String path) async {
    try {
      return await File(path).readAsString();
    } on FileSystemException catch (e) {
      log.fine('metrics: cannot read $path (${e.osError?.errorCode})');
      return null;
    }
  }

  @override
  Future<SystemSnapshot> capture() async {
    final stat = await _readFile('/proc/stat');
    final memInfo = await _readFile('/proc/meminfo');
    final loadAvg = await _readFile('/proc/loadavg');
    final uptime = await _readFile('/proc/uptime');
    final df = await _run('df', const <String>['-k']);

    var cpu = 0.0;
    final coresSeen = _countCpuCores(stat);
    final line = _aggregateCpuLine(stat);
    if (line != null) {
      final previous = _previousCpu;
      _previousCpu = line;
      if (previous != null) cpu = cpuUsageBetween(previous, line);
    }

    final disk = (df != null && df.ok) ? parseDfOutput(df.stdout) : null;

    return SystemSnapshot(
      platform: platform,
      capturedAt: DateTime.now(),
      cpuUsage: cpu,
      cpuCores: coresSeen > 0 ? coresSeen : _hostCores(),
      memory: memInfo == null ? MemorySample.empty : parseMemInfo(memInfo),
      disks: disk != null && disk.hasReading
          ? <DiskSample>[disk]
          : const <DiskSample>[],
      loadAverage: loadAvg == null
          ? const <double>[]
          : parseLoadAvg(loadAvg).where((v) => v > 0).toList(growable: false),
      uptime: uptime == null
          ? Duration.zero
          : Duration(seconds: parseUptime(uptime).round()),
    );
  }

  static int _hostCores() {
    final n = Platform.numberOfProcessors;
    return n > 0 ? n : 1;
  }

  Future<ShellResult?> _run(String executable, List<String> args) async {
    try {
      return await _runCommand(executable, args);
    } catch (e) {
      log.warn('metrics: $executable failed: $e');
      return null;
    }
  }

  static int _countCpuCores(String? stat) {
    if (stat == null) return 0;
    return stat
        .split('\n')
        .where((l) => l.startsWith('cpu') && l.length > 3 && l[3] != ' ')
        .length;
  }

  /// The aggregate `cpu ` line. [parseCpuLine] deliberately rejects per-core
  /// lines, so the file has to be walked line by line or the totals would be a
  /// meaningless sum of every core at once.
  static CpuTimes? _aggregateCpuLine(String? stat) {
    if (stat == null) return null;
    for (final line in stat.split('\n')) {
      final parsed = parseCpuLine(line);
      if (parsed != null) return parsed;
    }
    return null;
  }
}

/// Android shares the Linux `/proc` layout; only the label differs.
class AndroidMetricsSource extends LinuxMetricsSource {
  AndroidMetricsSource({
    MetricsFileReader? readFile,
    MetricsCommandRunner? runCommand,
  }) : super(
          platform: MetricsPlatform.android,
          readFile: readFile,
          runCommand: runCommand,
        );
}

/// Samples Windows through one PowerShell round trip.
class WindowsMetricsSource implements MetricsSource {
  WindowsMetricsSource({MetricsCommandRunner? runCommand})
      : _runCommand = runCommand ?? Shell.run;

  @override
  MetricsPlatform get platform => MetricsPlatform.windows;

  final MetricsCommandRunner _runCommand;

  @override
  Future<SystemSnapshot> capture() async {
    try {
      final result =
          await _runCommand('powershell', windowsMetricsArgs);
      if (!result.ok) {
        log.warn('metrics: powershell failed (${result.exitCode})');
        return SystemSnapshot.empty(platform);
      }
      final payload = parseWindowsMetricsJson(result.stdout);
      if (payload == null) {
        log.warn('metrics: unparseable PowerShell payload');
        return SystemSnapshot.empty(platform);
      }
      return SystemSnapshot(
        platform: platform,
        capturedAt: DateTime.now(),
        cpuUsage: payload.cpuPercent / 100,
        cpuCores: payload.cpuCores > 0 ? payload.cpuCores : 1,
        memory: payload.memory,
        disks: payload.disks
            .map(
              (d) => DiskSample(
                device: d.device,
                totalBytes: d.totalBytes,
                usedBytes: d.usedBytes,
                freeBytes: d.freeBytes,
              ),
            )
            .toList(growable: false),
        loadAverage: const <double>[],
        uptime: Duration.zero,
      );
    } catch (e) {
      log.warn('metrics: powershell threw: $e');
      return SystemSnapshot.empty(platform);
    }
  }
}

/// A source that reports nothing, used when we meet an OS we cannot measure.
class UnsupportedMetricsSource implements MetricsSource {
  const UnsupportedMetricsSource();

  @override
  MetricsPlatform get platform => MetricsPlatform.unsupported;

  @override
  Future<SystemSnapshot> capture() async =>
      SystemSnapshot.empty(platform);
}

/// Picks the right source for the machine the app is running on.
MetricsSource createMetricsSource() {
  final kind = metricsPlatformFor(
    os: Platform.operatingSystem,
    environment: Platform.environment,
  );
  switch (kind) {
    case MetricsPlatform.android:
      return AndroidMetricsSource();
    case MetricsPlatform.windows:
      return WindowsMetricsSource();
    case MetricsPlatform.linux:
      return LinuxMetricsSource();
    case MetricsPlatform.unsupported:
      return const UnsupportedMetricsSource();
  }
}

/// Drives a [MetricsSource] on a timer and publishes what it finds.
///
/// Plain Dart on purpose: the engine layer stays Flutter-free and testable, and
/// the UI simply subscribes to [snapshots].
class SystemMetricsService {
  SystemMetricsService({
    MetricsSource? source,
    this.interval = const Duration(seconds: 2),
  }) : source = source ?? createMetricsSource();

  final MetricsSource source;
  final Duration interval;

  final StreamController<SystemSnapshot> _controller =
      StreamController<SystemSnapshot>.broadcast();
  Timer? _timer;
  SystemSnapshot? _latest;
  bool _running = false;

  Stream<SystemSnapshot> get snapshots => _controller.stream;
  SystemSnapshot? get latest => _latest;
  bool get isRunning => _running;

  /// Takes one reading immediately and publishes it.
  Future<SystemSnapshot> refresh() async {
    SystemSnapshot snapshot;
    try {
      snapshot = await source.capture();
    } catch (e) {
      log.error('metrics: source blew up — $e');
      snapshot = SystemSnapshot.empty(source.platform);
    }
    _latest = snapshot;
    if (!_controller.isClosed) _controller.add(snapshot);
    return snapshot;
  }

  /// Begins polling. Calling it twice is harmless.
  Future<void> start() async {
    if (_running) return;
    _running = true;
    await refresh();
    _timer = Timer.periodic(interval, (_) => refresh());
  }

  Future<void> stop() async {
    _timer?.cancel();
    _timer = null;
    _running = false;
  }

  Future<void> dispose() async {
    await stop();
    await _controller.close();
  }
}
