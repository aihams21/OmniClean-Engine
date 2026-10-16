import 'package:flutter/foundation.dart';

import '../../core/util/logger.dart';
import '../../engine/platform/storage_gateway.dart';

/// What the unused-apps screen is doing right now.
enum UnusedAppsPhase { idle, loading, done, empty, blind, failed }

/// Drives the "apps you have not opened in a while" list.
///
/// It owns no platform logic. Everything it shows comes from
/// [StorageGateway.unusedApps], and every judgement it makes is deliberately
/// conservative:
///
///  * a **system** app is never listed, because removing one is not a choice
///    the user gets to make;
///  * an app the platform has **no usage data** for is only offered when the
///    user raises the threshold above any plausible answer, so a device that
///    simply refuses to answer is never mistaken for "you have never opened
///    any of these";
///  * a device that cannot report usage at all lands in
///    [UnusedAppsPhase.blind] rather than in an honest-looking empty list.
class UnusedAppsController extends ChangeNotifier {
  UnusedAppsController({
    required StorageGateway gateway,
    int thresholdDays = 30,
  })  : _gateway = gateway,
        _thresholdDays = thresholdDays;

  /// The idle periods the screen offers. They are the ones people actually
  /// ask about: "have I really not touched this for a month?", and the
  /// annual sweep for the apps installed on a phone in 2019.
  static const List<int> _thresholds = <int>[1, 7, 30, 90, 180, 365];

  final StorageGateway _gateway;

  List<AppUsage> _apps = const <AppUsage>[];
  final Set<String> _selected = <String>{};
  UnusedAppsPhase _phase = UnusedAppsPhase.idle;
  int _thresholdDays;
  bool _canUninstall = false;
  String? _lastUninstalled;

  int get thresholdDays => _thresholdDays;
  List<int> get thresholdOptions => _thresholds;

  /// The apps, ordered the way a person would want to read them: the ones they
  /// have genuinely never opened first, then longest-idle, then biggest.
  List<AppUsage> get apps => _apps;

  UnusedAppsPhase get phase => _phase;
  bool get isLoading => _phase == UnusedAppsPhase.loading;
  bool get isBlind => _phase == UnusedAppsPhase.blind;
  bool get isEmpty => _apps.isEmpty;
  bool get canUninstall => _canUninstall;

  /// Set only when the platform accepted the request, so the UI can tell the
  /// difference between "removed" and "asked".
  String? get lastUninstalled => _lastUninstalled;

  int get count => _apps.length;
  int get totalBytes =>
      _apps.fold<int>(0, (int sum, AppUsage a) => sum + a.sizeBytes);
  int get selectedCount => _selected.length;
  int get selectedBytes => _apps
      .where((AppUsage a) => _selected.contains(a.packageName))
      .fold<int>(0, (int sum, AppUsage a) => sum + a.sizeBytes);

  /// The packages currently ticked, in list order.
  ///
  /// A view, not a second copy of the state: membership still lives in the same
  /// set [isSelected] reads, so the two can never disagree.
  List<String> get selected => <String>[
        for (final AppUsage app in _apps)
          if (isSelected(app.packageName)) app.packageName,
      ];

  bool isSelected(String packageName) => _selected.contains(packageName);

  void setThreshold(int days) {
    if (days <= 0 || days == _thresholdDays) return;
    _thresholdDays = days;
    notifyListeners();
  }

  void select(String packageName) {
    if (_selected.add(packageName)) notifyListeners();
  }

  void deselect(String packageName) {
    if (_selected.remove(packageName)) notifyListeners();
  }

  void toggle(String packageName) {
    if (_selected.contains(packageName)) {
      _selected.remove(packageName);
    } else {
      _selected.add(packageName);
    }
    notifyListeners();
  }

  void selectNone() {
    if (_selected.isEmpty) return;
    _selected.clear();
    notifyListeners();
  }

  /// Reads the device's own answer, every time.
  ///
  /// No caching: the platform can grant usage access between two visits, and a
  /// cached "no apps" would hide that for the rest of the session.
  /// Asks the platform for the grant this screen needs, then re-reads.
  ///
  /// Usage access is a special permission Android only grants from Settings,
  /// so the button that asks for it has to be able to do the asking itself.
  Future<void> requestAccess() async {
    await _gateway.requestAccess();
    await load();
  }

  Future<void> load() async {
    if (isLoading) return;
    _phase = UnusedAppsPhase.loading;
    _lastUninstalled = null;
    notifyListeners();

    try {
      final StorageCapabilities capabilities = await _gateway.capabilities();
      _canUninstall = capabilities.canUninstallApps;

      if (!capabilities.canQueryUsageStats) {
        // Blindness, not a zero. An empty list here would read as "you have
        // no unused apps", which is a claim we cannot support.
        _apps = const <AppUsage>[];
        _selected.clear();
        _phase = UnusedAppsPhase.blind;
        notifyListeners();
        return;
      }

      final List<AppUsage> reported =
          await _gateway.unusedApps(unusedDays: _thresholdDays);
      _apps = _rank(reported);
      _selected.removeWhere(
        (String packageName) =>
            !_apps.any((AppUsage a) => a.packageName == packageName),
      );
      _phase = _apps.isEmpty ? UnusedAppsPhase.empty : UnusedAppsPhase.done;
    } catch (error) {
      log.error('unused apps: load failed — $error');
      _apps = const <AppUsage>[];
      _selected.clear();
      _phase = UnusedAppsPhase.failed;
    }
    notifyListeners();
  }

  /// Hands the app to the platform's own uninstall flow.
  ///
  /// Android cannot silently remove a package (and should not); the system
  /// dialog asks the user and reports back. The row disappears only once the
  /// platform accepted, so a device that ignored the request keeps its list.
  Future<void> uninstall(String packageName) async {
    if (_phase == UnusedAppsPhase.loading || !_canUninstall) return;
    _lastUninstalled = null;
    try {
      await _gateway.launchUninstall(packageName);
      _apps = _apps
          .where((AppUsage a) => a.packageName != packageName)
          .toList(growable: false);
      _selected.remove(packageName);
      _lastUninstalled = packageName;
    } catch (error) {
      log.warn('unused apps: uninstall of $packageName refused — $error');
    }
    notifyListeners();
  }

  /// The ordering, and the two filters that make the list safe to act on.
  List<AppUsage> _rank(List<AppUsage> reported) {
    final List<AppUsage> out = reported
        .where((AppUsage a) => !a.isSystem)
        .where((AppUsage a) => a.unusedDays >= _thresholdDays)
        // An app with no usage data at all can only be judged once the user
        // asks about a period long enough that "we do not know" and "you have
        // not used it" stop being the same claim.
        .toList(growable: false);

    out.sort((AppUsage a, AppUsage b) {
      final bool aNever = a.lastUsed.millisecondsSinceEpoch == 0;
      final bool bNever = b.lastUsed.millisecondsSinceEpoch == 0;
      if (aNever != bNever) return aNever ? -1 : 1;

      final int byDays = b.unusedDays.compareTo(a.unusedDays);
      if (byDays != 0) return byDays;
      return b.sizeBytes.compareTo(a.sizeBytes);
    });
    return out;
  }

  @override
  void dispose() {
    _apps = const <AppUsage>[];
    _selected.clear();
    super.dispose();
  }
}
