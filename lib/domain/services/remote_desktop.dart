import 'dart:typed_data';

import '../entities/stream_settings.dart';
import '../errors.dart';
import 'secure_tunnel.dart';
import 'session_log.dart';

/// Read-only view of the remote framebuffer as tightly packed RGBA8888.
abstract interface class FrameView {
  int get width;
  int get height;
  Uint8List get rgba;
}

final class RemoteCursor {
  const RemoteCursor(this.width, this.height, this.hotX, this.hotY, this.rgba);

  final int width;
  final int height;
  final int hotX;
  final int hotY;
  final Uint8List rgba;

  bool get isHidden => width == 0 || height == 0;
}

/// A live remote-desktop session. Implementations own the wire protocol.
abstract interface class RemoteDesktopSession {
  String get name;
  FrameView get frame;

  /// Emits (synchronously) after each complete framebuffer update.
  Stream<void> get frames;
  Stream<RemoteCursor> get cursors;
  Stream<String> get clipboard;

  /// Whether the server accepts resolution changes from the client.
  bool get canResize;

  /// Completes when the session ends: `null` if closed locally, otherwise why.
  Future<RemoteException?> get closed;

  void sendKey(int keysym, {required bool down});
  void sendPointer(int x, int y, int buttons);
  void sendClipboard(String text);

  /// Applies everything that can change mid-stream. The colour depth is
  /// negotiated when a connection opens and is ignored here.
  void applySettings(StreamSettings settings);
  void resize(int width, int height);
  void refresh();

  /// Bytes received per encoding (e.g. "Tight JPEG", "ZRLE") since the last call.
  Map<String, int> takeEncodingStats();

  Future<void> close();
}

abstract interface class RemoteDesktopProtocol {
  Future<RemoteDesktopSession> open(
    ByteChannel channel,
    StreamSettings settings, {
    required Future<String?> Function() password,
    required SessionLog log,
  });
}
