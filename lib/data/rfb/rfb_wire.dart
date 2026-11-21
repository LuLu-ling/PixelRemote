import 'dart:io';
import 'dart:typed_data';

import 'pixel_format.dart';

abstract final class Encoding {
  static const raw = 0, copyRect = 1, tight = 7, zrle = 16;
  static const cursor = -239, desktopSize = -223, lastRect = -224;
  static const desktopName = -307, extendedDesktopSize = -308;
  static const extendedClipboard = -1063131698; // 0xC0A1E5CE

  static int jpegQuality(int level) => -32 + level;
  static int compressLevel(int level) => -256 + level;

  static String name(int e) => switch (e) {
        raw => 'Raw',
        copyRect => 'CopyRect',
        2 => 'RRE',
        5 => 'Hextile',
        tight => 'Tight',
        zrle => 'ZRLE',
        cursor => 'Cursor',
        desktopSize => 'DesktopSize',
        lastRect => 'LastRect',
        desktopName => 'DesktopName',
        extendedDesktopSize => 'ExtendedDesktopSize',
        extendedClipboard => 'ExtendedClipboard',
        >= -32 && <= -23 => 'JPEG quality ${e + 32}',
        >= -256 && <= -247 => 'zlib level ${e + 256}',
        _ => 'encoding $e',
      };
}

String securityTypeName(int t) => switch (t) {
      1 => 'None',
      2 => 'VncAuth',
      5 => 'RA2',
      6 => 'RA2ne',
      16 => 'Tight',
      18 => 'TLS',
      19 => 'VeNCrypt',
      30 => 'Apple DH',
      _ => '#$t',
    };

final class RfbScreen {
  const RfbScreen(this.id, this.x, this.y, this.width, this.height, this.flags);

  final int id, x, y, width, height, flags;
}

/// Encoders for client-to-server messages (RFC 6143 §7.5 plus extensions).
abstract final class ClientMessage {
  static Uint8List setPixelFormat(PixelFormat pf) => Uint8List(20)..setRange(4, 20, pf.encode());

  static Uint8List setEncodings(List<int> encodings) {
    final b = ByteData(4 + 4 * encodings.length)
      ..setUint8(0, 2)
      ..setUint16(2, encodings.length);
    for (var i = 0; i < encodings.length; i++) {
      b.setInt32(4 + 4 * i, encodings[i]);
    }
    return b.buffer.asUint8List();
  }

  static Uint8List updateRequest({required bool incremental, required int width, required int height}) => _bytes(
      ByteData(10)
        ..setUint8(0, 3)
        ..setUint8(1, incremental ? 1 : 0)
        ..setUint16(6, width)
        ..setUint16(8, height));

  static Uint8List key(int keysym, {required bool down}) => _bytes(ByteData(8)
    ..setUint8(0, 4)
    ..setUint8(1, down ? 1 : 0)
    ..setUint32(4, keysym));

  static Uint8List pointer(int buttons, int x, int y) => _bytes(ByteData(6)
    ..setUint8(0, 5)
    ..setUint8(1, buttons)
    ..setUint16(2, x)
    ..setUint16(4, y));

  /// ClientCutText; [extended] payloads use the negative-length convention.
  static Uint8List cutText(List<int> payload, {bool extended = false}) {
    final head = ByteData(8)
      ..setUint8(0, 6)
      ..setInt32(4, extended ? -payload.length : payload.length);
    return Uint8List.fromList([..._bytes(head), ...payload]);
  }

  static Uint8List setDesktopSize(int width, int height, List<RfbScreen> screens) {
    final b = ByteData(8 + 16 * screens.length)
      ..setUint8(0, 251)
      ..setUint16(2, width)
      ..setUint16(4, height)
      ..setUint8(6, screens.length);
    for (var i = 0; i < screens.length; i++) {
      final s = screens[i], o = 8 + 16 * i;
      b
        ..setUint32(o, s.id)
        ..setUint16(o + 4, s.x)
        ..setUint16(o + 6, s.y)
        ..setUint16(o + 8, s.width)
        ..setUint16(o + 10, s.height)
        ..setUint32(o + 12, s.flags);
    }
    return b.buffer.asUint8List();
  }

  static Uint8List _bytes(ByteData b) => b.buffer.asUint8List();
}

/// A persistent zlib inflate stream: RFB keeps zlib state across rectangles.
final class Inflater {
  RawZLibFilter _filter = RawZLibFilter.inflateFilter();

  void reset() => _filter = RawZLibFilter.inflateFilter();

  Uint8List inflate(Uint8List input) {
    _filter.process(input, 0, input.length);
    final out = BytesBuilder(copy: false);
    for (var chunk = _filter.processed(); chunk != null; chunk = _filter.processed()) {
      out.add(chunk);
    }
    return out.takeBytes();
  }
}
