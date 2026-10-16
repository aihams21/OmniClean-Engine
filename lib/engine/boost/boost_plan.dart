import 'package:flutter/foundation.dart';

/// What a single boost step is *for*. The UI groups and explains by impact,
/// because "we set the CPU governor to performance" means nothing to someone
/// who has never heard of a governor, while "lower frame-time stutter" does.
enum BoostImpact { frames, memory, latency, storage }

/// One concrete thing the app will do when the user taps Boost.
///
/// This is a *description*, not an action: nothing here runs. Keeping the plan
/// pure and platform-derived is what makes it testable without a phone, a
/// desktop or a second of the user's time.
@immutable
class BoostAction {
  const BoostAction({
    required this.id,
    required this.titleKey,
    required this.descriptionKey,
    required this.impact,
    required this.requiresPrivilege,
    this.script = '',
  });

  /// Stable identifier, also the key the UI and the runner match on.
  final String id;

  /// ARB key for the one-line title.
  final String titleKey;

  /// ARB key for the sentence explaining what it changes.
  final String descriptionKey;

  final BoostImpact impact;

  /// True when the step needs administrator/root rights. A step that needs
  /// rights the app does not have is *not* listed rather than listed as a
  /// failure: a plan full of steps that cannot run is not a plan.
  final bool requiresPrivilege;

  /// The shell script for desktop platforms. Empty on Android, where the work
  /// happens natively behind the storage bridge.
  final String script;

  @override
  String toString() => 'BoostAction($id, impact: ${impact.name})';
}

/// The steps this platform can honestly perform.
///
/// `os` is the raw operating system string and `isRoot` the result of an actual
/// privilege probe, so the answer is always a plan the user can actually run.
List<BoostAction> boostActionsFor({required String os, required bool isRoot}) {
  final List<BoostAction> actions = <BoostAction>[];

  if (os.toLowerCase().contains('android')) {
    actions.add(const BoostAction(
      id: 'android_platform_boost',
      titleKey: 'boostActionAndroidTitle',
      descriptionKey: 'boostActionAndroidDescription',
      impact: BoostImpact.frames,
      requiresPrivilege: false,
    ));
    return actions;
  }

  if (os.toLowerCase().startsWith('win')) {
    actions.add(const BoostAction(
      id: 'windows_power_plan',
      titleKey: 'boostActionPowerPlanTitle',
      descriptionKey: 'boostActionPowerPlanDescription',
      impact: BoostImpact.frames,
      requiresPrivilege: false,
      script: 'powercfg /setactive SCHEME_MIN',
    ));
    actions.add(const BoostAction(
      id: 'windows_trim_working_sets',
      titleKey: 'boostActionWorkingSetsTitle',
      descriptionKey: 'boostActionWorkingSetsDescription',
      impact: BoostImpact.memory,
      requiresPrivilege: false,
      // A process may keep more resident than it is using. Asking Windows to
      // release the slack is a real, reversible reclaim - not a cosmetic one.
      script:
          r'''Get-Process | Where-Object { $_.WorkingSet64 -gt 64MB } | ForEach-Object { $_.MinWorkingSet = 65536 }''',
    ));
    if (isRoot) {
      actions.add(const BoostAction(
        id: 'windows_suspend_indexer',
        titleKey: 'boostActionIndexerTitle',
        descriptionKey: 'boostActionIndexerDescription',
        impact: BoostImpact.latency,
        requiresPrivilege: true,
        // The search indexer re-indexes in the background and competes for the
        // same disk and CPU a game wants. Suspending it is temporary and the
        // service resumes on the next boot or the next trigger.
        script:
            r'''Stop-Service -Name WSearch -Force -ErrorAction SilentlyContinue''',
      ));
    }
    return actions;
  }

  // Linux and every other unix.
  if (isRoot) {
    actions.add(const BoostAction(
      id: 'linux_cpu_governor',
      titleKey: 'boostActionGovernorTitle',
      descriptionKey: 'boostActionGovernorDescription',
      impact: BoostImpact.frames,
      requiresPrivilege: true,
      script:
          r'''for g in /sys/devices/system/cpu/cpu*/cpufreq/scaling_governor; do
  [ -w "$g" ] && echo performance > "$g" 2>/dev/null
done; cat /sys/devices/system/cpu/cpu0/cpufreq/scaling_governor 2>/dev/null || true''',
    ));
    actions.add(const BoostAction(
      id: 'linux_swappiness',
      titleKey: 'boostActionSwappinessTitle',
      descriptionKey: 'boostActionSwappinessDescription',
      impact: BoostImpact.frames,
      requiresPrivilege: true,
      script:
          r'''echo 10 > /proc/sys/vm/swappiness 2>/dev/null && cat /proc/sys/vm/swappiness''',
    ));
    actions.add(const BoostAction(
      id: 'linux_drop_caches',
      titleKey: 'boostActionDropCachesTitle',
      descriptionKey: 'boostActionDropCachesDescription',
      impact: BoostImpact.memory,
      requiresPrivilege: true,
      script:
          r'''sync; echo 3 > /proc/sys/vm/drop_caches 2>/dev/null && echo 3''',
    ));
    actions.add(const BoostAction(
      id: 'linux_fstrim',
      titleKey: 'boostActionTrimTitle',
      descriptionKey: 'boostActionTrimDescription',
      impact: BoostImpact.storage,
      requiresPrivilege: true,
      script: 'fstrim -v / 2>&1 || true',
    ));
  }
  return actions;
}

/// Human-readable grouping order, tightest frame-time first.
const List<BoostImpact> boostImpactOrder = <BoostImpact>[
  BoostImpact.frames,
  BoostImpact.memory,
  BoostImpact.latency,
  BoostImpact.storage,
];
