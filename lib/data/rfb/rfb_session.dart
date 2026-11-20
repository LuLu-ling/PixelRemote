import 'dart:async';
import 'dart:convert';
import 'dart:math';
import 'dart:typed_data';

import '../../domain/entities/stream_settings.dart';
import '../../domain/errors.dart';
import '../../domain/services/remote_desktop.dart';
import '../../domain/services/secure_tunnel.dart';
import 'byte_reader.dart';
import 'decoders/rect_decoder.dart';
import 'decoders/tight_decoder.dart';
import 'decoders/zrle_decoder.dart';
import 'extended_clipboard.dart';
import 'frame_pacer.dart';
import 'framebuffer.dart';
import 'pixel_format.dart';
import 'rfb_handshake.dart';
import 'rfb_wire.dart';

/// [RemoteDesktopProtocol] implementation for RFB / VNC.
final class RfbProtocol implements RemoteDesktopProtocol {
  const RfbProtocol(this._jpeg);

  final JpegCodec _jpeg;

  @override
  Future<RemoteDesktopSession> open(
    ByteChannel channel,
    StreamSettings settings, {
    required Future<String?> Function() password,
  }) async {
    final input = ByteReader(channel.input);
    try {
      final init = await performHandshake(input, channel.write, password);
      return RfbSession(channel, input, init, settings, _jpeg)..start();
    } catch (_) {
      await input.cancel();
      await channel.close();
      rethrow;
    }
  }
}

/// One RFB connection. Updates are pulled one at a time: each request is
/// paced by [FramePacer], which is what enforces frame-rate and bandwidth caps.
final class RfbSession implements RemoteDesktopSession {
  RfbSession(this._channel, this._input, ServerInit init, StreamSettings settings, JpegCodec jpeg)
      : name = init.name,
        _settings = settings,
        _format = PixelFormat.of(settings.colorDepth),
        _fb = Framebuffer(init.width, init.height),
        _nativeSize = (init.width, init.height),
        _pacer = FramePacer(fps: settings.frameRate, maxMbps: settings.maxBandwidthMbps),
        _decoders = {
          Encoding.raw: RawDecoder(),
          Encoding.copyRect: CopyRectDecoder(),
          Encoding.zrle: ZrleDecoder(),
          Encoding.tight: TightDecoder(jpeg),
        };

  static const _maxCutText = 64 << 20;

  final ByteChannel _channel;
  final ByteReader _input;
  final Framebuffer _fb;
  final (int, int) _nativeSize;
  final FramePacer _pacer;
  final Map<int, RectDecoder> _decoders;
  final _clip = ExtendedClipboard();
  final _frames = StreamController<void>.broadcast(sync: true);
  final _cursors = StreamController<RemoteCursor>.broadcast();
  final _clipboard = StreamController<String>.broadcast();
  final _closed = Completer<RemoteException?>();

  StreamSettings _settings;
  PixelFormat _format; // what the server is sending right now
  PixelFormat? _pendingFormat; // switched only between updates
  List<RfbScreen> _screens = const [];
  (int, int)? _wantedSize;
  bool _canResize = false, _fullRefresh = true;
  int _outstanding = 0;
  Timer? _timer;

  @override
  String name;

  @override
  FrameView get frame => _fb;

  @override
  Stream<void> get frames => _frames.stream;

  @override
  Stream<RemoteCursor> get cursors => _cursors.stream;

  @override
  Stream<String> get clipboard => _clipboard.stream;

  @override
  bool get canResize => _canResize;

  @override
  Future<RemoteException?> get closed => _closed.future;

  void start() {
    _send(ClientMessage.setPixelFormat(_format));
    _send(ClientMessage.setEncodings(_encodings()));
    _applyResolution();
    _requestUpdate();
    unawaited(_readLoop());
  }

  // ---- commands from the viewer --------------------------------------------

  @override
  void sendKey(int keysym, {required bool down}) => _send(ClientMessage.key(keysym, down: down));

  @override
  void sendPointer(int x, int y, int buttons) =>
      _send(ClientMessage.pointer(buttons, x.clamp(0, max(0, _fb.width - 1)), y.clamp(0, max(0, _fb.height - 1))));

  @override
  void sendClipboard(String text) => _send(_clip.enabled
      ? _clip.offer(text)
      : ClientMessage.cutText(latin1.encode(text.replaceAll('\r\n', '\n').replaceAll(RegExp(r'[^\x00-\xff]'), '?'))));

  @override
  void applySettings(StreamSettings settings) {
    final old = _settings;
    _settings = settings;
    _pacer.configure(fps: settings.frameRate, maxMbps: settings.maxBandwidthMbps);
    if (settings.colorDepth != old.colorDepth) _pendingFormat = PixelFormat.of(settings.colorDepth);
    if (settings.quality != old.quality) _send(ClientMessage.setEncodings(_encodings()));
    if (settings.resolution != old.resolution) _applyResolution();
  }

  @override
  void resize(int width, int height) {
    _wantedSize = (width.clamp(16, 8192), height.clamp(16, 8192));
    _requestWantedSize();
  }

  /// Sends the remembered size once the server has said it supports resizing.
  void _requestWantedSize() {
    final wanted = _wantedSize;
    if (wanted == null || !_canResize || (wanted.$1 == _fb.width && wanted.$2 == _fb.height)) return;
    final base = _screens.isEmpty ? const RfbScreen(0, 0, 0, 0, 0, 0) : _screens.first;
    _send(ClientMessage.setDesktopSize(wanted.$1, wanted.$2, [RfbScreen(base.id, 0, 0, wanted.$1, wanted.$2, base.flags)]));
  }

  @override
  void refresh() {
    _fullRefresh = true;
    if (_outstanding > 0) _requestUpdate(); // the pending one may be parked on an idle screen
  }

  @override
  Future<void> close() async => _shutdown(null);

  // ---- server messages -----------------------------------------------------

  Future<void> _readLoop() async {
    try {
      while (!_closed.isCompleted) {
        switch (await _input.u8()) {
          case 0:
            await _readUpdate();
          case 1: // SetColourMapEntries: irrelevant in true-colour mode
            final head = await _input.read(5);
            await _input.read(((head[3] << 8) | head[4]) * 6);
          case 2: // Bell
            break;
          case 3:
            await _readCutText();
          case final type:
            throw RemoteException(RemoteErrorKind.protocol, 'unexpected server message $type');
        }
      }
    } on RemoteException catch (e) {
      _shutdown(e);
    } catch (e) {
      _shutdown(RemoteException(RemoteErrorKind.protocol, '$e'));
    }
  }

  Future<void> _readUpdate() async {
    final start = _input.consumed - 1;
    final head = await _input.read(3);
    final count = (head[1] << 8) | head[2];
    for (var i = 0; i < count; i++) {
      final h = ByteData.sublistView(await _input.read(12));
      final encoding = h.getInt32(8);
      if (encoding == Encoding.lastRect) break;
      await _readRect((x: h.getUint16(0), y: h.getUint16(2), w: h.getUint16(4), h: h.getUint16(6)), encoding);
    }
    _outstanding = 0;
    if (!_frames.isClosed) _frames.add(null);
    _timer?.cancel();
    _timer = Timer(_pacer.onFrame(_input.consumed - start), _requestUpdate);
  }

  Future<void> _readRect(RfbRect r, int encoding) async {
    switch (encoding) {
      case Encoding.desktopSize:
        _resizeFramebuffer(r.w, r.h);
      case Encoding.extendedDesktopSize:
        await _readExtendedDesktopSize(r);
      case Encoding.cursor:
        final cursor = await readCursor(_input, r, _format);
        if (!_cursors.isClosed) _cursors.add(cursor);
      case Encoding.desktopName:
        name = utf8.decode(await _input.read(await _input.u32()), allowMalformed: true);
      default:
        final decoder = _decoders[encoding];
        if (decoder == null) throw RemoteException(RemoteErrorKind.protocol, 'unsupported encoding $encoding');
        if (r.x + r.w > _fb.width || r.y + r.h > _fb.height) {
          throw const RemoteException(RemoteErrorKind.protocol, 'rectangle outside framebuffer');
        }
        await decoder.decode(_input, r, _fb, _format);
    }
  }

  /// x = reason (1: our request), y = status (0: success).
  Future<void> _readExtendedDesktopSize(RfbRect r) async {
    final count = (await _input.read(4))[0];
    final b = ByteData.sublistView(await _input.read(count * 16));
    _screens = [
      for (var o = 0; o < count * 16; o += 16)
        RfbScreen(b.getUint32(o), b.getUint16(o + 4), b.getUint16(o + 6), b.getUint16(o + 8), b.getUint16(o + 10),
            b.getUint32(o + 12)),
    ];
    if (r.x != 1 || r.y == 0) _resizeFramebuffer(r.w, r.h);
    if (!_canResize) {
      _canResize = true;
      _requestWantedSize();
    }
  }

  Future<void> _readCutText() async {
    final length = ByteData.sublistView(await _input.read(7)).getInt32(3);
    if (length.abs() > _maxCutText) throw const RemoteException(RemoteErrorKind.protocol, 'clipboard too large');
    final payload = await _input.read(length.abs());
    final text = length >= 0 ? latin1.decode(payload) : _clip.receive(payload, _send);
    if (text != null && !_clipboard.isClosed) _clipboard.add(text);
  }

  // ---- helpers -------------------------------------------------------------

  List<int> _encodings() => [
        Encoding.tight,
        Encoding.zrle,
        Encoding.copyRect,
        Encoding.raw,
        if (_settings.quality.jpeg case final q?) Encoding.jpegQuality(q),
        Encoding.compressLevel(_settings.quality.compression),
        Encoding.cursor,
        Encoding.desktopSize,
        Encoding.extendedDesktopSize,
        Encoding.lastRect,
        Encoding.desktopName,
        Encoding.extendedClipboard,
      ];

  void _applyResolution() {
    final r = _settings.resolution;
    if (r.isFixed) resize(r.width, r.height);
    if (r.isNative) {
      _wantedSize = _nativeSize; // back to whatever the server started with
      _requestWantedSize();
    }
    // matchWindow is driven by the view through resize().
  }

  void _resizeFramebuffer(int w, int h) {
    if (w == _fb.width && h == _fb.height) return;
    _fb.resize(w, h);
    _fullRefresh = true;
  }

  void _requestUpdate() {
    if (_closed.isCompleted) return;
    if (_outstanding == 0 && _pendingFormat != null) {
      _format = _pendingFormat!;
      _pendingFormat = null;
      _send(ClientMessage.setPixelFormat(_format));
      _fullRefresh = true;
    }
    _send(ClientMessage.updateRequest(incremental: !_fullRefresh, width: _fb.width, height: _fb.height));
    _fullRefresh = false;
    _outstanding++;
    _pacer.onRequest();
  }

  void _send(List<int> bytes) {
    if (_closed.isCompleted) return;
    try {
      _channel.write(bytes);
    } catch (e) {
      _shutdown(RemoteException(RemoteErrorKind.disconnected, '$e'));
    }
  }

  void _shutdown(RemoteException? reason) {
    if (_closed.isCompleted) return;
    _closed.complete(reason);
    _timer?.cancel();
    unawaited(_input.cancel());
    unawaited(_channel.close().catchError((Object _) {}));
    _frames.close();
    _cursors.close();
    _clipboard.close();
  }
}
