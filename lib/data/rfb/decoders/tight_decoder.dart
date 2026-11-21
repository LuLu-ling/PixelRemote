import 'dart:typed_data';

import '../../../domain/errors.dart';
import '../byte_reader.dart';
import '../framebuffer.dart';
import '../pixel_format.dart';
import '../rfb_wire.dart';
import 'rect_decoder.dart';

/// Tight: fill, JPEG, or zlib-compressed data passed through a copy, palette
/// or gradient filter, over four persistent zlib streams.
final class TightDecoder implements RectDecoder {
  TightDecoder(this._jpeg);

  final JpegCodec _jpeg;
  final _zlib = List.generate(4, (_) => Inflater());

  static const _copy = 0, _palette = 1, _gradient = 2;

  @override
  Future<Decoded> decode(ByteReader input, RfbRect r, Framebuffer fb, PixelFormat pf) async {
    final control = await input.u8();
    for (var i = 0; i < 4; i++) {
      if ((control & (1 << i)) != 0) _zlib[i].reset();
    }
    final kind = control >> 4, tp = pf.compactSize;

    if (kind == 8) {
      fb.fill(r, pf.read(await input.read(tp), 0, tp));
      return const Decoded('Tight');
    }
    if (kind == 9) {
      final pixels = _jpeg.decode(await input.read(await _length(input)), r.w, r.h);
      return Decoded('Tight JPEG', pixels.then((px) => () => fb.blit(r, px)));
    }
    if (kind > 9) throw RemoteException(RemoteErrorKind.protocol, 'Tight compression $kind');

    final filter = (kind & 4) != 0 ? await input.u8() : _copy;
    var palette = const <int>[];
    var rowBytes = r.w * tp;
    if (filter == _palette) {
      final colors = await input.u8() + 1;
      final p = await input.read(colors * tp);
      palette = [for (var i = 0; i < colors; i++) pf.read(p, i * tp, tp)];
      rowBytes = colors == 2 ? (r.w + 7) >> 3 : r.w;
    } else if (filter != _copy && filter != _gradient) {
      throw RemoteException(RemoteErrorKind.protocol, 'Tight filter $filter');
    }

    final size = rowBytes * r.h;
    final data = size < 12 ? await input.read(size) : _zlib[kind & 3].inflate(await input.read(await _length(input)));
    if (data.length < size) throw const RemoteException(RemoteErrorKind.protocol, 'short Tight data');

    fb.blit(r, switch (filter) {
      _palette => _expandPalette(data, palette, r.w, r.h, rowBytes),
      _gradient => _ungradient(data, r.w, r.h, tp, pf),
      _ => pf.words(data, 0, r.w * r.h, tp),
    });
    return const Decoded('Tight');
  }

  static Future<int> _length(ByteReader input) async {
    var b = await input.u8();
    var n = b & 0x7f;
    if ((b & 0x80) != 0) {
      b = await input.u8();
      n |= (b & 0x7f) << 7;
      if ((b & 0x80) != 0) n |= await input.u8() << 14;
    }
    return n;
  }

  static Uint32List _expandPalette(Uint8List d, List<int> palette, int w, int h, int rowBytes) {
    final out = Uint32List(w * h);
    if (palette.length == 2) {
      for (var y = 0; y < h; y++) {
        for (var x = 0; x < w; x++) {
          out[y * w + x] = palette[(d[y * rowBytes + (x >> 3)] >> (7 - (x & 7))) & 1];
        }
      }
    } else {
      for (var i = 0; i < w * h; i++) {
        out[i] = palette[d[i]];
      }
    }
    return out;
  }

  /// Each component is predicted as left + above − above-left (clamped) and
  /// the stream carries the residual modulo (max + 1).
  static Uint32List _ungradient(Uint8List d, int w, int h, int tp, PixelFormat pf) {
    final maxes = [pf.redMax, pf.greenMax, pf.blueMax], shifts = [pf.redShift, pf.greenShift, pf.blueShift];
    var above = Int32List(w * 3), row = Int32List(w * 3);
    final out = Uint32List(w * h);
    for (var y = 0, o = 0; y < h; y++) {
      for (var x = 0; x < w; x++, o += tp) {
        final residual = PixelFormat.raw(d, o, tp);
        var v = 0;
        for (var c = 0; c < 3; c++) {
          final left = x > 0 ? row[(x - 1) * 3 + c] : 0;
          final aboveLeft = x > 0 ? above[(x - 1) * 3 + c] : 0;
          final predicted = (left + above[x * 3 + c] - aboveLeft).clamp(0, maxes[c]);
          final value = (predicted + ((residual >> shifts[c]) & maxes[c])) & maxes[c];
          row[x * 3 + c] = value;
          v |= value << shifts[c];
        }
        out[y * w + x] = pf.toWord(v);
      }
      (above, row) = (row, above);
    }
    return out;
  }
}
