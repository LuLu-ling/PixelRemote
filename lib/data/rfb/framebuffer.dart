import 'dart:typed_data';

import '../../domain/errors.dart';
import '../../domain/services/remote_desktop.dart';

typedef RfbRect = ({int x, int y, int w, int h});

/// The client-side copy of the remote screen, as RGBA8888.
final class Framebuffer implements FrameView {
  Framebuffer(int width, int height) {
    resize(width, height);
  }

  late int _width, _height;
  late Uint8List _rgba;
  late Uint32List _px;

  @override
  int get width => _width;

  @override
  int get height => _height;

  @override
  Uint8List get rgba => _rgba;

  void resize(int width, int height) {
    _width = width;
    _height = height;
    _rgba = Uint8List(width * height * 4);
    _px = _rgba.buffer.asUint32List()..fillRange(0, width * height, 0xFF000000);
  }

  void fill(RfbRect r, int color) {
    for (var y = r.y; y < r.y + r.h; y++) {
      _px.fillRange(y * _width + r.x, y * _width + r.x + r.w, color);
    }
  }

  /// Copies [src] (tightly packed, `r.w` words per row) into [r].
  void blit(RfbRect r, Uint32List src) {
    for (var row = 0; row < r.h; row++) {
      final start = (r.y + row) * _width + r.x;
      _px.setRange(start, start + r.w, src, row * r.w);
    }
  }

  /// Moves pixels within the framebuffer (CopyRect); handles overlap.
  void copy(int srcX, int srcY, RfbRect dst) {
    if (srcX + dst.w > _width || srcY + dst.h > _height) {
      throw const RemoteException(RemoteErrorKind.protocol, 'CopyRect source outside framebuffer');
    }
    final downward = dst.y > srcY;
    for (var i = 0; i < dst.h; i++) {
      final row = downward ? dst.h - 1 - i : i;
      final to = (dst.y + row) * _width + dst.x;
      _px.setRange(to, to + dst.w, _px, (srcY + row) * _width + srcX);
    }
  }
}
