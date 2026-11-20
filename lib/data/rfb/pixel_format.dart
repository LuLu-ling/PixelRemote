import 'dart:typed_data';

import '../../domain/entities/stream_settings.dart';

/// Little-endian true-colour pixel formats the client asks the server for.
/// Framebuffer words are 0xAABBGGRR, i.e. RGBA8888 in memory.
final class PixelFormat {
  const PixelFormat._(this.bitsPerPixel, this.depth, this.redMax, this.greenMax, this.blueMax, this.redShift,
      this.greenShift, this.blueShift);

  /// Bytes R,G,B,X in memory, identical to the framebuffer, so pixels copy straight through.
  static const rgbx = PixelFormat._(32, 24, 255, 255, 255, 0, 8, 16);
  static const rgb565 = PixelFormat._(16, 16, 31, 63, 31, 11, 5, 0);
  static const bgr233 = PixelFormat._(8, 8, 7, 7, 3, 0, 3, 6);

  static PixelFormat of(ColorDepth depth) => switch (depth) {
        ColorDepth.full => rgbx,
        ColorDepth.high => rgb565,
        ColorDepth.low => bgr233,
      };

  final int bitsPerPixel, depth, redMax, greenMax, blueMax, redShift, greenShift, blueShift;

  int get bytesPerPixel => bitsPerPixel >> 3;

  /// Size of a ZRLE CPIXEL / Tight TPIXEL: 24-bit colour travels as 3 bytes.
  int get compactSize => identical(this, rgbx) ? 3 : bytesPerPixel;

  Uint8List encode() {
    final b = ByteData(16)
      ..setUint8(0, bitsPerPixel)
      ..setUint8(1, depth)
      ..setUint8(2, 0) // little-endian
      ..setUint8(3, 1) // true colour
      ..setUint16(4, redMax)
      ..setUint16(6, greenMax)
      ..setUint16(8, blueMax)
      ..setUint8(10, redShift)
      ..setUint8(11, greenShift)
      ..setUint8(12, blueShift);
    return b.buffer.asUint8List();
  }

  /// Raw little-endian pixel value of [size] bytes at [o].
  static int raw(Uint8List b, int o, int size) => switch (size) {
        1 => b[o],
        2 => b[o] | (b[o + 1] << 8),
        3 => b[o] | (b[o + 1] << 8) | (b[o + 2] << 16),
        _ => b[o] | (b[o + 1] << 8) | (b[o + 2] << 16) | (b[o + 3] << 24),
      };

  int read(Uint8List b, int o, int size) => toWord(raw(b, o, size));

  /// Converts a raw pixel value into a framebuffer word.
  int toWord(int v) {
    if (identical(this, rgbx)) return 0xFF000000 | (v & 0xFFFFFF);
    return 0xFF000000 |
        (_scale((v >> blueShift) & blueMax, blueMax) << 16) |
        (_scale((v >> greenShift) & greenMax, greenMax) << 8) |
        _scale((v >> redShift) & redMax, redMax);
  }

  /// Converts [count] packed pixels of [size] bytes into framebuffer words.
  Uint32List words(Uint8List data, int offset, int count, int size) {
    final out = Uint32List(count);
    if (identical(this, rgbx) && size == 4) {
      out.buffer.asUint8List().setRange(0, count * 4, data, offset);
      for (var i = 0; i < count; i++) {
        out[i] |= 0xFF000000;
      }
    } else {
      for (var i = 0, o = offset; i < count; i++, o += size) {
        out[i] = read(data, o, size);
      }
    }
    return out;
  }

  static int _scale(int c, int max) => (c * 255 + (max >> 1)) ~/ max;
}
