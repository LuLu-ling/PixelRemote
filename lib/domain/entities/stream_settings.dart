/// How much image quality to trade for bandwidth. [auto] keeps adjusting so
/// the stream can hold the target frame rate.
enum ImageQuality { auto, low, balanced, high, lossless }

enum ColorDepth {
  full(24),
  high(16),
  low(8);

  const ColorDepth(this.bits);
  final int bits;
}

/// Everything the viewer can tune about the video stream, all of which can be
/// changed while a session is live.
final class StreamSettings {
  const StreamSettings({
    this.quality = ImageQuality.auto,
    this.colorDepth = ColorDepth.full,
    this.frameRate = 60,
    this.maxBandwidthMbps = 0,
  });

  static const frameRates = [15, 30, 60, 75, 90, 120, 144, 165];

  /// Mbps; 0 means unlimited.
  static const bandwidthLimits = [0, 100, 50, 20, 10, 5, 2, 1];

  final ImageQuality quality;
  final ColorDepth colorDepth;
  final int frameRate;
  final int maxBandwidthMbps;

  StreamSettings copyWith({ImageQuality? quality, ColorDepth? colorDepth, int? frameRate, int? maxBandwidthMbps}) =>
      StreamSettings(
        quality: quality ?? this.quality,
        colorDepth: colorDepth ?? this.colorDepth,
        frameRate: frameRate ?? this.frameRate,
        maxBandwidthMbps: maxBandwidthMbps ?? this.maxBandwidthMbps,
      );

  Map<String, Object?> toJson() => {
        'quality': quality.name,
        'colorDepth': colorDepth.name,
        'frameRate': frameRate,
        'maxBandwidthMbps': maxBandwidthMbps,
      };

  factory StreamSettings.fromJson(Map<String, Object?> j) {
    final fps = j['frameRate'] as int?;
    return StreamSettings(
      quality: ImageQuality.values.asNameMap()[j['quality']] ?? ImageQuality.auto,
      colorDepth: ColorDepth.values.asNameMap()[j['colorDepth']] ?? ColorDepth.full,
      frameRate: frameRates.contains(fps) ? fps! : 60,
      maxBandwidthMbps: j['maxBandwidthMbps'] as int? ?? 0,
    );
  }

  @override
  bool operator ==(Object other) =>
      other is StreamSettings &&
      other.quality == quality &&
      other.colorDepth == colorDepth &&
      other.frameRate == frameRate &&
      other.maxBandwidthMbps == maxBandwidthMbps;

  @override
  int get hashCode => Object.hash(quality, colorDepth, frameRate, maxBandwidthMbps);
}
