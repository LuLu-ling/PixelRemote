import 'dart:typed_data';

import '../../../domain/services/remote_desktop.dart';
import '../byte_reader.dart';
import '../framebuffer.dart';
import '../pixel_format.dart';

export '../framebuffer.dart' show RfbRect;

/// Strategy for one RFB rectangle encoding. Returns a short label of what was
/// decoded (e.g. "Tight JPEG") for statistics and the connection log.
abstract interface class RectDecoder {
  Future<String> decode(ByteReader input, RfbRect r, Framebuffer fb, PixelFormat pf);
}

/// JPEG decoding is a platform capability; Tight depends only on this port.
abstract interface class JpegCodec {
  /// Returns `width * height` framebuffer words.
  Future<Uint32List> decode(Uint8List jpeg, int width, int height);
}

final class RawDecoder implements RectDecoder {
  @override
  Future<String> decode(ByteReader input, RfbRect r, Framebuffer fb, PixelFormat pf) async {
    final n = r.w * r.h, size = pf.bytesPerPixel;
    fb.blit(r, pf.words(await input.read(n * size), 0, n, size));
    return 'Raw';
  }
}

final class CopyRectDecoder implements RectDecoder {
  @override
  Future<String> decode(ByteReader input, RfbRect r, Framebuffer fb, PixelFormat pf) async {
    final src = ByteData.sublistView(await input.read(4));
    fb.copy(src.getUint16(0), src.getUint16(2), r);
    return 'CopyRect';
  }
}

/// Cursor pseudo-encoding: pixels plus a 1-bit transparency mask.
Future<RemoteCursor> readCursor(ByteReader input, RfbRect r, PixelFormat pf) async {
  final size = pf.bytesPerPixel, maskRow = (r.w + 7) >> 3;
  final pixels = await input.read(r.w * r.h * size);
  final mask = await input.read(maskRow * r.h);
  final out = Uint32List(r.w * r.h);
  for (var y = 0; y < r.h; y++) {
    for (var x = 0; x < r.w; x++) {
      final i = y * r.w + x;
      final visible = (mask[y * maskRow + (x >> 3)] & (0x80 >> (x & 7))) != 0;
      out[i] = visible ? pf.read(pixels, i * size, size) : 0;
    }
  }
  return RemoteCursor(r.w, r.h, r.x, r.y, out.buffer.asUint8List());
}
