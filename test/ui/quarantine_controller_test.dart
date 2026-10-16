import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:omni_clean_engine/core/safety/quarantine.dart';
import 'package:omni_clean_engine/ui/controllers/quarantine_controller.dart';

void main() {
  late Directory sandbox;
  late Quarantine quarantine;
  late DateTime now;

  setUp(() async {
    sandbox = await Directory.systemTemp.createTemp('omniclean_quar_');
    now = DateTime.utc(2026, 10, 16, 12);
    quarantine = Quarantine(
      root: Directory('${sandbox.path}/.omniclean/trash'),
      clock: () => now,
    );
    await quarantine.init();
  });

  tearDown(() async {
    if (sandbox.existsSync()) {
      await sandbox.delete(recursive: true);
    }
  });

  File write(String name, {int bytes = 512, Duration age = const Duration(days: 1)}) {
    final file = File('${sandbox.path}/$name');
    file.parent.createSync(recursive: true);
    file.writeAsBytesSync(List<int>.filled(bytes, 7));
    file.setLastModifiedSync(now.subtract(age).toLocal());
    return file;
  }

  QuarantineController build({
    Duration retention = const Duration(days: 7),
    Quarantine? store,
  }) =>
      QuarantineController(
        quarantine: store ?? quarantine,
        retention: retention,
      );

  group('loading', () {
    test('starts empty and idle', () {
      final controller = build();

      expect(controller.items, isEmpty);
      expect(controller.isEmpty, isTrue);
      expect(controller.totalBytes, 0);
      expect(controller.count, 0);
      expect(controller.phase, QuarantinePhase.idle);
      expect(controller.isBusy, isFalse);
    });

    test('loads entries written by the quarantine itself', () async {
      write('a.bin');
      await quarantine.store('${sandbox.path}/a.bin', module: 'test_module');

      final controller = build();
      await controller.load();

      expect(controller.count, 1);
      expect(controller.totalBytes, 512);
      expect(controller.items.single.module, 'test_module');
      expect(controller.phase, QuarantinePhase.idle);
    });

    test('a load failure degrades to failed instead of throwing', () async {
      final controller = build(store: _BrokenQuarantine());

      await controller.load();

      expect(controller.phase, QuarantinePhase.failed);
      expect(controller.items, isEmpty);
    });

    test('load notifies listeners', () async {
      final controller = build();
      var notifications = 0;
      controller.addListener(() => notifications++);

      await controller.load();

      expect(notifications, greaterThanOrEqualTo(1));
    });
  });

  group('restore', () {
    test('restores a file back to its original path', () async {
      final file = write('gone.bin');
      await quarantine.store(file.path, module: 'm');
      expect(file.existsSync(), isFalse);

      final controller = build();
      await controller.load();
      await controller.restore(controller.items.single.id);

      expect(file.existsSync(), isTrue);
      expect(controller.items, isEmpty);
      expect(controller.totalBytes, 0);
    });

    test('restoring an unknown id leaves the list untouched', () async {
      write('a.bin');
      await quarantine.store('${sandbox.path}/a.bin', module: 'm');

      final controller = build();
      await controller.load();
      await controller.restore('does-not-exist');

      expect(controller.count, 1);
      expect(controller.phase, QuarantinePhase.failed);
    });

    test('a restore failure reports the failure phase', () async {
      write('a.bin');
      await quarantine.store('${sandbox.path}/a.bin', module: 'm');

      final controller = build(store: _BrokenQuarantine(onRestore: true));
      await controller.load();
      await controller.restore('anything');

      expect(controller.phase, QuarantinePhase.failed);
    });

    test('restoring several entries keeps the rest in the list', () async {
      final a = write('a.bin');
      write('b.bin');
      write('c.bin');
      await quarantine.store(a.path, module: 'm');
      await quarantine.store('${sandbox.path}/b.bin', module: 'm');
      await quarantine.store('${sandbox.path}/c.bin', module: 'm');

      final controller = build();
      await controller.load();
      await controller.restore(controller.items.last.id);

      expect(controller.count, 2);
    });
  });

  group('purging', () {
    test('purging one entry removes it forever', () async {
      write('a.bin');
      await quarantine.store('${sandbox.path}/a.bin', module: 'm');

      final controller = build();
      await controller.load();
      await controller.purge(controller.items.single.id);

      expect(controller.items, isEmpty);
      expect(await quarantine.list(), isEmpty);
    });

    test('purging an unknown id is a no-op failure', () async {
      final controller = build();
      await controller.load();
      await controller.purge('nope');

      expect(controller.phase, QuarantinePhase.failed);
      expect(controller.items, isEmpty);
    });

    test('purge all empties the quarantine', () async {
      write('a.bin');
      write('b.bin');
      await quarantine.store('${sandbox.path}/a.bin', module: 'm');
      await quarantine.store('${sandbox.path}/b.bin', module: 'm');

      final controller = build();
      await controller.load();
      await controller.purgeAll();

      expect(controller.items, isEmpty);
      expect(await quarantine.totalBytes(), 0);
    });

    test('purge expired only removes what is older than the retention',
        () async {
      write('fresh.bin', age: const Duration(days: 1));
      write('stale.bin', age: const Duration(days: 30));
      await quarantine.store('${sandbox.path}/fresh.bin', module: 'm');

      // Re-store the stale one with a hand-written manifest timestamp so the
      // quarantine clock does not have to move.
      await quarantine.store('${sandbox.path}/stale.bin', module: 'm');
      final items = await quarantine.list();
      final stale = items.firstWhere((i) => i.originalPath.endsWith('stale.bin'));
      final manifest = File('${quarantine.root.path}/manifest/${stale.id}.json');
      final json = await manifest.readAsString();
      await manifest.writeAsString(
        json.replaceAll(
          stale.quarantinedAt.toUtc().toIso8601String(),
          now.subtract(const Duration(days: 30)).toUtc().toIso8601String(),
        ),
      );

      final controller = build();
      await controller.load();
      await controller.purgeExpired();

      expect(controller.count, 1);
      expect(controller.items.single.originalPath, endsWith('fresh.bin'));
      expect(controller.hasExpired, isFalse);
    });

    test('hasExpired is true while something is past the retention', () async {
      write('stale.bin');
      await quarantine.store('${sandbox.path}/stale.bin', module: 'm');
      final items = await quarantine.list();
      final manifest = File('${quarantine.root.path}/manifest/${items.single.id}.json');
      await manifest.writeAsString(
        (await manifest.readAsString()).replaceAll(
              items.single.quarantinedAt.toUtc().toIso8601String(),
              now.subtract(const Duration(days: 90)).toUtc().toIso8601String(),
            ),
      );

      final controller = build(retention: const Duration(days: 7));
      await controller.load();

      expect(controller.hasExpired, isTrue);
      expect(controller.expiredCount, 1);
    });

    test('a purge failure reports the failure phase', () async {
      final controller = build(store: _BrokenQuarantine(onPurge: true));
      await controller.load();
      await controller.purge('x');

      expect(controller.phase, QuarantinePhase.failed);
    });
  });

  group('retention', () {
    test('defaults to seven days and can be changed', () {
      final controller = build();

      expect(controller.retention, const Duration(days: 7));

      controller.setRetention(const Duration(days: 30));

      expect(controller.retention, const Duration(days: 30));
    });

    test('an unchanged retention does not notify', () {
      final controller = build();
      var notifications = 0;
      controller.addListener(() => notifications++);

      controller.setRetention(const Duration(days: 7));

      expect(notifications, 0);
    });

    test('a non-positive retention is ignored', () {
      final controller = build();

      controller.setRetention(Duration.zero);

      expect(controller.retention, const Duration(days: 7));
    });
  });

  group('busy state', () {
    test('isBusy is true while work is in flight', () async {
      final controller = build();
      final seen = <bool>[];
      controller.addListener(() => seen.add(controller.isBusy));

      await controller.load();

      expect(seen, contains(true));
      expect(controller.isBusy, isFalse);
    });

    test('dispose is safe to call twice', () async {
      final controller = build();
      await controller.load();

      controller.dispose();
      controller.dispose();
    });
  });
}

class _BrokenQuarantine implements Quarantine {
  _BrokenQuarantine({this.onRestore = false, this.onPurge = false});

  final bool onRestore;
  final bool onPurge;

  @override
  Future<void> init() async {}

  @override
  Future<QuarantineReceipt> store(String rawPath, {required String module}) async =>
      throw StateError('read-only');

  @override
  Future<List<QuarantineItem>> list() async => throw StateError('broken');

  @override
  Future<void> restore(String id) async {
    if (onRestore) throw StateError('cannot restore');
  }

  @override
  Future<QuarantineItem> purgeItem(String id) async {
    if (onPurge) throw StateError('cannot purge');
    throw StateError('no quarantine entry $id');
  }

  @override
  Future<List<QuarantineItem>> purgeOlderThan(Duration retention) async {
    if (onPurge) throw StateError('cannot purge');
    return const <QuarantineItem>[];
  }

  @override
  Future<List<QuarantineItem>> purgeAll() => purgeOlderThan(Duration.zero);

  @override
  Future<int> totalBytes() async => 0;

  @override
  Directory get root => Directory('/tmp/never-created');
}
