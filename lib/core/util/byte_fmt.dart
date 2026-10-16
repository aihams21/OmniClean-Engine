/// Byte / number formatting shared by the whole UI.
///
/// `unitSystem` switches the *unit words* only — digits stay western on
/// purpose, because Arabic technical UIs overwhelmingly keep `1.0 GB`
/// readable rather than forcing Arabic-Indic numerals into a gauge label.
library;

/// Formats a byte count as a short human string.
///
/// English: `B`, `KB`, `MB`, `GB`, `TB`.
/// Arabic:  `ب`, `ك.ب`, `م.ب`, `ج.ب`, `ت.ب`.
///
/// Values below 1 KiB are printed without decimals (`999 ب`); everything
/// larger gets exactly one decimal place (`1.5 KB`).
String formatBytes(int bytes, {String unitSystem = 'en'}) {
  final arabic = unitSystem == 'ar';
  if (bytes <= 0) return arabic ? '0 ب' : '0 B';

  const enUnits = ['B', 'KB', 'MB', 'GB', 'TB', 'PB'];
  const arUnits = ['ب', 'ك.ب', 'م.ب', 'ج.ب', 'ت.ب', 'ب.ب'];
  final units = arabic ? arUnits : enUnits;

  var value = bytes.toDouble();
  var unit = 0;
  while (value >= 1024 && unit < units.length - 1) {
    value /= 1024;
    unit++;
  }

  if (unit == 0) return '${value.round()} ${units[0]}';
  return '${value.toStringAsFixed(1)} ${units[unit]}';
}

/// Same as [formatBytes] but drops the space, for tight chips.
String formatBytesTight(int bytes, {String unitSystem = 'en'}) =>
    formatBytes(bytes, unitSystem: unitSystem).replaceAll(' ', '');

/// `12 345 678` style grouping used by the storage read-outs.
String formatCount(int value, {String unitSystem = 'en'}) {
  final negative = value < 0;
  final digits = value.abs().toString();
  final buf = StringBuffer();
  for (var i = 0; i < digits.length; i++) {
    if (i > 0 && (digits.length - i) % 3 == 0) buf.write(' ');
    buf.write(digits[i]);
  }
  final sign = negative ? '−' : '';
  return unitSystem == 'ar' ? '$sign$buf' : '$sign$buf';
}

/// Percentage rendered with one decimal, clamped to `0..100`.
String formatPercent(double ratio) {
  final v = (ratio.isNaN ? 0.0 : ratio).clamp(0.0, 100.0);
  return '${(v * 100).toStringAsFixed(1)}%';
}

/// Human duration like `3d 04:12` / `4m 09s` / `12s`.
String formatDuration(Duration d, {String unitSystem = 'en'}) {
  final arabic = unitSystem == 'ar';
  if (d.inDays > 0) {
    return arabic
        ? '${d.inDays} يوم ${(d.inHours % 24).toString().padLeft(2, '0')}:${(d.inMinutes % 60).toString().padLeft(2, '0')}'
        : '${d.inDays}d ${(d.inHours % 24).toString().padLeft(2, '0')}:${(d.inMinutes % 60).toString().padLeft(2, '0')}';
  }
  if (d.inHours > 0) {
    return arabic
        ? '${d.inHours} س ${d.inMinutes % 60} د'
        : '${d.inHours}h ${d.inMinutes % 60}m';
  }
  if (d.inMinutes > 0) {
    return arabic ? '${d.inMinutes} د ${d.inSeconds % 60} ث' : '${d.inMinutes}m ${d.inSeconds % 60}s';
  }
  return arabic ? '${d.inSeconds} ث' : '${d.inSeconds}s';
}