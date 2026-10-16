import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:omni_clean_engine/core/safety/protected_paths.dart';
import 'package:omni_clean_engine/core/safety/quarantine.dart';
import 'package:omni_clean_engine/core/safety/safe_delete.dart';
import 'package:omni_clean_engine/core/util/byte_fmt.dart';

void main() {
  late Directory sandbox;
  late Quarantine quarantine;

  setUp(() async {
    sandbox = await Directory.systemTemp.createTemp('omniclean_test_');
    quarantine = Quarantine(
      root: Directory('${sandbox.path}/.omniclean/trash'),
      clock: () => DateTime.utc(2026, 10, 16, 12),
    );
    await quarantine.init();
  });

  tearDown(() async {
    if (sandbox.existsSync()) {
      await sandbox.delete(recursive: true);
    }
  });

  group('ProtectedPaths — absolute deny-list', () {
    test('never touches system roots', () {
      for (final p in <String>[
        '/',
        '/etc',
        '/etc/passwd',
        '/usr',
        '/usr/bin/python3',
        '/bin/sh',
        '/sbin',
        '/lib',
        '/boot/vmlinuz',
        '/proc/self',
        '/sys/class',
        '/dev/sda',
        '/var/lib/dpkg/status',
        '/var/lib/docker/volumes',
        '/var/spool/cron',
        '/root',
        '/home',
      ]) {
        expect(
          ProtectedPaths.isProtected(p),
          isTrue,
          reason: '$p must be hard-protected',
        );
      }
    });

    test('never touches user credentials, configs or databases', () {
      for (final p in <String>[
        '/home/aiham/.ssh/id_rsa',
        '/home/aiham/.ssh/authorized_keys',
        '/home/aiham/.gnupg/secring.gpg',
        '/home/aiham/.config/librewolf/profile',
        '/home/aiham/.bashrc',
        '/home/aiham/.clinerules',
        '/home/aiham/.local/share/keyrings/login.keyring',
        '/home/aiham/projects/app/.git/objects/ab/cdef',
        '/var/www/omniclean.sqlite3',
        '/home/aiham/backups/dump.sql',
      ]) {
        expect(
          ProtectedPaths.isProtected(p),
          isTrue,
          reason: '$p must be hard-protected',
        );
      }
    });

    test('protects by extension even in an innocent-looking directory', () {
      expect(ProtectedPaths.isProtected('/tmp/cache/users.db'), isTrue);
      expect(ProtectedPaths.isProtected('/tmp/cache/site.sqlite3'), isTrue);
      expect(ProtectedPaths.isProtected('/tmp/cache/private.pem'), isTrue);
      expect(ProtectedPaths.isProtected('/tmp/cache/vault.kdbx'), isTrue);
    });

    test('allows ordinary cache junk', () {
      for (final p in <String>[
        '/tmp/thumb-1234.jpg',
        '/home/aiham/.cache/thunderbird/abc/Cache2/entry',
        '/home/aiham/.cache/pip/wheels/9a/http-2.7.0-py3-none-any.whl',
        '/home/aiham/.cache/mozilla/firefox/xyz/diskCache/2F/entries',
      ]) {
        expect(
          ProtectedPaths.isProtected(p),
          isFalse,
          reason: '$p is legitimate cache and must remain cleanable',
        );
      }
    });

    test('protected check is case-insensitive on Windows paths', () {
      expect(ProtectedPaths.isProtected('C:/Windows/System32/config'), isTrue);
      expect(
          ProtectedPaths.isProtected('c:\\program files\\x\\app.db'), isTrue);
      expect(ProtectedPaths.isProtected(r'C:\Users\me\AppData\Roaming\Mozilla'),
          isTrue);
    });
  });

  group('Quarantine — nothing is ever unlinked directly', () {
    test('moves a file into the quarantine and keeps its bytes readable',
        () async {
      final victim = File('${sandbox.path}/thumb.jpg');
      await victim.writeAsBytes(List<int>.filled(2048, 7));

      final receipt = await quarantine.store(victim.path, module: 'test');

      expect(victim.existsSync(), isFalse, reason: 'source must be moved away');
      expect(receipt.bytes, 2048);
      final stored = File(receipt.storedPath);
      expect(stored.existsSync(), isTrue);
      expect(await stored.length(), 2048);
      expect(await stored.readAsBytes(), List<int>.filled(2048, 7));
    });

    test('manifest round-trips so the file can be restored later', () async {
      final victim = File('${sandbox.path}/photo.png');
      await victim.writeAsBytes(List<int>.filled(64, 3));

      await quarantine.store(victim.path, module: 'duplicates');
      final items = await quarantine.list();

      expect(items, hasLength(1));
      final item = items.single;
      expect(item.originalPath, victim.path);
      expect(item.module, 'duplicates');
      expect(item.bytes, 64);
      expect(item.quarantinedAt, DateTime.utc(2026, 10, 16, 12));

      await quarantine.restore(item.id);
      expect(File(item.originalPath).existsSync(), isTrue);
      expect(await File(item.originalPath).readAsBytes(), hasLength(64));
      expect(await quarantine.list(), isEmpty);
    });

    test('quarantines a whole directory tree preserving structure', () async {
      final dir = Directory('${sandbox.path}/cache-root')
        ..createSync(recursive: true);
      for (var i = 0; i < 5; i++) {
        File('${dir.path}/f$i.bin')
            .writeAsBytesSync(List<int>.filled(100 + i, i));
      }
      File('${dir.path}/sub/g.bin').parent.createSync(recursive: true);
      File('${dir.path}/sub/g.bin').writeAsBytesSync(List<int>.filled(9, 9));

      final receipt = await quarantine.store(dir.path, module: 'cache');

      expect(dir.existsSync(), isFalse);
      expect(receipt.isDirectory, isTrue);
      expect(receipt.bytes, 100 + 101 + 102 + 103 + 104 + 9);
      expect(File('${receipt.storedPath}/sub/g.bin').existsSync(), isTrue);
    });

    test('purges only entries older than the retention window', () async {
      var now = DateTime.utc(2026, 10, 16, 12);
      quarantine = Quarantine(
        root: Directory('${sandbox.path}/.omniclean/trash'),
        clock: () => now,
      );
      await quarantine.init();

      final old = File('${sandbox.path}/old.tmp');
      await old.writeAsBytes([1, 2, 3]);
      final oldReceipt = await quarantine.store(old.path, module: 'test');

      now = DateTime.utc(2026, 10, 16, 12).add(const Duration(days: 3));
      final newer = File('${sandbox.path}/new.tmp');
      await newer.writeAsBytes([1, 2, 3]);
      final newReceipt = await quarantine.store(newer.path, module: 'test');

      // Purge from a clock 10 days on, so the first entry is 10 days old and
      // the second is exactly 7 days old (i.e. still inside retention).
      now = DateTime.utc(2026, 10, 16, 12).add(const Duration(days: 10));
      final purged = await quarantine.purgeOlderThan(const Duration(days: 7));

      expect(purged, hasLength(1));
      expect(purged.single.id, oldReceipt.id);
      expect(File(oldReceipt.storedPath).existsSync(), isFalse);
      expect(File(newReceipt.storedPath).existsSync(), isTrue);
      expect(File(newReceipt.originalPath).existsSync(), isFalse);
    });

    test('survives a corrupted manifest instead of throwing', () async {
      final victim = File('${sandbox.path}/x.bin');
      await victim.writeAsBytes([1]);
      final receipt = await quarantine.store(victim.path, module: 'test');

      File('${quarantine.root.path}/manifest/${receipt.id}.json')
          .writeAsStringSync('{ this is not json');

      // Must not throw; the unreadable manifest is reported as skipped.
      final items = await quarantine.list();
      expect(items, isEmpty);
      expect(File(receipt.storedPath).existsSync(), isTrue,
          reason: 'the payload itself must survive');
    });
  });

  group('SafeDelete — verdict gate', () {
    final future = DateTime.utc(2026, 10, 16, 12);
    late SafeDelete safeDelete;

    setUp(() {
      safeDelete = SafeDelete(
        quarantine: quarantine,
        clock: () => future,
        privilegeProbe: () async => false,
      );
    });

    File aged(String name, {int days = 30, int size = 1024}) {
      final f = File('${sandbox.path}/$name');
      f.parent.createSync(recursive: true);
      f.writeAsBytesSync(List<int>.filled(size, 1));
      f.setLastModifiedSync(future.subtract(Duration(days: days)));
      return f;
    }

    test('allows an old junk file inside a declared cache root', () async {
      final f = aged('cache-root/junk.tmp');
      final verdict = await safeDelete.evaluate(
        f.path,
        allowedRoots: ['${sandbox.path}/cache-root'],
        minAge: const Duration(days: 7),
      );
      expect(verdict.isAllowed, isTrue, reason: verdict.reason);
    });

    test('refuses anything outside the declared roots', () async {
      final f = aged('somewhere-else/junk.tmp');
      final verdict = await safeDelete.evaluate(
        f.path,
        allowedRoots: ['${sandbox.path}/cache-root'],
        minAge: const Duration(days: 7),
      );
      expect(verdict.isAllowed, isFalse);
      expect(verdict.code, VerdictCode.outsideRoots);
    });

    test('refuses protected paths even when the root declares them', () async {
      final f = aged('cache-root/secrets.db');
      final verdict = await safeDelete.evaluate(
        f.path,
        allowedRoots: ['${sandbox.path}/cache-root'],
        minAge: const Duration(days: 7),
      );
      expect(verdict.isAllowed, isFalse);
      expect(verdict.code, VerdictCode.protected);
    });

    test('refuses files that are too young (live session data)', () async {
      final f = aged('cache-root/hot.tmp', days: 0);
      final verdict = await safeDelete.evaluate(
        f.path,
        allowedRoots: ['${sandbox.path}/cache-root'],
        minAge: const Duration(days: 7),
      );
      expect(verdict.isAllowed, isFalse);
      expect(verdict.code, VerdictCode.tooYoung);
    });

    test('never follows symlinks out of the sandbox', () async {
      final target = File('${sandbox.path}/precious.txt');
      await target.writeAsString('do not touch');
      final linkDir = Directory('${sandbox.path}/cache-root')
        ..createSync(recursive: true);
      final link = Link('${linkDir.path}/escape');
      await link.create(target.path);

      final verdict = await safeDelete.evaluate(
        link.path,
        allowedRoots: ['${sandbox.path}/cache-root'],
        minAge: const Duration(days: 0),
        followLinks: false,
      );
      expect(verdict.isAllowed, isFalse);
      expect(verdict.code, VerdictCode.symlink);
      expect(target.readAsStringSync(), 'do not touch');
    });

    test('quarantineAll skips unsafe entries but still cleans the safe ones',
        () async {
      final good = aged('cache-root/good.tmp');
      final young = aged('cache-root/young.tmp', days: 0);
      final db = aged('cache-root/keep.db');

      final outcome = await safeDelete.quarantineAll(
        [good.path, young.path, db.path],
        allowedRoots: ['${sandbox.path}/cache-root'],
        minAge: const Duration(days: 7),
        module: 'cache',
      );

      expect(outcome.cleaned, hasLength(1));
      expect(outcome.cleaned.single, good.path);
      expect(good.existsSync(), isFalse);
      expect(young.existsSync(), isTrue, reason: 'young file must survive');
      expect(db.existsSync(), isTrue, reason: 'database must survive');
      expect(outcome.bytesFreed, 1024);
      expect(outcome.skipped, hasLength(2));
    });
  });

  group('formatBytes', () {
    test('uses western units for English', () {
      expect(formatBytes(1024, unitSystem: 'en'), '1.0 KB');
      expect(formatBytes(1536, unitSystem: 'en'), '1.5 KB');
      expect(formatBytes(1048576, unitSystem: 'en'), '1.0 MB');
      expect(formatBytes(1073741824, unitSystem: 'en'), '1.0 GB');
    });

    test('uses Arabic abbreviations and keeps western digits', () {
      expect(formatBytes(1048576, unitSystem: 'ar'), '1.0 م.ب');
      expect(formatBytes(1073741824, unitSystem: 'ar'), '1.0 ج.ب');
      expect(formatBytes(999, unitSystem: 'ar'), '999 ب');
    });

    test('handles zero and negative safely', () {
      expect(formatBytes(0, unitSystem: 'en'), '0 B');
      expect(formatBytes(-5, unitSystem: 'en'), '0 B');
    });
  });
}
