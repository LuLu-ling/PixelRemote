enum LogLevel { debug, info, warning, error }

final class LogEntry {
  const LogEntry(this.time, this.level, this.source, this.message);

  final DateTime time;
  final LogLevel level;
  final String source;
  final String message;

  String format() {
    String two(int v) => v.toString().padLeft(2, '0');
    final t = '${two(time.hour)}:${two(time.minute)}:${two(time.second)}.${time.millisecond.toString().padLeft(3, '0')}';
    return '$t ${level.name.toUpperCase().padRight(7)} [$source] $message';
  }
}

/// Where every layer reports what it is doing on the current connection.
abstract interface class SessionLog {
  void add(LogLevel level, String source, String message);
}

extension SessionLogLevels on SessionLog {
  void debug(String source, String message) => add(LogLevel.debug, source, message);
  void info(String source, String message) => add(LogLevel.info, source, message);
  void warn(String source, String message) => add(LogLevel.warning, source, message);
  void error(String source, String message) => add(LogLevel.error, source, message);
}

final class NullLog implements SessionLog {
  const NullLog();

  @override
  void add(LogLevel level, String source, String message) {}
}
