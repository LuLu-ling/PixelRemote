import 'dart:math';

/// Decides when to ask for the next frame: never faster than the target frame
/// rate, and never above the bandwidth cap (token bucket with a short burst).
final class FramePacer {
  FramePacer({required int fps, required int maxMbps, Stopwatch? clock}) : _clock = clock ?? (Stopwatch()..start()) {
    configure(fps: fps, maxMbps: maxMbps);
    _tokens = _burst;
  }

  static const _burstWindowUs = 250000;

  final Stopwatch _clock;
  late int _intervalUs;
  late double _bytesPerUs;
  double _tokens = 0;
  int _lastRequestUs = 0, _lastRefillUs = 0;

  double get _burst => _bytesPerUs * _burstWindowUs;

  void configure({required int fps, required int maxMbps}) {
    _intervalUs = 1000000 ~/ max(1, fps);
    _bytesPerUs = maxMbps <= 0 ? 0 : maxMbps / 8; // Mbit/s == bit/µs, so /8 gives bytes/µs
    _tokens = min(_tokens, _burst);
  }

  void onRequest() => _lastRequestUs = _clock.elapsedMicroseconds;

  /// Accounts for a received frame of [bytes] and returns the delay before the next request.
  Duration onFrame(int bytes) {
    final now = _clock.elapsedMicroseconds;
    var waitUs = _intervalUs - (now - _lastRequestUs);
    if (_bytesPerUs > 0) {
      _tokens = min(_burst, _tokens + (now - _lastRefillUs) * _bytesPerUs) - bytes;
      if (_tokens < 0) waitUs = max(waitUs, (-_tokens / _bytesPerUs).ceil());
    }
    _lastRefillUs = now;
    return Duration(microseconds: max(0, waitUs));
  }
}
