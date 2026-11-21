import 'dart:async';
import 'dart:convert';
import 'dart:math';
import 'dart:typed_data';

import '../../domain/entities/stream_settings.dart';
import '../../domain/errors.dart';
import '../../domain/services/remote_desktop.dart';
import '../../domain/services/secure_tunnel.dart';
import '../../domain/services/session_log.dart';
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
    required SessionLog log,
  }) async {
    final input = ByteReader(channel.input);
    try {
      final init = await performHandshake(input, channel.write, password, log);
      return RfbSession(channel, input, init, settings, _jpeg, log)..start();
    } catch (_) {
      await input.cancel();
      await channel.close();
      rethrow;
    }
  }
}

/// One RFB connection. Its pixel format is fixed for its lifetime, which keeps
/// decoding unambiguous (a colour-depth change opens a new connection).
///
/// Requests are pipelined like TigerVNC's viewer: the next request goes out as
/// soon as an update starts arriving, so the server encodes frame N+1 while
/// frame N is still in flight. [FramePacer] delays requests to honour the
/// frame-rate and bandwidth limits.
final class RfbSession implements RemoteDesktopSession {
  RfbSession(this._channel, this._input, ServerInit init, StreamSettings settings, JpegCodec jpeg, this._log)
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

  static const _src = 'rfb', _maxCutText = 64 << 20, _summaryEvery = Duration(seconds: 10);

  final ByteChannel _channel;
  final ByteReader _input;
  final SessionLog _log;
  final Framebuffer _fb;
  final (int, int) _nativeSize;
  final PixelFormat _format;
  final FramePacer _pacer;
  final Map<int, RectDecoder> _decoders;
  final _clip = ExtendedClipboard();
  final _frames = StreamController<void>.broadcast(sync: true);
  final _cursors = StreamController<RemoteCursor>.broadcast();
  final _clipboard = StreamController<String>.broadcast();
  final _closed = Completer<RemoteException?>();
  final _usage = <String, int>{};
  final _window = _WindowStats();
  final _seen = <String>{};

  StreamSettings _settings;
  List<RfbScreen> _screens = const [];
  (int, int)? _wantedSize;
  bool _canResize = false, _fullRefresh = true, _requestScheduled = false, _legacyClipboardLogged = false;
  int _updates = 0;
  Timer? _requestTimer, _summaryTimer;

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
    final encodings = _encodings();
    _log.info(_src, 'Requesting pixel format ${_format.describe()}');
    _log.info(_src, 'Encodings offered: ${encodings.map(Encoding.name).join(', ')}');
    _send(ClientMessage.setPixelFormat(_format));
    _send(ClientMessage.setEncodings(encodings));
    _applyResolution();
    _sendRequest();
    _summaryTimer = Timer.periodic(_summaryEvery, (_) => _logSummary());
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
    _settings = settings.copyWith(colorDepth: old.colorDepth); // fixed for this connection
    _pacer.configure(fps: settings.frameRate, maxMbps: settings.maxBandwidthMbps);
    if (settings.frameRate != old.frameRate || settings.maxBandwidthMbps != old.maxBandwidthMbps) {
      final cap = settings.maxBandwidthMbps == 0 ? 'unlimited' : '${settings.maxBandwidthMbps} Mbit/s';
      _log.info(_src, 'Pacing: up to ${settings.frameRate} fps, bandwidth $cap');
    }
    if (settings.quality != old.quality) {
      final q = settings.quality;
      _log.info(_src, 'Quality ${old.quality.name} → ${q.name}: JPEG ${q.jpeg ?? 'off (lossless)'}, zlib level ${q.compression}');
      _send(ClientMessage.setEncodings(_encodings()));
    }
    if (settings.resolution != old.resolution) _applyResolution();
  }

  @override
  void resize(int width, int height) {
    _wantedSize = (width.clamp(16, 8192), height.clamp(16, 8192));
    _requestWantedSize();
  }

  @override
  void refresh() {
    _fullRefresh = true;
    if (!_requestScheduled) _sendRequest(); // the pending one may be parked on an idle screen
  }

  @override
  Map<String, int> takeEncodingStats() {
    final stats = Map.of(_usage);
    _usage.clear();
    return stats;
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
    final watch = Stopwatch()..start();
    final head = await _input.read(3);
    _scheduleRequest(); // pipelining: let the server prepare the next frame now
    final count = (head[1] << 8) | head[2];
    for (var i = 0; i < count; i++) {
      final h = ByteData.sublistView(await _input.read(12));
      final encoding = h.getInt32(8);
      if (encoding == Encoding.lastRect) break;
      final before = _input.consumed;
      final label = await _readRect((x: h.getUint16(0), y: h.getUint16(2), w: h.getUint16(4), h: h.getUint16(6)), encoding);
      if (label != null) _account(label, _input.consumed - before);
    }
    final bytes = _input.consumed - start;
    _pacer.onReceived(bytes);
    _window.addUpdate(bytes, watch.elapsedMicroseconds);
    if (++_updates == 1 && !_canResize) {
      _log.info(_src, 'Server does not support ExtendedDesktopSize: resolution changes are scaled locally');
    }
    if (!_frames.isClosed) _frames.add(null);
  }

  /// Decodes one rectangle; returns its statistics label (null for pseudo-encodings).
  Future<String?> _readRect(RfbRect r, int encoding) async {
    switch (encoding) {
      case Encoding.desktopSize:
        _log.info(_src, 'Server resized the desktop to ${r.w}×${r.h}');
        _resizeFramebuffer(r.w, r.h);
      case Encoding.extendedDesktopSize:
        await _readExtendedDesktopSize(r);
      case Encoding.cursor:
        final cursor = await readCursor(_input, r, _format);
        if (!_cursors.isClosed) _cursors.add(cursor);
      case Encoding.desktopName:
        name = utf8.decode(await _input.read(await _input.u32()), allowMalformed: true);
        _log.info(_src, 'Desktop renamed to "$name"');
      default:
        final decoder = _decoders[encoding];
        if (decoder == null) {
          throw RemoteException(RemoteErrorKind.protocol, 'server sent ${Encoding.name(encoding)}, which was not requested');
        }
        if (r.x + r.w > _fb.width || r.y + r.h > _fb.height) {
          throw const RemoteException(RemoteErrorKind.protocol, 'rectangle outside framebuffer');
        }
        return decoder.decode(_input, r, _fb, _format);
    }
    return null;
  }

  /// x = reason (0 server, 1 this client, 2 another client), y = status.
  Future<void> _readExtendedDesktopSize(RfbRect r) async {
    final count = (await _input.read(4))[0];
    final b = ByteData.sublistView(await _input.read(count * 16));
    _screens = [
      for (var o = 0; o < count * 16; o += 16)
        RfbScreen(b.getUint32(o), b.getUint16(o + 4), b.getUint16(o + 6), b.getUint16(o + 8), b.getUint16(o + 10),
            b.getUint32(o + 12)),
    ];
    if (!_canResize) {
      _canResize = true;
      _log.info(_src, 'Server supports remote resizing (ExtendedDesktopSize), ${_screens.length} screen(s)');
    }
    const reasons = ['server', 'this viewer', 'another viewer'];
    const failures = ['', 'prohibited', 'out of resources', 'invalid screen layout'];
    if (r.x == 1 && r.y != 0) {
      _log.warn(_src, 'Server refused the resize: ${r.y < failures.length ? failures[r.y] : 'error ${r.y}'}');
    } else {
      if (r.w != _fb.width || r.h != _fb.height) {
        _log.info(_src, 'Desktop is now ${r.w}×${r.h} (changed by ${r.x < reasons.length ? reasons[r.x] : 'unknown'})');
      }
      _resizeFramebuffer(r.w, r.h);
    }
    _requestWantedSize();
  }

  Future<void> _readCutText() async {
    final length = ByteData.sublistView(await _input.read(7)).getInt32(3);
    if (length.abs() > _maxCutText) throw const RemoteException(RemoteErrorKind.protocol, 'clipboard too large');
    final payload = await _input.read(length.abs());
    final wasEnabled = _clip.enabled;
    final String? text;
    if (length >= 0) {
      text = latin1.decode(payload);
      if (!_legacyClipboardLogged) {
        _legacyClipboardLogged = true;
        _log.info(_src, 'Server uses the legacy Latin-1 clipboard (non-Latin text such as Chinese cannot be shared)');
      }
    } else {
      text = _clip.receive(payload, _send);
      if (!wasEnabled && _clip.enabled) _log.info(_src, 'Extended clipboard enabled (UTF-8)');
    }
    if (text != null && !_clipboard.isClosed) {
      _log.debug(_src, 'Received ${text.length} characters of clipboard text');
      _clipboard.add(text);
    }
  }

  // ---- helpers -------------------------------------------------------------

  void _account(String label, int bytes) {
    _usage[label] = (_usage[label] ?? 0) + bytes;
    _window.addRect(label, bytes);
    if (_seen.add(label)) {
      final lossless = label == 'ZRLE' || label == 'Raw';
      _log.info(_src, 'Server started sending $label${lossless ? ' (lossless, so JPEG quality settings do not apply)' : ''}');
    }
  }

  void _logSummary() {
    final w = _window;
    if (w.updates == 0) return;
    final parts = w.byLabel.entries.map((e) => '${e.key} ${e.value.$1}×${_kb(e.value.$2)}').join(', ');
    _log.info(
      _src,
      '${w.updates} updates in ${_summaryEvery.inSeconds} s, ${_kb(w.bytes)} '
      '(${(w.bytes * 8 / _summaryEvery.inMicroseconds).toStringAsFixed(1)} Mbit/s), '
      'avg ${_kb(w.bytes ~/ w.updates)} and ${(w.micros / w.updates / 1000).toStringAsFixed(1)} ms per update; $parts',
    );
    w.reset();
  }

  static String _kb(int bytes) => bytes >= 1 << 20 ? '${(bytes / (1 << 20)).toStringAsFixed(1)} MB' : '${(bytes / 1024).toStringAsFixed(1)} KB';

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

  /// Sends the remembered size once the server has said it supports resizing.
  void _requestWantedSize() {
    final wanted = _wantedSize;
    if (wanted == null || !_canResize || (wanted.$1 == _fb.width && wanted.$2 == _fb.height)) return;
    _log.info(_src, 'Requesting desktop size ${wanted.$1}×${wanted.$2}');
    final base = _screens.isEmpty ? const RfbScreen(0, 0, 0, 0, 0, 0) : _screens.first;
    _send(ClientMessage.setDesktopSize(wanted.$1, wanted.$2, [RfbScreen(base.id, 0, 0, wanted.$1, wanted.$2, base.flags)]));
  }

  void _resizeFramebuffer(int w, int h) {
    if (w == _fb.width && h == _fb.height) return;
    _fb.resize(w, h);
    _fullRefresh = true;
  }

  void _scheduleRequest() {
    if (_requestScheduled || _closed.isCompleted) return;
    final delay = _pacer.nextDelay();
    if (delay == Duration.zero) return _sendRequest();
    _requestScheduled = true;
    _requestTimer = Timer(delay, _sendRequest);
  }

  void _sendRequest() {
    _requestScheduled = false;
    if (_closed.isCompleted) return;
    _send(ClientMessage.updateRequest(incremental: !_fullRefresh, width: _fb.width, height: _fb.height));
    _fullRefresh = false;
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
    reason == null ? _log.info(_src, 'Connection closed by the viewer') : _log.error(_src, 'Connection lost: $reason');
    _closed.complete(reason);
    _requestTimer?.cancel();
    _summaryTimer?.cancel();
    unawaited(_input.cancel());
    unawaited(_channel.close().catchError((Object _) {}));
    // Deferred: close() may be called from inside a (synchronous) frame event.
    scheduleMicrotask(() {
      _frames.close();
      _cursors.close();
      _clipboard.close();
    });
  }
}

/// Rolling counters for the periodic log summary.
final class _WindowStats {
  int updates = 0, bytes = 0, micros = 0;
  final byLabel = <String, (int, int)>{};

  void addUpdate(int size, int us) {
    updates++;
    bytes += size;
    micros += us;
  }

  void addRect(String label, int size) {
    final (rects, total) = byLabel[label] ?? (0, 0);
    byLabel[label] = (rects + 1, total + size);
  }

  void reset() {
    updates = bytes = micros = 0;
    byLabel.clear();
  }
}
