import 'dart:convert';
import 'dart:math' as math;

/// What `apt-get -s autoremove` says it would do, without touching anything.
class AptSimulatePlan {
  AptSimulatePlan({
    required this.packages,
    required this.toRemove,
    required this.notUpgraded,
  });

  /// Packages apt proposes to remove, de-duplicated and in the order apt listed
  /// them.
  final List<String> packages;

  /// The `N to remove` figure from apt's summary line.
  final int toRemove;

  /// The `N not upgraded` figure — useful context for the UI.
  final int notUpgraded;

  bool get isEmpty => packages.isEmpty || toRemove == 0;

  int get count => packages.length;
}

final _removeBlock = RegExp(
  r'The following packages will be REMOVED:\s*\n((?:\s+\S.*\n?)+)',
);
final _remvLine = RegExp(r'^\s*Remv\s+(\S+)');
final _summary = RegExp(
  r'^(\d+)\s+upgraded,\s*(\d+)\s+newly installed,\s*(\d+)\s+to remove and\s*(\d+)\s+not upgraded',
  multiLine: true,
);

/// Parses `apt-get -s autoremove` / `apt-get -s remove` output.
///
/// The indented block after `The following packages will be REMOVED:` and the
/// later `Remv <pkg> [version]` restatements name the same packages, so both are
/// harvested and merged. Anything that is not a recognisable plan — an `E:`
/// banner, a lock message, empty output — yields an empty plan instead of an
/// exception, because the caller is a UI that must keep working.
AptSimulatePlan parseAptSimulate(String output) {
  if (output.trim().isEmpty) {
    return AptSimulatePlan(packages: const <String>[], toRemove: 0, notUpgraded: 0);
  }

  final packages = <String>[];
  final seen = <String>{};

  void add(String name) {
    if (name.isEmpty) return;
    if (seen.add(name)) packages.add(name);
  }

  final block = _removeBlock.firstMatch(output);
  if (block != null) {
    for (final line in const LineSplitter().convert(block.group(1) ?? '')) {
      final trimmed = line.trim();
      if (trimmed.isEmpty) continue;
      for (final token in trimmed.split(RegExp(r'\s+'))) {
        add(token);
      }
    }
  }

  for (final line in const LineSplitter().convert(output)) {
    final match = _remvLine.firstMatch(line);
    if (match != null) add(match.group(1)!);
  }

  final summary = _summary.firstMatch(output);
  return AptSimulatePlan(
    packages: packages,
    toRemove: summary != null
        ? int.tryParse(summary.group(3)!) ?? packages.length
        : packages.length,
    notUpgraded: summary != null ? int.tryParse(summary.group(4)!) ?? 0 : 0,
  );
}

final _journalTakeUp = RegExp(r'take\s+up\s+([0-9]+(?:\.[0-9]+)?)\s*([BKMGTPE])?');

const _journalUnits = <String, int>{
  '': 1,
  'B': 1,
  'K': 1024,
  'M': 1024 * 1024,
  'G': 1024 * 1024 * 1024,
  'T': 1024 * 1024 * 1024 * 1024,
  'P': 1024 * 1024 * 1024 * 1024 * 1024,
  'E': 1024 * 1024 * 1024 * 1024 * 1024 * 1024,
};

/// Reads the byte figure out of `journalctl --disk-usage`.
///
/// Real output: `Archived and active journals take up 76.6M in the file system.`
/// Returns 0 when the sentence is absent (no journal at all), never throws.
int parseJournalDiskUsage(String output) {
  final match = _journalTakeUp.firstMatch(output);
  if (match == null) return 0;
  final value = double.tryParse(match.group(1)!);
  if (value == null) return 0;
  final unit = (match.group(2) ?? '').toUpperCase();
  final factor = _journalUnits[unit] ?? 1;
  return math.max(0, (value * factor).round());
}