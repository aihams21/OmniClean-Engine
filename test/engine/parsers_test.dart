import 'package:flutter_test/flutter_test.dart';
import 'package:omni_clean_engine/engine/metrics/parsers.dart';

void main() {
  group('parseCpuLine', () {
    test('reads a raw aggregate cpu line', () {
      final CpuTimes? t = parseCpuLine('cpu  100 20 30 800 5 0 10 0 0 0');
      expect(t, isNotNull);
      expect(t!.idle, 805);
      expect(t.total, 965);
    });

    test('ignores per-core cpuN lines', () {
      expect(parseCpuLine('cpu0 1 2 3 4'), isNull);
      expect(parseCpuLine('intr 12345'), isNull);
      expect(parseCpuLine(''), isNull);
    });
  });

  group('cpuUsageBetween', () {
    test('returns busy fraction between two samples', () {
      final CpuTimes a = parseCpuLine('cpu  0 0 0 100 0 0 0')!;
      final CpuTimes b = parseCpuLine('cpu  20 0 0 180 0 0 0')!;
      expect(cpuUsageBetween(a, b), closeTo(0.2, 1e-9));
    });

    test('idle machine reports zero', () {
      final CpuTimes a = parseCpuLine('cpu  0 0 0 100 0')!;
      final CpuTimes b = parseCpuLine('cpu  0 0 0 200 0')!;
      expect(cpuUsageBetween(a, b), 0.0);
    });

    test('no elapsed ticks reports zero instead of NaN', () {
      final CpuTimes a = parseCpuLine('cpu  5 5 5 85 5')!;
      expect(cpuUsageBetween(a, a), 0.0);
    });

    test('result is always clamped inside 0..1', () {
      final CpuTimes a = parseCpuLine('cpu  0 0 0 100 0')!;
      final CpuTimes b = parseCpuLine('cpu  500 0 0 100 0')!;
      final double v = cpuUsageBetween(a, b);
      expect(v, inInclusiveRange(0.0, 1.0));
    });
  });

  group('parseMemInfo', () {
    test('derives used bytes from MemAvailable, not MemFree', () {
      final MemorySample m = parseMemInfo('''
MemTotal:       16316360 kB
MemFree:         2000000 kB
MemAvailable:   12000000 kB
Buffers:          300000 kB
Cached:          4000000 kB
SwapTotal:       2097148 kB
SwapFree:        1048574 kB
''');
      expect(m.totalBytes, 16316360 * 1024);
      expect(m.availableBytes, 12000000 * 1024);
      expect(m.usedBytes, (16316360 - 12000000) * 1024);
      expect(m.swapUsedBytes, (2097148 - 1048574) * 1024);
    });

    test('never reports negative usage on odd input', () {
      final MemorySample m = parseMemInfo('MemTotal: 1000 kB\nMemAvailable: 4000 kB');
      expect(m.usedBytes, 0);
      expect(m.swapUsedFraction, 0.0);
      expect(m.usedFraction, inInclusiveRange(0.0, 1.0));
    });

    test('missing swap section means no swap', () {
      final MemorySample m = parseMemInfo('MemTotal: 100 kB\nMemAvailable: 50 kB');
      expect(m.swapTotalBytes, 0);
      expect(m.swapUsedFraction, 0.0);
    });

    test('empty text degrades to zeroes without throwing', () {
      final MemorySample m = parseMemInfo('');
      expect(m.totalBytes, 0);
      expect(m.usedFraction, 0.0);
    });
  });

  group('parseDfOutput', () {
    test('parses coreutils df --output format', () {
      final DiskSample d = parseDfOutput('''
Filesystem     1B-blocks         Used        Available
/dev/sda1      1000000000      400000000      600000000
''');
      expect(d.totalBytes, 1000000000);
      expect(d.usedBytes, 400000000);
      expect(d.freeBytes, 600000000);
      expect(d.usedFraction, closeTo(0.4, 1e-9));
    });

    test('parses classic df -k output (wraps long device names)', () {
      final DiskSample d = parseDfOutput('''
Filesystem     1024-blocks      Used Available Capacity Mounted on
/dev/mapper/vg-root
               104857600  41943040  62914560      40% /
''');
      expect(d.totalBytes, 104857600 * 1024);
      expect(d.usedBytes, 41943040 * 1024);
      expect(d.freeBytes, 62914560 * 1024);
    });

    test('skips pseudo filesystems', () {
      final DiskSample d = parseDfOutput('''
Filesystem     1B-blocks         Used        Available
tmpfs           16777216           0        16777216
/dev/sda1      2000000000     500000000     1500000000
devtmpfs          102400           0          102400
''');
      expect(d.totalBytes, 2000000000);
    });

    test('no data yields an empty sample', () {
      expect(parseDfOutput('').totalBytes, 0);
    });
  });

  group('parseLoadAvg', () {
    test('reads the three averages', () {
      expect(parseLoadAvg('0.52 1.03 0.87 2/1234 5678'), [0.52, 1.03, 0.87]);
    });

    test('garbage yields zeros', () {
      expect(parseLoadAvg('nope'), [0, 0, 0]);
    });
  });

  group('parseUptime', () {
    test('reads seconds from /proc/uptime', () {
      expect(parseUptime('98765.43 123456.78'), closeTo(98765.43, 0.01));
    });

    test('garbage yields zero', () {
      expect(parseUptime('x y'), 0);
    });
  });
}