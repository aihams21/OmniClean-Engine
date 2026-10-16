import 'package:flutter/foundation.dart';

import '../../core/util/logger.dart';
import '../../engine/shell.dart';
import '../../engine/boost/boost_plan.dart';
import '../../engine/platform/storage_gateway.dart';

/// What one boost step actually returned, in the platform's own words.
@immutable
class BoostActionResult {
  const BoostActionResult({
    required this.id,
    required this.ok,
    this.detail = '',
  });

  final String id;
  final bool ok;

  /// Short, honest text: the governor name the kernel reports back, the error
  /// the shell printed, or the platform's own summary. Never invented.
  final String detail;
}

/// Runs a plan and answers with one result per step.
typedef BoostExecutor = Future<Map<String, BoostActionResult>> Function(
  List<BoostAction> actions,
);

enum BoostPhase { idle, running, done, failed }

/// Drives the one-tap Boost screen.
///
/// The controller holds no system logic: the plan is data and the executor
/// does the work, so the whole feature can be tested without a phone, without
/// root and without waiting for a shell. That split is also what keeps the
/// honest part honest — a step that fails is recorded as failed and shown.
class BoostController extends ChangeNotifier {
  BoostController({
    required List<BoostAction> plan,
    required BoostExecutor executor,
  })  : _plan = List<BoostAction>.unmodifiable(plan),
        _executor = executor;

  final List<BoostAction> _plan;
  final BoostExecutor _executor;

  BoostPhase _phase = BoostPhase.idle;
  Map<String, BoostActionResult> _results = const <String, BoostActionResult>{};
  int _progressDone = 0;

  List<BoostAction> get actions => _plan;
  BoostPhase get phase => _phase;
  Map<String, BoostActionResult> get results => _results;
  int get progressDone => _progressDone;
  int get progressTotal => _plan.length;
  bool get isBusy => _phase == BoostPhase.running;

  /// False when the platform has nothing to offer, which is a *fact* the UI
  /// shows rather than a run that comes back empty and pretends to have worked.
  bool get canRun => _plan.isNotEmpty && !isBusy;

  int get succeededCount =>
      _results.values.where((BoostActionResult r) => r.ok).length;
  int get failedCount => _results.length - succeededCount;
  bool get didAnything => succeededCount > 0;

  BoostActionResult? resultFor(String id) => _results[id];

  /// Runs every step in order. Never throws: a shell that cannot start, a
  /// platform that refuses, an executor that explodes — all of them land in
  /// [BoostPhase.failed] with the previous screen still usable.
  Future<void> run() async {
    if (!canRun) return;

    _phase = BoostPhase.running;
    _results = const <String, BoostActionResult>{};
    _progressDone = 0;
    notifyListeners();

    Map<String, BoostActionResult> raw;
    try {
      raw = await _executor(_plan);
    } catch (error) {
      log.error('boost: run failed — $error');
      _phase = BoostPhase.failed;
      _progressDone = 0;
      notifyListeners();
      return;
    }

    // A step the executor forgot to answer for is a failure, not a silence:
    // the plan promised the user this work and it did not happen.
    _results = <String, BoostActionResult>{
      for (final BoostAction action in _plan)
        action.id: raw[action.id] ??
            BoostActionResult(
              id: action.id,
              ok: false,
              detail: 'the platform returned no answer for this step',
            ),
    };
    _progressDone = _plan.length;
    _phase = BoostPhase.done;
    notifyListeners();
  }

  /// Forgets the last run so the button invites another.
  void reset() {
    _results = const <String, BoostActionResult>{};
    _progressDone = 0;
    _phase = BoostPhase.idle;
    notifyListeners();
  }
}

/// The real executor: shell scripts on desktop, the native bridge on Android.
class PlatformBoostExecutor {
  PlatformBoostExecutor({StorageGateway? gateway}) : _gateway = gateway;

  final StorageGateway? _gateway;

  Future<Map<String, BoostActionResult>> run(List<BoostAction> actions) async {
    final Map<String, BoostActionResult> out = <String, BoostActionResult>{};
    for (final BoostAction action in actions) {
      if (action.script.isEmpty) {
        out[action.id] = await _native(action);
        continue;
      }
      out[action.id] = await _shell(action);
    }
    return out;
  }

  Future<BoostActionResult> _native(BoostAction action) async {
    final StorageGateway? gateway = _gateway;
    if (gateway == null) {
      return BoostActionResult(
        id: action.id,
        ok: false,
        detail: 'this platform needs the native storage bridge',
      );
    }
    try {
      final BoostReport report = await gateway.boost();
      if (report.unavailableReason.isNotEmpty) {
        return BoostActionResult(
          id: action.id,
          ok: false,
          detail: report.unavailableReason,
        );
      }
      final List<String> lines = <String>[
        ...report.actions,
        if (report.memoryReclaimedBytes > 0)
          'memory reclaimed: ${report.memoryReclaimedBytes} B',
      ];
      return BoostActionResult(
        id: action.id,
        ok: report.didAnything,
        detail: lines.isEmpty ? 'nothing to reclaim' : lines.join('\n'),
      );
    } catch (error) {
      log.warn('boost: ${action.id} failed — $error');
      return BoostActionResult(id: action.id, ok: false, detail: '$error');
    }
  }

  Future<BoostActionResult> _shell(BoostAction action) async {
    try {
      final ShellResult result = await Shell.runScript(action.script);
      final String printed = result.stdout.trim().isEmpty
          ? result.stderr.trim()
          : result.stdout.trim();
      return BoostActionResult(
        id: action.id,
        ok: result.ok,
        detail: printed.isEmpty
            ? (result.timedOut ? 'timed out' : 'exit ${result.exitCode}')
            : printed,
      );
    } catch (error) {
      log.warn('boost: ${action.id} failed — $error');
      return BoostActionResult(id: action.id, ok: false, detail: '$error');
    }
  }
}
