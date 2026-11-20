import 'dart:math';
import 'dart:typed_data';

import '../../../domain/errors.dart';
import '../byte_reader.dart';
import '../framebuffer.dart';
import '../pixel_format.dart';
import '../rfb_wire.dart';
import 'rect_decoder.dart';

/// ZRLE (RFC 6143 §7.7.6): zlib-compressed 64×64 tiles, each raw, solid,
/// packed-palette or run-length encoded.
final class ZrleDecoder implements RectDecoder {
  final _zlib = Inflater();
  final _tile = Uint32List(64 * 64);

  @override
  Future<void> decode(ByteReader input, RfbRect r, Framebuffer fb, PixelFormat pf) async {
    final d = _zlib.inflate(await input.read(await input.u32()));
    final cp = pf.compactSize;
    var o = 0;
    int pixel() {
      final v = pf.read(d, o, cp);
      o += cp;
      return v;
    }

    int runLength() {
      var n = 1, b = 0;
      do {
        b = d[o++];
        n += b;
      } while (b == 255);
      return n;
    }

    final px = _tile;
    for (var ty = r.y; ty < r.y + r.h; ty += 64) {
      for (var tx = r.x; tx < r.x + r.w; tx += 64) {
        final tile = (x: tx, y: ty, w: min(64, r.x + r.w - tx), h: min(64, r.y + r.h - ty));
        final n = tile.w * tile.h;
        final sub = d[o++];
        if (sub == 1) {
          fb.fill(tile, pixel());
          continue;
        }
        if (sub == 0) {
          for (var i = 0; i < n; i++) {
            px[i] = pixel();
          }
        } else if (sub <= 16) {
          final palette = [for (var i = 0; i < sub; i++) pixel()];
          final bits = sub == 2 ? 1 : (sub <= 4 ? 2 : 4), mask = (1 << bits) - 1;
          for (var y = 0, i = 0; y < tile.h; y++) {
            var byte = 0, left = 0;
            for (var x = 0; x < tile.w; x++, i++) {
              if (left == 0) {
                byte = d[o++];
                left = 8;
              }
              left -= bits;
              px[i] = palette[(byte >> left) & mask];
            }
          }
        } else if (sub == 128) {
          for (var i = 0; i < n;) {
            final c = pixel(), len = runLength();
            px.fillRange(i, i += len, c);
          }
        } else if (sub >= 130) {
          final palette = [for (var i = 0; i < sub - 128; i++) pixel()];
          for (var i = 0; i < n;) {
            final index = d[o++];
            final len = (index & 128) != 0 ? runLength() : 1;
            px.fillRange(i, i += len, palette[index & 127]);
          }
        } else {
          throw RemoteException(RemoteErrorKind.protocol, 'ZRLE subencoding $sub');
        }
        fb.blit(tile, px);
      }
    }
  }
}
