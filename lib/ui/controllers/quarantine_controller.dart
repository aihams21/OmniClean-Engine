import 'package:flutter/foundation.dart';

import '../../core/safety/quarantine.dart';
import '../../core/util/logger.dart';

enum QuarantinePhase { idle, loading, working, failed }

/// Drives the quarantine screen: what is held, how much space it occupies, and
/// the three things the user can do about it — restore, purge one, purge all.
///
/// Like every other controller in this app it owns no deletion logic of its
/// own; it only sequences calls into [Quarantine] and republishes the result.
class QuarantineController extends ChangeNotifier {
  QuarantineController({
    required this.quarantine,
    Duration retention = const Duration(days: 7),
    DateTime Function()? clock,
  })  : _retention = retention,
        _clock = clock ?? DateTime.now;

  final Quarantine quarantine;
  final DateTime Function() _clock;

  Duration _retention;
  List<QuarantineItem> _items = const <QuarantineItem>[];
  QuarantinePhase _phase = QuarantinePhase.idle;
  bool _disposed = false;

  /// How long a quarantined payload is offered back before [purgeExpired]
  /// is willing to remove it for good.
  Duration get retention => _retention;

  List<QuarantineItem> get items => _items;
  QuarantinePhase get phase => _phase;
  bool get isEmpty => _items.isEmpty;
  int get count => _items.length;

  int get totalBytes => _items.fold<int>(0, (sum, item) => sum + item.bytes);

  bool get isBusy =>
      _phase == QuarantinePhase.loading || _phase == QuarantinePhase.working;

  bool get hasExpired => expiredCount > 0;

  int get expiredCount {
    final cutoff = _clock().toUtc().subtract(_retention);
    return _items
        .where((item) => item.quarantinedAt.toUtc().isBefore(cutoff))
        .length;
  }

  /// Reads the manifest back. A broken manifest is a failed phase, not a crash:
  /// the rest of the app must keep working.
  Future<void> load() async {
    if (isBusy) return;
    _phase = QuarantinePhase.loading;
    notifyListeners();
    try {
      _items = await quarantine.list();
      _phase = QuarantinePhase.idle;
    } catch (error) {
      log.error('quarantine: load failed — $error');
      _items = const <QuarantineItem>[];
      _phase = QuarantinePhase.failed;
    }
    notifyListeners();
  }

  /// Puts one payload back exactly where it came from.
  Future<void> restore(String id) async {
    if (isBusy) return;
    _phase = QuarantinePhase.working;
    notifyListeners();
    try {
      await quarantine.restore(id);
      _items = await quarantine.list();
      _phase = QuarantinePhase.idle;
    } catch (error) {
      log.error('quarantine: restore $id failed — $error');
      _phase = QuarantinePhase.failed;
    }
    notifyListeners();
  }

  /// Destroys one payload for good. This is the only irreversible action in the
  /// app, and the UI must confirm it before calling.
  Future<void> purge(String id) async {
    if (isBusy) return;
    _phase = QuarantinePhase.working;
    notifyListeners();
    try {
      await quarantine.purgeItem(id);
      _items = await quarantine.list();
      _phase = QuarantinePhase.idle;
    } catch (error) {
      log.error('quarantine: purge $id failed — $error');
      _phase = QuarantinePhase.failed;
    }
    notifyListeners();
  }

  /// Destroys everything that is past the retention window.
  Future<void> purgeExpired() async {
    if (isBusy) return;
    _phase = QuarantinePhase.working;
    notifyListeners();
    try {
      await quarantine.purgeOlderThan(_retention);
      _items = await quarantine.list();
      _phase = QuarantinePhase.idle;
    } catch (error) {
      log.error('quarantine: purge expired failed — $error');
      _phase = QuarantinePhase.failed;
    }
    notifyListeners();
  }

  Future<void> purgeAll() async {
    if (isBusy) return;
    _phase = QuarantinePhase.working;
    notifyListeners();
    try {
      await quarantine.purgeAll();
      _items = await quarantine.list();
      _phase = QuarantinePhase.idle;
    } catch (error) {
      log.error('quarantine: purge all failed — $error');
      _phase = QuarantinePhase.failed;
    }
    notifyListeners();
  }

  void setRetention(Duration value) {
    if (value <= Duration.zero || value == _retention) return;
    _retention = value;
    notifyListeners();
  }

  @override
  void dispose() {
    if (_disposed) return;
    _disposed = true;
    super.dispose();
  }
}
