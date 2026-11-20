/// A one-second snapshot of link and stream health.
final class SessionStats {
  const SessionStats({
    this.rtt,
    this.lossPercent = 0,
    this.rxBitsPerSecond = 0,
    this.txBitsPerSecond = 0,
    this.fps = 0,
    this.width = 0,
    this.height = 0,
  });

  static const empty = SessionStats();

  /// Round trip through the SSH connection; null until the first probe returns.
  final Duration? rtt;

  /// Share of recent probes that went unanswered within the timeout.
  final double lossPercent;
  final double rxBitsPerSecond;
  final double txBitsPerSecond;
  final double fps;
  final int width;
  final int height;
}
