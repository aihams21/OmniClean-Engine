import 'dart:async';
import 'dart:io';

import 'package:omni_clean_engine/core/util/logger.dart';

/// How to obtain administrator rights when a clean target needs them.
enum Escalation { none, pkexec, sudo }

/// Picks the least surprising way to become root.
///
/// `sudo` is only ever used with `-n`, so a desktop-less CLI can never sit
/// waiting on a password prompt that nobody is there to type.
Escalation planEscalation({
  required bool isRoot,
  required bool hasPkexec,
  required bool hasSudo,
}) {
  if (isRoot) return Escalation.none;
  if (hasPkexec) return Escalation.pkexec;
  if (hasSudo) return Escalation.sudo;
  return Escalation.none;
}

/// Turns a shell [script] into an argv for the chosen escalation strategy.
List<String> buildPrivilegedCommand(String script, Escalation escalation) {
  switch (escalation) {
    case Escalation.none:
      return ['sh', '-c', script];
    case Escalation.pkexec:
      return ['pkexec', 'sh', '-c', script];
    case Escalation.sudo:
      return ['sudo', '-n', 'sh', '-c', script];
  }
}

/// The outcome of one external command.
class ShellResult {
  ShellResult({
    required this.command,
    required this.exitCode,
    required String stdout,
    required String stderr,
    required this.duration,
    this.timedOut = false,
  })  : stdout = _trim(stdout),
        stderr = _trim(stderr);

  final String command;
  final int exitCode;
  final String stdout;
  final String stderr;
  final Duration duration;
  final bool timedOut;

  /// True when the process exited zero in time.
  bool get ok => exitCode == 0 && !timedOut;

  /// One line fit to show in the UI or a log.
  String get description {
    if (timedOut) return '`$command` timed out after ${duration.inSeconds}s';
    if (ok) return stdout.isEmpty ? '`$command` succeeded' : stdout;
    final detail = stderr.isNotEmpty ? stderr : stdout;
    return '`$command` failed ($exitCode)${detail.isEmpty ? '' : ': $detail'}';
  }

  List<String> get lines => stdout.isEmpty
      ? const <String>[]
      : stdout
          .split('\n')
          .map((l) => l.trim())
          .where((l) => l.isNotEmpty)
          .toList(growable: false);
}

/// A thin, honest wrapper around external commands.
///
/// Nothing here is privileged by itself: [runPrivileged] is the only member
/// that escalates, it always asks [planEscalation] first, and when no helper
/// exists it returns a failed [ShellResult] describing why instead of throwing
/// or silently pretending the job was done.
class Shell {
  Shell._();

  static const Duration defaultTimeout = Duration(seconds: 45);

  /// Runs [executable] with [args].
  static Future<ShellResult> run(
    String executable,
    List<String> args, {
    String? workingDirectory,
    Duration timeout = defaultTimeout,
    Map<String, String>? environment,
  }) async {
    final sw = Stopwatch()..start();
    try {
      final process = await Process.start(
        executable,
        args,
        workingDirectory: workingDirectory,
        environment: environment,
      );
      final out = process.stdout.transform(const SystemEncoding().decoder).join();
      final err = process.stderr.transform(const SystemEncoding().decoder).join();

      final code = await process.exitCode.timeout(timeout, onTimeout: () {
        process.kill(ProcessSignal.sigkill);
        return -1;
      });
      sw.stop();

      final timedOut = code == -1 && sw.elapsed >= timeout;
      log.fine('exec ${[executable, ...args].join(' ')} -> $code');
      return ShellResult(
        command: [executable, ...args].join(' '),
        exitCode: timedOut ? -1 : code,
        stdout: await out,
        stderr: await err,
        duration: sw.elapsed,
        timedOut: timedOut,
      );
    } on ProcessException catch (e) {
      sw.stop();
      log.warn('exec ${executable} failed to start: ${e.message}');
      return ShellResult(
        command: executable,
        exitCode: 127,
        stdout: '',
        stderr: e.message,
        duration: sw.elapsed,
      );
    }
  }

  /// Runs [script] through `sh -c`, so pipes and redirects are available.
  static Future<ShellResult> runScript(
    String script, {
    Duration timeout = defaultTimeout,
  }) =>
      run('sh', ['-c', script], timeout: timeout);

  /// Absolute path of [executable], or null when it is not on `PATH`.
  static Future<String?> which(String executable) async {
    final result = await run(
      'sh',
      ['-c', r'command -v "$1" 2>/dev/null', '_', executable],
    );
    final path = result.stdout.trim();
    if (result.ok && path.isNotEmpty) return path;
    return null;
  }

  /// True when the current process is uid 0.
  static Future<bool> isRoot() async =>
      (await run('id', ['-u'])).stdout.trim() == '0';

  /// True when the uid can be resolved to a user name (cosmetic, best effort).
  static Future<String> currentUser() async =>
      (await run('id', ['-un'])).stdout.trim();

  /// Runs [script] as root, escalating with `pkexec` or `sudo -n` when needed.
  ///
  /// Returns a failed result — never an exception — when the process is not
  /// root and no helper is installed, so the caller can tell the user exactly
  /// what is missing instead of reporting a success that never happened.
  static Future<ShellResult> runPrivileged(
    String script, {
    bool allowPkexec = true,
    bool allowSudo = true,
    Duration timeout = defaultTimeout,
  }) async {
    final root = await isRoot();
    final escalation = planEscalation(
      isRoot: root,
      hasPkexec: allowPkexec && await which('pkexec') != null,
      hasSudo: allowSudo && await which('sudo') != null,
    );

    if (!root && escalation == Escalation.none) {
      return ShellResult(
        command: script,
        exitCode: 126,
        stdout: '',
        stderr: 'administrator rights need root: launch OmniClean as root or '
            'install pkexec/sudo',
        duration: Duration.zero,
      );
    }

    final argv = buildPrivilegedCommand(script, escalation);
    return run(argv.first, argv.skip(1).toList(), timeout: timeout);
  }

  /// Convenience: total bytes used under [path], or 0 when unreadable.
  static Future<int> directoryBytes(String path) async {
    const bytesFlag = 'du -sb -- %s 2>/dev/null | cut -f1';
    const kibFlag = 'du -sk -- %s 2>/dev/null | cut -f1';
    var result =
        await runScript(bytesFlag.replaceAll('%s', quote(path)), timeout: _duTimeout);
    // `du -sb` is GNU-only; `du -sk` is the portable fallback.
    var bytes = int.tryParse(result.stdout.trim());
    if (bytes == null) {
      result =
          await runScript(kibFlag.replaceAll('%s', quote(path)), timeout: _duTimeout);
      final kilobytes = int.tryParse(result.stdout.trim());
      bytes = kilobytes == null ? null : kilobytes * 1024;
    }
    return bytes ?? 0;
  }

  static const Duration _duTimeout = Duration(seconds: 20);

  /// Wraps [value] in POSIX single quotes so it survives `sh -c` intact.
  static String quote(String value) => "'${value.replaceAll("'", r"'\''")}'";
}

String _trim(String value) {
  var out = value;
  while (out.endsWith('\n') || out.endsWith('\r')) {
    out = out.substring(0, out.length - 1);
  }
  return out;
}