import 'dart:async';

import 'package:flutter_test/flutter_test.dart';
import 'package:omni_clean_engine/engine/metrics/metrics_collector.dart';
import 'package:omni_clean_engine/engine/metrics/parsers.dart';
import 'package:omni_clean_engine/engine/metrics/system_snapshot.dart';
import 'package:omni_clean_engine/engine/metrics/windows_metrics.dart';
import 'package:omni_clean_engine/engine/shell.dart';

class FakeReader {
  FakeReader(this.files);

  final Map<String, String> files;
  final List<String> requested = <String>[];

  Future<String?> call(String path) async {
    requested.add(path);
    return files[path];
  }
}

class FakeRunner {
  FakeRunner(this.responses);

  final Map<String, ShellResult> responses;
  final List<List<String>> invocations = <List<String>>[];

  Future<ShellResult> call(String executable, List<String> args) async {
    invocations.add(<String>[executable, ...args]);
    final key = '$executable ${args.join(' ')}';
    return responses[key] ??
        ShellResult(
          command: key,
          exitCode: 127,
          stdout: '',
          stderr: 'not found',
          duration: Duration.zero,
        );
  }
}

ShellResult ok(String command, String stdout) => ShellResult(
      command: command,
      exitCode: 0,
      stdout: stdout,
      stderr: '',
      duration: const Duration(milliseconds: 3),
    );

void main() {
  group('SystemSnapshot', () {
    test('starts empty and reports what it has', () {
      const snapshot = SystemSnapshot.empty(MetricsPlatform.linux);
      expect(snapshot.cpuUsage, 0);
      expect(snapshot.memory.hasReading, isFalse);
      expect(snapshot.disks, isEmpty);
      expect(snapshot.hasLoadAverage, isFalse);
      expect(snapshot.reclaimableBytes, 0);
    });

    test('derives the honest headline numbers', () {
      final snapshot = SystemSnapshot(
        platform: MetricsPlatform.linux,
        capturedAt: DateTime.utc(2026, 3, 1),
        cpuUsage: 0.42,
        cpuCores: 8,
        memory: MemorySample(
          totalBytes: 16 * 1024 * 1024 * 1024,
          availableBytes: 4 * 1024 * 1024 * 1024,
          freeBytes: 2 * 1024 * 1024 * 1024,
          buffersBytes: 1024 * 1024 * 1024,
          cachedBytes: 1024 * 1024 * 1024,
          swapTotalBytes: 2 * 1024 * 1024 * 1024,
          swapFreeBytes: 1024 * 1024 * 1024,
        ),
        disks: const <DiskSample>[],
        loadAverage: const <double>[0.5, 0.4, 0.3],
        uptime: const Duration(hours: 3),
      );

      expect(snapshot.cpuPercent, 42);
      expect(snapshot.memory.usedFraction, closeTo(0.75, 0.001));
      expect(snapshot.reclaimableBytes, 4 * 1024 * 1024 * 1024);
      expect(snapshot.hasLoadAverage, isTrue);
      expect(snapshot.hasUptime, isTrue);
      expect(snapshot.swapPercent, 50);
    });

    test('clamps hostile numbers instead of rendering nonsense', () {
      final snapshot = SystemSnapshot(
        platform: MetricsPlatform.unsupported,
        capturedAt: DateTime.utc(2026),
        cpuUsage: 12.5,
        cpuCores: -3,
        memory: MemorySample.empty,
        disks: const <DiskSample>[],
        loadAverage: const <double>[],
        uptime: Duration.zero,
      );
      expect(snapshot.cpuPercent, 100);
      expect(snapshot.cpuCores, 0);
      expect(snapshot.memoryPercent, 0);
    });
  });

  group('platform detection', () {
    test('maps an operating system name plus environment to a platform', () {
      expect(
        metricsPlatformFor(os: 'linux', environment: const <String, String>{}),
        MetricsPlatform.linux,
      );
      expect(
        metricsPlatformFor(os: 'windows', environment: const <String, String>{}),
        MetricsPlatform.windows,
      );
      expect(
        metricsPlatformFor(
          os: 'linux',
          environment: const <String, String>{'ANDROID_ROOT': '/system'},
        ),
        MetricsPlatform.android,
      );
      expect(
        metricsPlatformFor(os: 'macos', environment: const <String, String>{}),
        MetricsPlatform.unsupported,
      );
    });
  });

  group('LinuxMetricsSource', () {
    const procStatA = 'cpu  100 0 100 800 0 0 0 0 0 0\ncpu0 50 0 50 400 0 0 0 0 0 0';
    const procStatB = 'cpu  200 0 100 900 0 0 0 0 0 0\ncpu0 100 0 50 450 0 0 0 0 0 0';
    const memInfo = '''
MemTotal:       16000000 kB
MemFree:         2000000 kB
MemAvailable:    4000000 kB
Buffers:          500000 kB
Cached:          1500000 kB
SwapTotal:       2000000 kB
SwapFree:        1000000 kB
''';
    const dfOut = '''
Filesystem     1K-blocks      Used Available Use% Mounted on
/dev/nvme0n1p2 468000000 90000000 360000000  21% /
/dev/nvme0n1p2 468000000 90000000 360000000  21% /boot/efi
tmpfs              8192     0     8192   0% /run
/dev/loop1        20480  1024     8192   8% /snap/core/1
''';

    test('first capture has no CPU delta yet but fills everything else', () async {
      final reader = FakeReader(<String, String>{
        '/proc/stat': procStatA,
        '/proc/meminfo': memInfo,
        '/proc/loadavg': '0.52 0.41 0.33 1/900 12345',
        '/proc/uptime': '10984.02 40000.01',
      });
      final runner = FakeRunner(<String, ShellResult>{
        'df -k': ok('df -k', dfOut),
      });

      final source = LinuxMetricsSource(
        platform: MetricsPlatform.linux,
        readFile: reader.call,
        runCommand: runner.call,
      );
      final snapshot = await source.capture();

      expect(snapshot.platform, MetricsPlatform.linux);
      expect(snapshot.cpuUsage, 0, reason: 'no previous sample to diff against');
      expect(snapshot.memory.hasReading, isTrue);
      expect(snapshot.memory.totalBytes, 16000000 * 1024);
      expect(snapshot.disks, hasLength(1), reason: 'loop device skipped');
      expect(snapshot.disks.single.totalBytes, 468000000 * 1024);
      expect(snapshot.loadAverage, <double>[0.52, 0.41, 0.33]);
      expect(snapshot.uptime.inSeconds, 10984);
      expect(snapshot.cpuCores, greaterThanOrEqualTo(1));
      expect(reader.requested, contains('/proc/meminfo'));
    });

    test('second capture turns the /proc/stat delta into a real percentage',
        () async {
      final reader = FakeReader(<String, String>{
        '/proc/stat': procStatA,
        '/proc/meminfo': memInfo,
      });
      final runner = FakeRunner(<String, ShellResult>{
        'df -k': ok('df -k', dfOut),
      });
      final source = LinuxMetricsSource(
        readFile: reader.call,
        runCommand: runner.call,
      );

      await source.capture();
      reader.files['/proc/stat'] = procStatB;
      final snapshot = await source.capture();

      // total 1000 -> 1200, idle 800 -> 900 : (200-100)/200 = 50%
      expect(snapshot.cpuUsage, closeTo(0.5, 0.001));
      expect(snapshot.cpuPercent, closeTo(50, 0.5));
    });

    test('a machine with no /proc at all still yields a usable snapshot',
        () async {
      final source = LinuxMetricsSource(
        readFile: FakeReader(<String, String>{}).call,
        runCommand: FakeRunner(<String, ShellResult>{}).call,
      );
      final snapshot = await source.capture();

      expect(snapshot.memory.hasReading, isFalse);
      expect(snapshot.disks, isEmpty);
      expect(snapshot.cpuPercent, 0);
    });

    test('reports itself as android when asked, and reads /proc like linux',
        () async {
      final reader = FakeReader(<String, String>{
        '/proc/meminfo': memInfo,
      });
      final source = AndroidMetricsSource(
        readFile: reader.call,
        runCommand: FakeRunner(<String, ShellResult>{}).call,
      );
      final snapshot = await source.capture();

      expect(snapshot.platform, MetricsPlatform.android);
      expect(snapshot.memory.hasReading, isTrue);
    });
  });

  group('WindowsMetricsSource', () {
    const psJson = '''
{"cpu":23.75,"cores":12,"memTotal":34359738368,"memFree":8589934592,\
"disks":[{"device":"C:\\\\","total":512000000000,"free":128000000000}]}
''';

    test('parses the PowerShell payload into a snapshot', () async {
      final runner = FakeRunner(<String, ShellResult>{
        'powershell -NoProfile -NonInteractive -Command '
            'Get-CimInstance OmniCleanMetrics | ConvertTo-Json -Compress':
            ok('ps', psJson),
      });
      final source = WindowsMetricsSource(runCommand: runner.call);
      final snapshot = await source.capture();

      expect(snapshot.platform, MetricsPlatform.windows);
      expect(snapshot.cpuPercent, 24, reason: 'display percentages are whole');
      expect(snapshot.cpuCores, 12);
      expect(snapshot.memory.totalBytes, 34359738368);
      expect(snapshot.memory.reclaimableBytes, 8589934592);
      expect(snapshot.disks.single.device, r'C:\');
      expect(snapshot.disks.single.freeBytes, 128000000000);
    });

    test('a broken PowerShell never throws and never invents numbers',
        () async {
      final runner = FakeRunner(<String, ShellResult>{
        'powershell -NoProfile -NonInteractive -Command '
            'Get-CimInstance OmniCleanMetrics | ConvertTo-Json -Compress':
            ShellResult(
              command: 'ps',
              exitCode: 1,
              stdout: '',
              stderr: 'boom',
              duration: Duration.zero,
            ),
      });
      final snapshot =
          await WindowsMetricsSource(runCommand: runner.call).capture();

      expect(snapshot.cpuPercent, 0);
      expect(snapshot.memory.hasReading, isFalse);
      expect(snapshot.disks, isEmpty);
    });
  });

  group('parseWindowsMetricsJson', () {
    test('rejects garbage and empty payloads without throwing', () {
      expect(parseWindowsMetricsJson('not json'), isNull);
      expect(parseWindowsMetricsJson(''), isNull);
      expect(parseWindowsMetricsJson('null'), isNull);
      expect(parseWindowsMetricsJson('{}'), isNull);
    });

    test('ignores a disk row that is missing its numbers', () {
      final payload = parseWindowsMetricsJson(
        '{"cpu":1,"cores":2,"memTotal":10,"memFree":5,'
        '"disks":[{"device":"C:"},{"device":"D:","total":20,"free":8}]}',
      );
      expect(payload!.disks, hasLength(1));
      expect(payload.disks.single.device, 'D:');
      expect(payload.disks.single.totalBytes, 20);
    });
  });

  group('SystemMetricsService', () {
    test('streams fresh snapshots on an interval and stops cleanly', () async {
      var call = 0;
      final service = SystemMetricsService(
        interval: const Duration(milliseconds: 15),
        source: _CountingSource(() => call++),
      );
      final seen = <int>[];
      final sub = service.snapshots.listen((s) => seen.add(s.cpuPercent));

      await service.start();
      await Future<void>.delayed(const Duration(milliseconds: 120));
      await service.stop();
      await sub.cancel();

      expect(call, greaterThan(2));
      expect(seen.length, greaterThan(2));
      expect(service.latest, isNotNull);
      expect(service.isRunning, isFalse);
    });

    test('refresh pushes one snapshot without waiting for the timer', () async {
      final service = SystemMetricsService(
        interval: const Duration(hours: 1),
        source: _CountingSource(() => 42),
      );
      final first = await service.refresh();
      expect(first.cpuPercent, 42);
      expect(service.latest!.cpuPercent, 42);
    });

    test('a throwing source degrades to an empty snapshot', () async {
      final service = SystemMetricsService(
        interval: const Duration(hours: 1),
        source: _CountingSource(() => throw StateError('boom')),
      );
      final snapshot = await service.refresh();
      expect(snapshot.memory.hasReading, isFalse);
      expect(snapshot.platform, MetricsPlatform.linux,
          reason: 'falls back to the source it was given');
    });

    test('start is idempotent', () async {
      final service = SystemMetricsService(
        interval: const Duration(milliseconds: 10),
        source: _CountingSource(() => 0),
      );
      await service.start();
      await service.start();
      await Future<void>.delayed(const Duration(milliseconds: 60));
      await service.stop();
      expect(service.isRunning, isFalse);
    });
  });

  group('createMetricsSource', () {
    test('returns a working source for whatever host we are on', () async {
      final source = createMetricsSource();
      final snapshot = await source.capture();
      expect(snapshot.platform, isNot(MetricsPlatform.unsupported));
    });
  });
}

class _CountingSource implements MetricsSource {
  _CountingSource(this._cpuPercent);

  final int Function() _cpuPercent;

  @override
  MetricsPlatform get platform => MetricsPlatform.linux;

  @override
  Future<SystemSnapshot> capture() async {
    final percent = _cpuPercent();
    return SystemSnapshot(
      platform: platform,
      capturedAt: DateTime.utc(2026),
      cpuUsage: percent / 100,
      cpuCores: 4,
      memory: MemorySample.empty,
      disks: const <DiskSample>[],
      loadAverage: const <double>[],
      uptime: Duration.zero,
    );
  }
}
