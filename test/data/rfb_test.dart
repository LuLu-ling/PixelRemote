import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:pixel_remote/application/connection_log.dart';
import 'package:pixel_remote/data/rfb/byte_reader.dart';
import 'package:pixel_remote/data/rfb/decoders/rect_decoder.dart';
import 'package:pixel_remote/data/rfb/frame_pacer.dart';
import 'package:pixel_remote/data/rfb/rfb_handshake.dart';
import 'package:pixel_remote/data/rfb/rfb_session.dart';
import 'package:pixel_remote/data/rfb/tight_quality.dart';
import 'package:pixel_remote/domain/entities/stream_settings.dart';
import 'package:pixel_remote/domain/errors.dart';
import 'package:pixel_remote/domain/services/remote_desktop.dart';
import 'package:pixel_remote/domain/services/secure_tunnel.dart';

/// Loopback pipe: the client talks to [server], the test plays the VNC server.
final class _Pipe implements ByteChannel {
  final _toClient = StreamController<Uint8List>();
  final _toServer = StreamController<Uint8List>();
  late final ByteReader server = ByteReader(_toServer.stream);

  @override
  Stream<Uint8List> get input => _toClient.stream;

  @override
  void write(List<int> bytes) => _toServer.add(Uint8List.fromList(bytes));

  @override
  Future<void> close() async => _toClient.close();

  void send(List<int> bytes) => _toClient.add(Uint8List.fromList(bytes));
}

/// JPEG codec whose decodes finish only when the test says so.
final class _ControlledJpeg implements JpegCodec {
  final pending = <Completer<Uint32List>>[];

  @override
  Future<Uint32List> decode(Uint8List jpeg, int width, int height) => (Completer<Uint32List>()..also(pending.add)).future;
}

extension<T> on T {
  T also(void Function(T) f) {
    f(this);
    return this;
  }
}

final class _NoJpeg implements JpegCodec {
  const _NoJpeg();

  @override
  Future<Uint32List> decode(Uint8List jpeg, int width, int height) => throw UnimplementedError();
}

List<int> _u16(int v) => [v >> 8 & 0xff, v & 0xff];
List<int> _u32(int v) => [v >> 24 & 0xff, v >> 16 & 0xff, v >> 8 & 0xff, v & 0xff];
List<int> _rect(int x, int y, int w, int h, int encoding) => [..._u16(x), ..._u16(y), ..._u16(w), ..._u16(h), ..._u32(encoding)];

/// Framebuffer word for an opaque RGB colour.
int _rgb(int r, int g, int b) => 0xFF000000 | b << 16 | g << 8 | r;

final class _FakeClock implements Stopwatch {
  int now = 0;

  @override
  int get elapsedMicroseconds => now;

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

/// Parses what the client sends, one whole message at a time (type byte first).
final class _ClientMessages {
  _ClientMessages(this._in);

  final ByteReader _in;

  Future<Uint8List> next() async {
    final type = await _in.u8();
    Future<List<int>> rest() async {
      switch (type) {
        case 0:
          return _in.read(19);
        case 2:
          final h = await _in.read(3);
          return [...h, ...await _in.read(((h[1] << 8) | h[2]) * 4)];
        case 3:
          return _in.read(9);
        case 4:
          return _in.read(7);
        case 5:
          return _in.read(5);
        case 6:
          final h = await _in.read(7);
          return [...h, ...await _in.read(ByteData.sublistView(h).getInt32(3).abs())];
        case 251:
          final h = await _in.read(7);
          return [...h, ...await _in.read(h[5] * 16)];
        default:
          throw StateError('unexpected client message $type');
      }
    }

    return Uint8List.fromList([type, ...await rest()]);
  }

  /// Next message other than a FramebufferUpdateRequest.
  Future<Uint8List> command() async {
    while (true) {
      final m = await next();
      if (m[0] != 3) return m;
    }
  }

  Future<Uint8List> request() async {
    final m = await next();
    expect(m[0], 3, reason: 'expected a FramebufferUpdateRequest');
    return m;
  }
}

/// Drives the RFB 3.8 handshake (VNC auth) and ServerInit for an [w]×[h] desktop.
Future<RemoteDesktopSession> _handshake(_Pipe pipe, StreamSettings settings, ConnectionLog log, {int w = 8, int h = 4}) async {
  final opening = const RfbProtocol(_NoJpeg()).open(pipe, settings, password: () async => 'secret', log: log);
  final server = pipe.server;
  pipe.send(ascii.encode('RFB 003.008\n'));
  expect(ascii.decode(await server.read(12)), 'RFB 003.008\n');
  pipe.send([1, 2]);
  expect(await server.u8(), 2);
  final challenge = Uint8List.fromList(List.generate(16, (i) => i * 7));
  pipe.send(challenge);
  expect(await server.read(16), vncAuthResponse('secret', challenge));
  pipe.send(_u32(0));
  expect(await server.u8(), 1, reason: 'shared ClientInit');
  pipe.send([..._u16(w), ..._u16(h), ...List.filled(16, 0), ..._u32(4), ...ascii.encode('demo')]);
  return opening;
}

void main() {
  test('DES matches the textbook vector', () {
    final key = Uint8List.fromList([0x13, 0x34, 0x57, 0x79, 0x9B, 0xBC, 0xDF, 0xF1]);
    final plain = Uint8List.fromList([0x01, 0x23, 0x45, 0x67, 0x89, 0xAB, 0xCD, 0xEF]);
    expect(desEncrypt(key, plain), [0x85, 0xE8, 0x13, 0x54, 0x0F, 0x0A, 0xB4, 0x05]);
  });

  test('FramePacer honours both the frame interval and the bandwidth cap', () {
    final clock = _FakeClock();
    final pacer = FramePacer(fps: 60, maxMbps: 8, clock: clock); // 8 Mbps = 1 byte/µs, 250 KB burst
    pacer.onRequest();
    clock.now = 5000;
    pacer.onReceived(1000);
    expect(pacer.nextDelay().inMicroseconds, 16666 - 5000, reason: 'frame interval dominates');

    clock.now = 40000;
    pacer.onRequest();
    pacer.onReceived(1000000); // overdraws the bucket by ~750 KB
    final wait = pacer.nextDelay().inMicroseconds;
    expect(wait, greaterThan(700000));
    expect(wait, lessThan(760000));

    pacer.configure(fps: 15, maxMbps: 0);
    pacer.onReceived(50000000);
    expect(pacer.nextDelay().inMicroseconds, 66666, reason: 'unlimited bandwidth');
  });

  test('RFB session: auth, decoders, pipelining, quality, input, clipboard, log', () async {
    final pipe = _Pipe();
    final log = ConnectionLog();
    final client = _ClientMessages(pipe.server);
    final session = await _handshake(pipe, const StreamSettings(), log);
    expect(session.name, 'demo');

    // -- client setup: SetPixelFormat (32bpp), SetEncodings, full update request
    final pf = await client.next();
    expect((pf[0], pf[4], pf[7]), (0, 32, 1), reason: 'type 0, 32 bpp, true colour');
    final enc = ByteData.sublistView(await client.next());
    final advertised = [for (var i = 0; i < enc.getUint16(2); i++) enc.getInt32(4 + i * 4)];
    expect(advertised.take(4), [7, 16, 1, 0], reason: 'Tight, ZRLE, CopyRect, Raw');
    // Auto quality starts at JPEG 35: level 3, fine quality 35, chroma 4:2:0, zlib 6.
    expect(advertised, containsAll([-29, -512 + 35, -767, -250, -239, -223, -1063131698]));
    expect(advertised, isNot(contains(-308)), reason: 'no client-driven resizing');
    expect((await client.request())[1], 0, reason: 'first request is non-incremental');

    // -- pipelining: the next request goes out while this update is still arriving
    final zrle = ZLibCodec().encode([
      130, 255, 0, 0, 0, 0, 255, // palette RLE, 2 colours: red, blue
      0 | 128, 5, // 6 × red
      1 | 128, 5, // 6 × blue
    ]);
    final frame = session.frames.first;
    pipe.send([0, 0, ..._u16(5)]);
    expect((await client.request())[1], 1, reason: 'incremental request sent ahead of the rectangles');
    pipe.send([
      ..._rect(0, 0, 2, 1, 0), 10, 20, 30, 0, 40, 50, 60, 0, // Raw
      ..._rect(2, 0, 2, 2, 7), 0x80, 1, 2, 3, // Tight fill
      ..._rect(4, 0, 2, 1, 1), ..._u16(0), ..._u16(0), // CopyRect from (0,0)
      ..._rect(6, 0, 2, 2, 7), 0x40, 1, 1, 9, 9, 9, 7, 7, 7, 0x80, 0x40, // Tight palette, 2 colours
      ..._rect(0, 1, 4, 3, 16), ..._u32(zrle.length), ...zrle, // ZRLE
    ]);
    await frame;

    final px = session.frame.rgba.buffer.asUint32List();
    int at(int x, int y) => px[y * 8 + x];
    expect(at(0, 0), _rgb(10, 20, 30));
    expect(at(1, 0), _rgb(40, 50, 60));
    expect(at(3, 0), _rgb(1, 2, 3), reason: 'Tight fill (row 1 is overwritten by ZRLE)');
    expect(at(4, 0), _rgb(10, 20, 30), reason: 'CopyRect');
    expect((at(6, 0), at(7, 0), at(6, 1), at(7, 1)), (_rgb(7, 7, 7), _rgb(9, 9, 9), _rgb(9, 9, 9), _rgb(7, 7, 7)));
    expect((at(0, 1), at(1, 2), at(2, 2), at(3, 3)), (_rgb(255, 0, 0), _rgb(255, 0, 0), _rgb(0, 0, 255), _rgb(0, 0, 255)));
    expect(session.takeEncodingStats().keys, containsAll(['Raw', 'Tight', 'CopyRect', 'ZRLE']));
    expect(session.takeEncodingStats(), isEmpty, reason: 'stats reset after each read');

    // -- commands; a colour-depth change is ignored mid-stream (it needs a new connection)
    session
      ..applySettings(const StreamSettings(colorDepth: ColorDepth.high, quality: ImageQuality.low))
      ..sendKey(0x61, down: true)
      ..sendPointer(3, 2, 1);
    final reEnc = ByteData.sublistView(await client.command());
    expect(reEnc.getUint8(0), 2, reason: 'quality change re-sends SetEncodings, no SetPixelFormat');
    // Low: JPEG 10 (level 1), chroma 4:2:0, zlib 9.
    expect([for (var i = 0; i < reEnc.getUint16(2); i++) reEnc.getInt32(4 + i * 4)], containsAll([-31, -502, -767, -247]));
    expect(await client.command(), [4, 1, 0, 0, 0, 0, 0, 0x61]);
    expect(await client.command(), [5, 1, 0, 3, 0, 2]);

    // -- extended clipboard: caps exchange, then UTF-8 text both ways
    final clipboard = session.clipboard.first;
    final caps = [..._u32(1 << 24 | 1), ..._u32(1 << 20)];
    pipe.send([3, 0, 0, 0, ..._u32(-caps.length & 0xffffffff), ...caps]);
    final provided = ZLibCodec().encode([..._u32(7), ...utf8.encode('你好'), 0]);
    final provide = [..._u32(1 << 28 | 1), ...provided];
    pipe.send([3, 0, 0, 0, ..._u32(-provide.length & 0xffffffff), ...provide]);
    expect(await clipboard, '你好');
    int flags(Uint8List cut) => ByteData.sublistView(cut).getUint32(8);
    expect(flags(await client.command()) & 1 << 24, isNonZero, reason: 'client caps');
    session.sendClipboard('世界');
    expect(flags(await client.command()), 1 << 27 | 1, reason: 'notify');
    pipe.send([3, 0, 0, 0, ..._u32(-4 & 0xffffffff), ..._u32(1 << 25 | 1)]); // request
    final reply = await client.command();
    expect(flags(reply), 1 << 28 | 1);
    final body = ZLibCodec().decode(reply.sublist(12));
    expect(utf8.decode(body.sublist(4, body.length - 1)), '世界');

    // -- the log tells the story
    final text = log.export();
    expect(text, contains('Security types offered: VncAuth → using VncAuth'));
    expect(text, contains('Desktop "demo" 8×4'));
    expect(text, contains('Server started sending ZRLE (lossless'));
    expect(text, contains('Extended clipboard enabled (UTF-8)'));

    // -- a server disconnect ends the session with a reason
    await pipe._toClient.close();
    expect((await session.closed)?.kind, RemoteErrorKind.disconnected);
    expect(log.export(), contains('Connection lost'));
  });

  test('8-bit colour: format negotiated at open, 1-byte pixels in every decoder', () async {
    final pipe = _Pipe();
    final client = _ClientMessages(pipe.server);
    final session = await _handshake(pipe, const StreamSettings(colorDepth: ColorDepth.low), ConnectionLog(), w: 4, h: 2);
    final pf = await client.next();
    expect((pf[4], pf[5], pf[7], pf[9], pf[11], pf[13]), (8, 8, 1, 7, 7, 3), reason: '8 bpp BGR233');
    await client.next(); // SetEncodings
    await client.request();

    // BGR233: red = 0x07, green = 0x38, blue = 0xC0.
    final zrle = ZLibCodec().encode([1, 0xC0]); // one solid blue tile, 1-byte CPIXEL
    final frame = session.frames.first;
    pipe.send([
      0, 0, ..._u16(3),
      ..._rect(0, 0, 1, 1, 0), 0x07, // Raw red
      ..._rect(1, 0, 1, 1, 7), 0x80, 0x38, // Tight fill green
      ..._rect(0, 1, 4, 1, 16), ..._u32(zrle.length), ...zrle, // ZRLE blue
    ]);
    await frame;
    final px = session.frame.rgba.buffer.asUint32List();
    expect((px[0], px[1], px[4], px[7]), (_rgb(255, 0, 0), _rgb(0, 255, 0), _rgb(0, 0, 255), _rgb(0, 0, 255)));
    await session.close();
  });

  test('JPEG rectangles decode in parallel but are drawn in order', () async {
    final pipe = _Pipe();
    final jpeg = _ControlledJpeg();
    final opening = RfbProtocol(jpeg).open(pipe, const StreamSettings(), password: () async => null, log: ConnectionLog());
    final client = _ClientMessages(pipe.server);
    pipe.send([...ascii.encode('RFB 003.008\n'), 1, 1]);
    await pipe.server.read(13); // version + chosen security type
    pipe.send([..._u32(0)]);
    await pipe.server.u8();
    pipe.send([..._u16(4), ..._u16(1), ...List.filled(16, 0), ..._u32(0)]);
    final session = await opening;
    await client.next(); // SetPixelFormat
    await client.next(); // SetEncodings
    await client.request();

    var framed = false;
    unawaited(session.frames.first.then((_) => framed = true));
    pipe.send([
      0, 0, ..._u16(3),
      ..._rect(0, 0, 1, 1, 7), 0x90, 1, 0xA, // JPEG #1 (1 byte "image")
      ..._rect(1, 0, 1, 1, 7), 0x90, 1, 0xB, // JPEG #2
      ..._rect(2, 0, 2, 1, 1), ..._u16(0), ..._u16(0), // CopyRect from (0,0): must see JPEG #1's pixels
    ]);
    await Future<void>.delayed(const Duration(milliseconds: 20));
    expect(jpeg.pending, hasLength(2), reason: 'both decodes started before either finished');
    expect(framed, isFalse);
    jpeg.pending[1].complete(Uint32List.fromList([_rgb(0, 0, 9)])); // finishes out of order
    jpeg.pending[0].complete(Uint32List.fromList([_rgb(9, 0, 0)]));
    await Future<void>.delayed(const Duration(milliseconds: 20));
    final px = session.frame.rgba.buffer.asUint32List();
    expect(px, [_rgb(9, 0, 0), _rgb(0, 0, 9), _rgb(9, 0, 0), _rgb(0, 0, 9)]);
    expect(framed, isTrue);
    await session.close();
  });

  group('QualityGovernor', () {
    test('drops quality while the link is saturated and frames fall short', () {
      final g = QualityGovernor();
      expect(g.quality, 35);
      expect(g.sample(fps: 40, targetFps: 60, busy: 0.95, jpegShare: 0.8), isTrue);
      expect(g.quality, 25);
      expect(g.sample(fps: 20, targetFps: 60, busy: 0.95, jpegShare: 0.8), isFalse, reason: 'cooldown');
      expect(g.sample(fps: 20, targetFps: 60, busy: 0.95, jpegShare: 0.8), isTrue);
      expect(g.quality, 10, reason: 'far below target: two steps');
    });

    test('leaves quality alone when the screen is idle or quality would not help', () {
      final g = QualityGovernor();
      expect(g.sample(fps: 2, targetFps: 60, busy: 0.05, jpegShare: 0.9), isFalse, reason: 'idle, not congested');
      expect(g.sample(fps: 20, targetFps: 60, busy: 0.95, jpegShare: 0.02), isFalse, reason: 'almost no JPEG');
      expect(g.quality, 35);
    });

    test('raises quality after sustained headroom, up to the ceiling', () {
      final g = QualityGovernor();
      var changes = 0;
      for (var i = 0; i < 60; i++) {
        if (g.sample(fps: 60, targetFps: 60, busy: 0.2, jpegShare: 0.5)) changes++;
      }
      expect(g.quality, QualityGovernor.steps.last);
      expect(changes, QualityGovernor.steps.length - 1 - QualityGovernor.initialStep);
    });
  });

  test('handshake reports unsupported security types', () async {
    final pipe = _Pipe();
    final log = ConnectionLog();
    final opening = const RfbProtocol(_NoJpeg()).open(pipe, const StreamSettings(), password: () async => null, log: log);
    pipe.send([...ascii.encode('RFB 003.889\n'), 2, 19, 30]);
    await expectLater(
      opening,
      throwsA(isA<RemoteException>().having((e) => e.kind, 'kind', RemoteErrorKind.unsupportedSecurity)),
    );
    expect(log.export(), contains('(Apple)'));
  });
}
