import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:omni_clean_engine/engine/shell.dart';

void main() {
  group('Escalation planning', () {
    test('root never escalates', () {
      expect(
        planEscalation(isRoot: true, hasPkexec: true, hasSudo: true),
        Escalation.none,
      );
    });

    test('pkexec wins over sudo because it can prompt', () {
      expect(
        planEscalation(isRoot: false, hasPkexec: true, hasSudo: true),
        Escalation.pkexec,
      );
    });

    test('sudo is the fallback', () {
      expect(
        planEscalation(isRoot: false, hasPkexec: false, hasSudo: true),
        Escalation.sudo,
      );
    });

    test('nothing available means no escalation', () {
      expect(
        planEscalation(isRoot: false, hasPkexec: false, hasSudo: false),
        Escalation.none,
      );
    });
  });

  group('buildPrivilegedCommand', () {
    test('runs the script directly as root', () {
      expect(
        buildPrivilegedCommand('apt-get clean', Escalation.none),
        ['sh', '-c', 'apt-get clean'],
      );
    });

    test('wraps pkexec', () {
      expect(
        buildPrivilegedCommand('apt-get clean', Escalation.pkexec),
        ['pkexec', 'sh', '-c', 'apt-get clean'],
      );
    });

    test('uses non-interactive sudo so a CLI can never hang on a prompt',
        () {
      expect(
        buildPrivilegedCommand('apt-get clean', Escalation.sudo),
        ['sudo', '-n', 'sh', '-c', 'apt-get clean'],
      );
    });
  });

  group('ShellResult', () {
    ShellResult result(int code, [String out = '', String err = '']) =>
        ShellResult(
          command: 'id',
          exitCode: code,
          stdout: out,
          stderr: err,
          duration: Duration.zero,
        );

    test('ok only when the process exited zero', () {
      expect(result(0).ok, isTrue);
      expect(result(1, '', 'boom').ok, isFalse);
      expect(result(-9).ok, isFalse);
    });

    test('strips a trailing newline from captured output', () {
      expect(result(0, 'hello\n').stdout, 'hello');
      expect(result(0, 'hello\n\n').stdout, 'hello');
      expect(result(0, '  hi  \n').stdout, '  hi  ');
    });

    test('splits multi-line output', () {
      expect(result(0, 'a\n b \n\n').lines, ['a', 'b']);
      expect(result(0, '').lines, isEmpty);
    });

    test('a timed-out process is never ok', () {
      final timedOut = ShellResult(
        command: 'sleep',
        exitCode: -1,
        stdout: '',
        stderr: '',
        duration: const Duration(seconds: 5),
        timedOut: true,
      );
      expect(timedOut.ok, isFalse);
      expect(timedOut.description, contains('timed out'));
    });

    test('describes a failure with its stderr', () {
      expect(result(2, '', 'permission denied').description,
          contains('permission denied'));
    });
  });

  group('Shell.run', () {
    test('captures stdout of a real process', () async {
      final result = await Shell.run('echo', ['hello world']);
      expect(result.ok, isTrue);
      expect(result.exitCode, 0);
      expect(result.stdout, 'hello world');
      expect(result.duration, greaterThan(Duration.zero));
    });

    test('supports a shell pipeline through the script form', () async {
      final result = await Shell.runScript('printf "b\\na\\n" | sort');
      expect(result.ok, isTrue);
      expect(result.stdout, 'a\nb');
    });

    test('a non-zero exit is reported, not thrown', () async {
      final result = await Shell.run('sh', ['-c', 'exit 3']);
      expect(result.ok, isFalse);
      expect(result.exitCode, 3);
    });

    test('a missing executable fails without throwing', () async {
      final result = await Shell.run('omniclean-not-a-real-binary', []);
      expect(result.ok, isFalse);
      expect(result.stderr, isNotEmpty);
    });

    test('kills a process that overruns its timeout', () async {
      final result = await Shell.run('sleep', ['5'], timeout: const Duration(milliseconds: 300));
      expect(result.ok, isFalse);
      expect(result.timedOut, isTrue);
      expect(result.duration, lessThan(const Duration(seconds: 4)));
    }, timeout: const Timeout(Duration(seconds: 20)));
  });

  group('Shell.which', () {
    test('finds sh', () async {
      final found = await Shell.which('sh');
      expect(found, isNotNull);
      expect(await File(found!).exists(), isTrue);
    });

    test('returns null for something absent', () async {
      expect(await Shell.which('omniclean-not-a-real-binary'), isNull);
    });
  });

  group('Shell.whoami', () {
    test('agrees with the real uid', () async {
      final root = await Shell.isRoot();
      expect(root, (await Shell.run('id', ['-u'])).stdout.trim() == '0');
    });
  });

  group('Shell.runPrivileged', () {
    test('succeeds without escalation when the process is already root',
        () async {
      if (!await Shell.isRoot()) {
        markTestSkipped('not running as root');
        return;
      }
      final result = await Shell.runPrivileged('echo escalated');
      expect(result.ok, isTrue);
      expect(result.stdout, 'escalated');
    });

    test('degrades gracefully when no escalation helper exists', () async {
      final result = await Shell.runPrivileged(
        'echo escalated',
        allowPkexec: false,
        allowSudo: false,
      );
      if (await Shell.isRoot()) {
        expect(result.stdout, 'escalated');
      } else {
        expect(result.ok, isFalse);
        expect(
          result.description,
          anyOf(contains('pkexec'), contains('sudo'), contains('root')),
        );
      }
    });
  });
}