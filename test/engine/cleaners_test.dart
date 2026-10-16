import 'package:flutter_test/flutter_test.dart';
import 'package:omni_clean_engine/engine/cleaners/cleaners.dart';

const _autoremoveOutput = '''
NOTE: This is only a simulation!
      apt-get needs root privileges for real execution.
Reading package lists...
Building dependency tree...
Reading state information...
Solving dependencies...
The following packages will be REMOVED:
  linux-binary-7.0.12+kali-amd64 linux-modules-7.0.12+kali-amd64
0 upgraded, 0 newly installed, 2 to remove and 838 not upgraded.
Remv linux-binary-7.0.12+kali-amd64 [7.0.12-2kali1]
Remv linux-modules-7.0.12+kali-amd64 [7.0.12-2kali1]
''';

void main() {
  group('parseAptSimulate', () {
    test('collects the packages apt proposes to remove', () {
      final plan = parseAptSimulate(_autoremoveOutput);
      expect(plan.packages, contains('linux-binary-7.0.12+kali-amd64'));
      expect(plan.packages, contains('linux-modules-7.0.12+kali-amd64'));
      expect(plan.packages, hasLength(2));
    });

    test('does not count the "Remv" restatement twice', () {
      expect(parseAptSimulate(_autoremoveOutput).packages, hasLength(2));
    });

    test('reads the remove/upgrade counts from the summary line', () {
      final plan = parseAptSimulate(_autoremoveOutput);
      expect(plan.toRemove, 2);
      expect(plan.notUpgraded, 838);
    });

    test('an empty simulate means nothing to remove', () {
      const clean = '0 upgraded, 0 newly installed, 0 to remove and 0 not upgraded.';
      final plan = parseAptSimulate(clean);
      expect(plan.packages, isEmpty);
      expect(plan.toRemove, 0);
      expect(plan.isEmpty, isTrue);
    });

    test('survives an error banner instead of throwing', () {
      expect(parseAptSimulate('E: Unable to acquire the dpkg lock').isEmpty, isTrue);
      expect(parseAptSimulate('').isEmpty, isTrue);
    });

    test('handles a wrapped package list', () {
      const wrapped = '''
The following packages will be REMOVED:
  a-pkg b-pkg
  c-pkg
2 upgraded, 3 newly installed, 3 to remove and 1 not upgraded.
''';
      expect(parseAptSimulate(wrapped).packages, ['a-pkg', 'b-pkg', 'c-pkg']);
    });
  });

  group('parseJournalDiskUsage', () {
    test('reads the real journalctl output', () {
      expect(
        parseJournalDiskUsage(
          'Archived and active journals take up 76.6M in the file system.',
        ),
        (76.6 * 1024 * 1024).round(),
      );
    });

    test('supports G, K and plain bytes', () {
      expect(parseJournalDiskUsage('take up 1.5G of disk.'), 1610612736);
      expect(parseJournalDiskUsage('take up 512K.'), 524288);
      expect(parseJournalDiskUsage('take up 1024B.'), 1024);
    });

    test('returns zero when the line is unrecognisable', () {
      expect(parseJournalDiskUsage('no journals found'), 0);
      expect(parseJournalDiskUsage(''), 0);
    });
  });

  group('LinuxCleaner targets', () {
    final targets = LinuxCleaner.targets.targets;

    test('every target has roots and a unique id', () {
      final ids = <String>{};
      for (final target in targets) {
        expect(target.id, isNotEmpty, reason: 'id must be set');
        expect(ids.add(target.id), isTrue, reason: 'duplicate ${target.id}');
        expect(target.roots, isNotEmpty, reason: '${target.id} has no roots');
      }
      expect(LinuxCleaner.targets.count, targets.length);
    });

    test('covers the four areas the brief asks for', () {
      final categories = targets.map((t) => t.category).toSet();
      expect(categories, containsAll(<CleanCategory>[
        CleanCategory.packageCache,
        CleanCategory.temp,
        CleanCategory.logs,
        CleanCategory.appCache,
      ]));
    });

    test('apt and the system journal are marked as needing root', () {
      final privileged = targets
          .where((t) => t.id.startsWith('linux_apt') || t.id == 'linux_journal');
      expect(privileged, isNotEmpty);
      for (final target in privileged) {
        expect(target.requiresPrivilege, isTrue, reason: target.id);
        expect(target.risk, isNot(RiskLevel.safe), reason: target.id);
      }
    });

    test('the per-user journal needs no root at all', () {
      final user = targets.firstWhere((t) => t.id == 'linux_user_journal');
      expect(user.requiresPrivilege, isFalse);
      expect(user.risk, RiskLevel.safe);
    });

    test('the home cache is safe to clean without asking', () {
      final home = targets.firstWhere((t) => t.id == 'linux_home_cache');
      expect(home.requiresPrivilege, isFalse);
      expect(home.risk, RiskLevel.safe);
      expect(home.roots.first, contains('.cache'));
    });

    test('every target protects fresh files for at least an hour', () {
      for (final target in targets) {
        expect(target.minAge, greaterThan(Duration.zero), reason: target.id);
      }
    });
  });

  group('WindowsCleaner targets', () {
    final targets = WindowsCleaner.targets.targets;

    test('has unique ids and roots', () {
      final ids = <String>{};
      for (final target in targets) {
        expect(ids.add(target.id), isTrue, reason: 'duplicate ${target.id}');
        expect(target.roots, isNotEmpty, reason: target.id);
      }
    });

    test('every root is absolute and environment variables are expanded', () {
      for (final target in targets) {
        for (final root in target.roots) {
          final resolved = resolveWindowsRoot(root, environment: {
            'LOCALAPPDATA': r'C:\Users\hamza\AppData\Local',
            'WINDIR': r'C:\Windows',
            'SystemDrive': 'C:',
            'TEMP': r'C:\Users\hamza\AppData\Local\Temp',
          });
          expect(resolved, startsWith('C:'), reason: '$root -> $resolved');
        }
      }
    });

    test('covers temp, browser caches, logs and windows update leftovers', () {
      final categories = targets.map((t) => t.category).toSet();
      expect(categories, containsAll(<CleanCategory>[
        CleanCategory.temp,
        CleanCategory.browser,
        CleanCategory.logs,
        CleanCategory.updates,
        CleanCategory.dumps,
      ]));
    });
  });

  group('AndroidCleaner junk rules', () {
    test('flags interrupted downloads', () {
      expect(classifyJunkName('movie.part'), JunkKind.partialDownload);
      expect(classifyJunkName('setup.crdownload'), JunkKind.partialDownload);
      expect(classifyJunkName('apk.opdownload'), JunkKind.partialDownload);
      expect(classifyJunkName('.download'), JunkKind.partialDownload);
      expect(classifyJunkName('report.pdf'), isNull);
    });

    test('flags installer leftovers', () {
      expect(classifyJunkName('app.apk'), JunkKind.installer);
      expect(classifyJunkName('update.apk.tmp'), JunkKind.installer);
      expect(classifyJunkName('thumbs.db'), isNull);
    });

    test('flags temp by name but requires a real age check', () {
      expect(classifyJunkName('cache_1.tmp'), JunkKind.temp);
      expect(classifyJunkName('notes.txt'), isNull);
    });

    test('never flags anything a user may still need', () {
      for (final name in <String>[
        'holiday.jpg',
        'receipt.pdf',
        'notes.txt',
        'song.mp3',
        'db.sqlite',
      ]) {
        expect(classifyJunkName(name), isNull, reason: name);
      }
    });

    test('an obsolete apk is junk only when a newer copy exists', () {
      final byName = <String, int>{
        'app-release-1.0.apk': 100,
        'app-release-1.1.apk': 120,
      };
      expect(
        obsoleteApks(byName, currentPackageName: 'app-release-1.1.apk'),
        ['app-release-1.0.apk'],
      );
      expect(
        obsoleteApks(byName, currentPackageName: 'app-release-1.0.apk'),
        ['app-release-1.1.apk'],
      );
      expect(obsoleteApks(byName, currentPackageName: null), isEmpty);
    });

    test('an empty folder is junk only when nothing is left in it', () {
      expect(isEmptyDirectoryListing(const <String>[]), isTrue);
      expect(isEmptyDirectoryListing(const <String>['.nomedia']), isTrue);
      expect(isEmptyDirectoryListing(const <String>['a.txt']), isFalse);
    });
  });

  group('AndroidCleaner targets', () {
    final targets = AndroidCleaner.targets.targets;

    test('has unique ids and roots', () {
      final ids = <String>{};
      for (final target in targets) {
        expect(ids.add(target.id), isTrue, reason: 'duplicate ${target.id}');
        expect(target.roots, isNotEmpty, reason: target.id);
      }
    });

    test('the root sweep is the only thing needing su', () {
      final needsRoot = targets.where((t) => t.requiresPrivilege);
      expect(needsRoot.map((t) => t.id), ['android_app_cache_root']);
      expect(needsRoot.first.risk, RiskLevel.elevated);
    });
  });
}