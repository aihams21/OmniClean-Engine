/// Tiny dependency-free logger.
///
/// Writes to stderr (so `flutter run` shows it without a devtools session) and
/// keeps a bounded in-memory ring buffer that the Settings screen can dump for
/// bug reports.
class Log {
  Log._();

  /// Set to false to silence stderr output in release builds.
  static bool echoToStderr = true;

  static const int _capacity = 400;
  final List<String> _buffer = <String>[];

  /// Newest-last snapshot of recent log lines (oldest first).
  List<String> get recent => List<String>.unmodifiable(_buffer);

  void _write(String level, String message) {
    final line = '${DateTime.now().toIso8601String()} [$level] $message';
    _buffer.add(line);
    if (_buffer.length > _capacity) _buffer.removeAt(0);
    if (echoToStderr) {
      // ignore: avoid_print
      print(line);
    }
  }

  void fine(String m) => _write('FINE', m);
  void info(String m) => _write('INFO', m);
  void warn(String m) => _write('WARN', m);
  void error(String m) => _write('ERR ', m);

  void clear() => _buffer.clear();
}

/// Process-wide logger instance.
final Log log = Log._();
