import 'dart:typed_data';
import 'dart:ui' as ui;

import '../../domain/errors.dart';
import '../rfb/decoders/rect_decoder.dart';

/// Decodes JPEG with the engine's native codec (libjpeg-turbo/Skia), far
/// faster than any pure-Dart decoder.
final class UiJpegCodec implements JpegCodec {
  const UiJpegCodec();

  @override
  Future<Uint32List> decode(Uint8List jpeg, int width, int height) async {
    final buffer = await ui.ImmutableBuffer.fromUint8List(jpeg);
    final descriptor = await ui.ImageDescriptor.encoded(buffer);
    final codec = await descriptor.instantiateCodec();
    final image = (await codec.getNextFrame()).image;
    try {
      final data = await image.toByteData(format: ui.ImageByteFormat.rawRgba);
      if (data == null || image.width != width || image.height != height) {
        throw const RemoteException(RemoteErrorKind.protocol, 'JPEG rectangle size mismatch');
      }
      return data.buffer.asUint32List(data.offsetInBytes, width * height);
    } finally {
      image.dispose();
      codec.dispose();
      descriptor.dispose();
      buffer.dispose();
    }
  }
}
