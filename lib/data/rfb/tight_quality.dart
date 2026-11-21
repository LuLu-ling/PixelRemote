import 'dart:math';

import '../../domain/entities/stream_settings.dart';
import 'rfb_wire.dart';

/// Tight/JPEG parameters requested from the server. Fine-grained quality and
/// chroma subsampling are TigerVNC/TurboVNC extensions; other servers ignore
/// them and use the classic 0–9 [level].
final class TightQuality {
  const TightQuality._(this.jpeg, this.subsampling, this.compression);

  /// JPEG quality: lower trades detail in photos and video for bandwidth.
  /// Above 85 chroma is kept at full resolution; below 70 it's quartered.
  factory TightQuality.jpeg(int quality) => TightQuality._(
        quality,
        quality < 70 ? Encoding.subsamp420 : (quality < 85 ? Encoding.subsamp422 : Encoding.subsampNone),
        quality <= 25 ? 9 : 6,
      );

  static const lossless = TightQuality._(null, Encoding.subsampNone, 6);

  static TightQuality preset(ImageQuality q) => switch (q) {
        ImageQuality.auto => TightQuality.jpeg(QualityGovernor.steps[QualityGovernor.initialStep]),
        ImageQuality.low => TightQuality.jpeg(10),
        ImageQuality.balanced => TightQuality.jpeg(50),
        ImageQuality.high => TightQuality.jpeg(85),
        ImageQuality.lossless => lossless,
      };

  /// 1–100, or null for lossless (no JPEG at all).
  final int? jpeg;
  final int subsampling;

  /// zlib effort 0–9 for the lossless parts (text, UI).
  final int compression;

  int get level => ((jpeg ?? 0) / 11).round().clamp(0, 9);

  List<int> get pseudoEncodings => [
        if (jpeg case final q?) ...[Encoding.jpegQuality(level), Encoding.fineQuality(q), subsampling],
        Encoding.compressLevel(compression),
      ];

  String describe() => jpeg == null
      ? 'lossless, zlib $compression'
      : 'JPEG quality $jpeg (level $level), ${Encoding.name(subsampling)}, zlib $compression';
}

/// Auto quality: lowers JPEG quality while the link is saturated and the frame
/// rate misses its target, and raises it again after sustained headroom.
final class QualityGovernor {
  static const steps = [5, 10, 15, 25, 35, 50, 65, 80, 90];
  static const initialStep = 4;

  int _step = initialStep, _headroom = 0, _cooldown = 0;

  int get quality => steps[_step];

  /// Feeds one ~1 s sample; returns whether [quality] changed.
  ///
  /// [busy] is the share of the window spent receiving updates or held back
  /// by the bandwidth cap; [jpegShare] is the share of bytes that were JPEG,
  /// since quality only shrinks those.
  bool sample({required double fps, required int targetFps, required double busy, required double jpegShare}) {
    if (_cooldown > 0) {
      _cooldown--;
      return false;
    }
    if (busy > 0.75 && fps < targetFps * 0.9 && jpegShare >= 0.1 && _step > 0) {
      _step = max(0, _step - (fps < targetFps * 0.5 ? 2 : 1));
      _headroom = 0;
      _cooldown = 1;
      return true;
    }
    _headroom = busy < 0.4 && fps > 0 ? _headroom + 1 : 0;
    if (_headroom >= 3 && _step < steps.length - 1) {
      _step++;
      _headroom = 0;
      _cooldown = 1;
      return true;
    }
    return false;
  }
}
