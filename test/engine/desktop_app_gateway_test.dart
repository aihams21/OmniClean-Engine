import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:omni_clean_engine/engine/platform/desktop_app_gateway.dart';
import 'package:omni_clean_engine/engine/platform/desktop_apps.dart';
import 'package:omni_clean_engine/engine/platform/storage_gateway.dart';

void main() {
  group('DesktopApp', () {
    test('a never-recorded launch is a fact, not a guess', () {
      final app = DesktopApp(name: 'gimp.desktop', displayName: 'GIMP');
      expect(app.lastUsed, isNull);
      expect(app.idleDays(DateTime.now()), isNull);
    });

    test('idle days are counted in whole days and never go negative', () {
      final now = DateTime.utc(2026, 10, 16, 12);
      final app = DesktopApp(
        name: 'code.desktop',
        displayName: 'Code',
        lastUsed: now.subtract(const Duration(days: 40, hours: 3)),
      );
      expect(app.idleDays(now), 40);
      expect(
        DesktopApp(
                name: 'x',
                displayName: 'x',
                lastUsed: now.add(const Duration(days: 2)))
            .idleDays(now),
        0,
      );
    });

    test('a running app is running, not idle', () {
      expect(
        DesktopApp(name: 'a', displayName: 'a', workingSetBytes: 4096)
            .isRunning,
        isTrue,
      );
      expect(
        DesktopApp(name: 'a', displayName: 'a').isRunning,
        isFalse,
      );
    });

    test('a row without a name is dropped rather than invented', () {
      expect(DesktopApp.fromMap(<String, Object?>{}), isNull);
      expect(DesktopApp.fromMap(<String, Object?>{'name': ''}), isNull);
      expect(
        DesktopApp.fromMap(<String, Object?>{'name': 'a.desktop'})!.displayName,
        'a.desktop',
      );
      expect(
        DesktopApp.fromMap(<String, Object?>{
          'name': 'a.desktop',
          'displayName': 'Editor',
          'sizeBytes': 2048.0,
          'launchCount': 7,
        })!
            .sizeBytes,
        2048,
      );
    });
  });

  group('parseDesktopEntries', () {
    test('reads the entry the launcher will actually run', () {
      const raw = '\u0000'
          'Name=GIMP\n'
          'Exec=/usr/bin/gimp-2.10 %U\n'
          '\u0000'
          '[Desktop Entry]\n'
          'Name=Firefox\n'
          'Exec=/usr/lib/firefox/firefox %u\n';

      final apps = parseDesktopEntries(raw);

      expect(apps, hasLength(2));
      expect(apps.first.displayName, 'GIMP');
      expect(apps.first.name, '/usr/bin/gimp-2.10.desktop');
      expect(apps.last.displayName, 'Firefox');
    });

    test('an entry with no Exec is skipped, not half-reported', () {
      final apps = parseDesktopEntries('\u0000Name=Broken\nExec=\n\u0000');
      expect(apps, isEmpty);
    });

    test('a launch count and a last-used stamp both come through', () {
      const raw = '\u0000Name=GIMP\n'
          'Exec=/usr/bin/gimp %U\n'
          'X-OmniClean-LaunchCount=42\n'
          'X-OmniClean-LastUsed=1700000000\n';

      final app = parseDesktopEntries(raw).single;

      expect(app.launchCount, 42);
      expect(
          app.lastUsed, DateTime.fromMillisecondsSinceEpoch(1700000000 * 1000));
    });

    test('an empty input is an empty list, never a throw', () {
      expect(parseDesktopEntries(''), isEmpty);
      expect(parseDesktopEntries('\u0000\u0000\u0000'), isEmpty);
    });

    test('a front-end script reports no size rather than the interpreter size',
        () {
      // A real script on disk, not /bin/sh: the interpreter *is* the program
      // there, so reporting its size would be a lie about this app.
      final script = File('${Directory.systemTemp.path}/oc_frontend.sh')
        ..writeAsStringSync('#!/bin/sh\nexec /usr/bin/real-binary \u0024@\n');

      final app =
          parseDesktopEntries('\u0000Name=App\nExec=${script.path}\n').single;
      expect(app.sizeBytes, 0);
    });
  });

  group('DesktopAppGateway', () {
    late List<DesktopApp> catalogue;
    late List<String> uninstalled;

    DesktopAppSource sourceWith(List<DesktopApp> apps) => _FakeSource(
          apps: apps,
          uninstalled: uninstalled,
        );

    final now = DateTime.utc(2026, 10, 16, 12);

    setUp(() {
      uninstalled = <String>[];
      catalogue = <DesktopApp>[
        DesktopApp(
          name: 'gimp.desktop',
          displayName: 'GIMP',
          sizeBytes: 180 * 1024 * 1024,
          lastUsed: now.subtract(const Duration(days: 200)),
          launchCount: 3,
        ),
        DesktopApp(
          name: 'code.desktop',
          displayName: 'Code',
          sizeBytes: 300 * 1024 * 1024,
          lastUsed: now.subtract(const Duration(minutes: 20)),
          launchCount: 900,
        ),
        DesktopApp(
          name: 'never.desktop',
          displayName: 'Never Opened',
          sizeBytes: 12 * 1024 * 1024,
        ),
        DesktopApp(
          name: 'running.desktop',
          displayName: 'Running Now',
          lastUsed: now.subtract(const Duration(days: 90)),
          workingSetBytes: 64 * 1024 * 1024,
        ),
      ];
    });

    DesktopAppGateway build() => DesktopAppGateway(
          source: sourceWith(catalogue),
          clock: () => now,
          capabilities: const StorageCapabilities(
            apiLevel: 0,
            canQueryUsageStats: true,
            canUninstallApps: true,
          ),
        );

    test('reports the platform as capable of both questions', () async {
      final caps = await build().capabilities();
      expect(caps.canQueryUsageStats, isTrue);
      expect(caps.canUninstallApps, isTrue);
    });

    test('an app used today is not an unused app', () async {
      final apps = await build().unusedApps(unusedDays: 30);
      expect(
        apps.map((AppUsage a) => a.label),
        isNot(contains('Code')),
      );
    });

    test('a running app is never offered for removal', () async {
      final apps = await build().unusedApps(unusedDays: 30);
      expect(apps.map((AppUsage a) => a.label), isNot(contains('Running Now')));
    });

    test('an app the shell never recorded is reported as never opened',
        () async {
      final apps = await build().unusedApps(unusedDays: 30);
      final never = apps.firstWhere((AppUsage a) => a.label == 'Never Opened');
      expect(never.lastUsed.millisecondsSinceEpoch, 0);
      expect(never.unusedDays, 9999);
    });

    test('sizes are the platform\'s, not invented', () async {
      final apps = await build().unusedApps(unusedDays: 30);
      final gimp = apps.firstWhere((AppUsage a) => a.label == 'GIMP');
      expect(gimp.sizeBytes, 180 * 1024 * 1024);
    });

    test('an empty catalogue reports nothing rather than crashing', () async {
      final gateway =
          DesktopAppGateway(source: sourceWith(const <DesktopApp>[]));
      expect(await gateway.unusedApps(), isEmpty);
    });

    test('uninstalling hands the command to the platform source', () async {
      await build().launchUninstall('gimp.desktop');
      expect(uninstalled, <String>['gimp.desktop']);
    });

    test('a platform with no scripted uninstall refuses loudly', () async {
      final gateway = DesktopAppGateway(
        source: _RefusingSource(),
        clock: () => now,
      );
      await expectLater(
        gateway.launchUninstall('anything'),
        throwsA(isA<UnsupportedError>()),
      );
    });
  });

  group('linuxUninstallCommand', () {
    test('a Flatpak id uses flatpak, a system one uses the package manager',
        () {
      expect(linuxUninstallCommand('org.gimp.GIMP.desktop'),
          <String>['flatpak', 'uninstall', '-y', 'org.gimp.GIMP']);
      expect(linuxUninstallCommand('gimp.desktop'),
          <String>['pkexec', 'apt-get', 'remove', '--purge', 'gimp']);
      expect(linuxUninstallCommand('gimp'),
          <String>['pkexec', 'apt-get', 'remove', '--purge', 'gimp']);
    });
  });

  test('the real gateway reports a capability rather than a crash', () async {
    // No injection: this exercises the default source on the host and must not
    // throw, whatever this machine happens to have installed.
    final gateway = DesktopAppGateway();
    final caps = await gateway.capabilities();
    expect(caps.canQueryUsageStats, isTrue);
    final apps = await gateway.unusedApps();
    expect(apps, isA<List<AppUsage>>());
  });
}

class _FakeSource implements DesktopAppSource {
  _FakeSource({required this.apps, required this.uninstalled});

  @override
  List<String>? manualUninstallHint(DesktopApp app) => null;

  final List<DesktopApp> apps;
  final List<String> uninstalled;

  @override
  Future<List<DesktopApp>> installedApps() async => apps;

  @override
  List<String>? uninstallCommand(DesktopApp app) {
    uninstalled.add(app.name);
    return <String>['echo', 'removed', app.name];
  }
}

class _RefusingSource implements DesktopAppSource {
  @override
  List<String>? manualUninstallHint(DesktopApp app) => null;

  @override
  Future<List<DesktopApp>> installedApps() async => const <DesktopApp>[];

  @override
  List<String>? uninstallCommand(DesktopApp app) => null;
}
