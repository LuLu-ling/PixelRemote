import 'dart:async';
import 'dart:collection';

import '../domain/services/session_log.dart';

/// In-memory log of one connection attempt and the session that follows,
/// capped at [capacity] entries.
final class ConnectionLog implements SessionLog {
  ConnectionLog({this.capacity = 5000});

  final int capacity;
  final _entries = ListQueue<LogEntry>();
  final _changes = StreamController<void>.broadcast();

  List<LogEntry> get entries => List.unmodifiable(_entries);

  /// Fires whenever an entry is added.
  Stream<void> get changes => _changes.stream;

  @override
  void add(LogLevel level, String source, String message) {
    _entries.add(LogEntry(DateTime.now(), level, source, message));
    if (_entries.length > capacity) _entries.removeFirst();
    if (!_changes.isClosed) _changes.add(null);
  }

  String export() => _entries.map((e) => e.format()).join('\n');
}
