import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'rfb_wire.dart';

/// Extended Clipboard pseudo-encoding: UTF-8 text (so CJK survives), using
/// the caps / notify / request / provide handshake. Falls back to Latin-1
/// cut text when the server never announces support.
final class ExtendedClipboard {
  static const _text = 1, _caps = 1 << 24, _request = 1 << 25, _peek = 1 << 26, _notify = 1 << 27, _provide = 1 << 28;
  static const _maxTextBytes = 16 << 20;

  bool _enabled = false;
  String? _local;

  bool get enabled => _enabled;

  /// Handles a server message, sending any replies; returns text the server provided.
  String? receive(Uint8List payload, void Function(List<int>) send) {
    if (payload.length < 4) return null;
    final flags = ByteData.sublistView(payload).getUint32(0);
    if ((flags & _caps) != 0) {
      _enabled = true;
      send(_message(_caps | _request | _peek | _notify | _provide | _text, _u32(_maxTextBytes)));
    } else if ((flags & _request) != 0) {
      if ((flags & _text) != 0 && _local != null) send(_provideText(_local!));
    } else if ((flags & _peek) != 0) {
      send(_message(_notify | (_local == null ? 0 : _text)));
    } else if ((flags & _notify) != 0) {
      if ((flags & _text) != 0) send(_message(_request | _text));
    } else if ((flags & _provide) != 0 && (flags & _text) != 0) {
      final data = Uint8List.fromList(ZLibCodec().decode(payload.sublist(4)));
      final length = ByteData.sublistView(data).getUint32(0);
      final text = utf8.decode(data.sublist(4, 4 + length), allowMalformed: true);
      return text.replaceAll('\x00', '').replaceAll('\r\n', '\n');
    }
    return null;
  }

  /// Announces new local clipboard text; the server pulls it when it wants it.
  Uint8List offer(String text) {
    _local = text;
    return _message(_notify | _text);
  }

  static Uint8List _provideText(String text) {
    final bytes = utf8.encode('${text.replaceAll('\r\n', '\n').replaceAll('\n', '\r\n')}\x00');
    return _message(_provide | _text, ZLibCodec().encode([..._u32(bytes.length), ...bytes]));
  }

  static Uint8List _message(int flags, [List<int> data = const []]) =>
      ClientMessage.cutText([..._u32(flags), ...data], extended: true);

  static Uint8List _u32(int v) => Uint8List(4)..buffer.asByteData().setUint32(0, v);
}
