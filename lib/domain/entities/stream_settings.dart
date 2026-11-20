/// Lossy presets map onto Tight JPEG quality (0–9) and zlib effort (0–9).
enum ImageQuality {
  low(jpeg: 1, compression: 9),
  balanced(jpeg: 5, compression: 6),
  high(jpeg: 8, compression: 2),
  lossless(jpeg: null, compression: 1);

  const ImageQuality({required this.jpeg, required this.compression});

  /// `null` disables JPEG entirely (pixel-exact output).
  final int? jpeg;
  final int compression;
}

enum ColorDepth {
  full(24),
  high(16),
  low(8);

  const ColorDepth(this.bits);
  final int bits;
}

/// Remote framebuffer size. Two sentinels: [native] leaves the server alone,
/// [matchWindow] follows the local window.
final class Resolution {
  const Resolution(this.width, this.height);

  static const native = Resolution(0, 0);
  static const matchWindow = Resolution(-1, -1);
  static const presets = [
    native,
    matchWindow,
    Resolution(3840, 2160),
    Resolution(2560, 1440),
    Resolution(1920, 1080),
    Resolution(1600, 900),
    Resolution(1366, 768),
    Resolution(1280, 720),
  ];

  final int width;
  final int height;

  bool get isNative => width == 0;
  bool get isMatchWindow => width < 0;
  bool get isFixed => width > 0;

  String encode() => isNative ? 'native' : isMatchWindow ? 'window' : '${width}x$height';

  static Resolution decode(String? s) {
    if (s == 'window') return matchWindow;
    final parts = s?.split('x');
    if (parts == null || parts.length != 2) return native;
    final w = int.tryParse(parts[0]), h = int.tryParse(parts[1]);
    return w != null && h != null && w > 0 && h > 0 ? Resolution(w, h) : native;
  }

  @override
  bool operator ==(Object other) => other is Resolution && other.width == width && other.height == height;

  @override
  int get hashCode => Object.hash(width, height);

  @override
  String toString() => '$width×$height';
}

/// Everything the viewer can tune about the video stream, all of which can be
/// changed while a session is live.
final class StreamSettings {
  const StreamSettings({
    this.quality = ImageQuality.balanced,
    this.colorDepth = ColorDepth.full,
    this.frameRate = 60,
    this.resolution = Resolution.native,
    this.maxBandwidthMbps = 0,
  });

  static const frameRates = [15, 30, 60, 75, 90, 120, 144, 165];

  /// Mbps; 0 means unlimited.
  static const bandwidthLimits = [0, 100, 50, 20, 10, 5, 2, 1];

  final ImageQuality quality;
  final ColorDepth colorDepth;
  final int frameRate;
  final Resolution resolution;
  final int maxBandwidthMbps;

  StreamSettings copyWith({
    ImageQuality? quality,
    ColorDepth? colorDepth,
    int? frameRate,
    Resolution? resolution,
    int? maxBandwidthMbps,
  }) =>
      StreamSettings(
        quality: quality ?? this.quality,
        colorDepth: colorDepth ?? this.colorDepth,
        frameRate: frameRate ?? this.frameRate,
        resolution: resolution ?? this.resolution,
        maxBandwidthMbps: maxBandwidthMbps ?? this.maxBandwidthMbps,
      );

  Map<String, Object?> toJson() => {
        'quality': quality.name,
        'colorDepth': colorDepth.name,
        'frameRate': frameRate,
        'resolution': resolution.encode(),
        'maxBandwidthMbps': maxBandwidthMbps,
      };

  factory StreamSettings.fromJson(Map<String, Object?> j) {
    final fps = j['frameRate'] as int?;
    return StreamSettings(
      quality: ImageQuality.values.asNameMap()[j['quality']] ?? ImageQuality.balanced,
      colorDepth: ColorDepth.values.asNameMap()[j['colorDepth']] ?? ColorDepth.full,
      frameRate: frameRates.contains(fps) ? fps! : 60,
      resolution: Resolution.decode(j['resolution'] as String?),
      maxBandwidthMbps: j['maxBandwidthMbps'] as int? ?? 0,
    );
  }

  @override
  bool operator ==(Object other) =>
      other is StreamSettings &&
      other.quality == quality &&
      other.colorDepth == colorDepth &&
      other.frameRate == frameRate &&
      other.resolution == resolution &&
      other.maxBandwidthMbps == maxBandwidthMbps;

  @override
  int get hashCode => Object.hash(quality, colorDepth, frameRate, resolution, maxBandwidthMbps);
}
