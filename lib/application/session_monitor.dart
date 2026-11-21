import 'dart:async';
import 'dart:collection';
import 'dart:typed_data';

import '../domain/entities/session_stats.dart';
import '../domain/services/remote_desktop.dart';
import '../domain/services/secure_tunnel.dart';

/// Byte counters shared by every channel of one session.
final class TrafficMeter {
  int received = 0, sent = 0;
}

/// Decorator that counts bytes flowing through a [ByteChannel].
final class MeteredChannel implements ByteChannel {
  MeteredChannel(this._inner, this._meter);

  final ByteChannel _inner;
  final TrafficMeter _meter;

  @override
  late final Stream<Uint8List> input = _inner.input.map((chunk) {
    _meter.received += chunk.length;
    return chunk;
  });

  @override
  void write(List<int> bytes) {
    _meter.sent += bytes.length;
    _inner.write(bytes);
  }

  @override
  Future<void> close() => _inner.close();
}

/// Samples latency, loss, throughput and frame rate once per [period].
/// Latency comes from SSH keep-alive round trips; a probe unanswered within
/// [probeTimeout] counts as lost.
final class SessionMonitor {
  SessionMonitor({
    required this._tunnel,
    required this._traffic,
    required this._desktop,
    this.period = const Duration(seconds: 1),
    this.probeTimeout = const Duration(seconds: 2),
  });

  static const _lossWindow = 30;

  final SecureTunnel _tunnel;
  final TrafficMeter _traffic;
  final RemoteDesktopSession _desktop;
  final Duration period, probeTimeout;

  final _stats = StreamController<SessionStats>.broadcast();
  final _probes = ListQueue<bool>();
  final _clock = Stopwatch();
  StreamSubscription<void>? _frameSub;
  Timer? _timer;
  Duration? _rtt;
  String? _encoding;
  int _frames = 0, _lastRx = 0, _lastTx = 0;
  bool _running = false;

  SessionStats latest = SessionStats.empty;
  Stream<SessionStats> get stats => _stats.stream;

  void start() {
    _running = true;
    _clock.start();
    _frameSub = _desktop.frames.listen((_) => _frames++);
    _timer = Timer.periodic(period, (_) => _sample());
    unawaited(_probeLoop());
  }

  void dispose() {
    _running = false;
    _timer?.cancel();
    _frameSub?.cancel();
    _stats.close();
  }

  void _sample() {
    final seconds = _clock.elapsedMicroseconds / 1e6;
    _clock.reset();
    final lost = _probes.where((ok) => !ok).length;
    final usage = _desktop.takeEncodingStats()..remove('CopyRect');
    if (usage.isNotEmpty) _encoding = usage.entries.reduce((a, b) => a.value >= b.value ? a : b).key;
    latest = SessionStats(
      rtt: _rtt,
      lossPercent: _probes.isEmpty ? 0 : lost * 100 / _probes.length,
      rxBitsPerSecond: (_traffic.received - _lastRx) * 8 / seconds,
      txBitsPerSecond: (_traffic.sent - _lastTx) * 8 / seconds,
      fps: _frames / seconds,
      width: _desktop.frame.width,
      height: _desktop.frame.height,
      encoding: _encoding,
    );
    _frames = 0;
    _lastRx = _traffic.received;
    _lastTx = _traffic.sent;
    if (!_stats.isClosed) _stats.add(latest);
  }

  Future<void> _probeLoop() async {
    while (_running) {
      final watch = Stopwatch()..start();
      try {
        _rtt = await _tunnel.ping().timeout(probeTimeout);
        _record(true);
      } catch (_) {
        _record(false);
      }
      final rest = period - watch.elapsed;
      if (rest > Duration.zero) await Future<void>.delayed(rest);
    }
  }

  void _record(bool ok) {
    _probes.add(ok);
    if (_probes.length > _lossWindow) _probes.removeFirst();
  }
}
