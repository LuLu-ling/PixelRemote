import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:pixel_remote/data/rfb/byte_reader.dart';
import 'package:pixel_remote/data/rfb/decoders/rect_decoder.dart';
import 'package:pixel_remote/data/rfb/frame_pacer.dart';
import 'package:pixel_remote/data/rfb/rfb_handshake.dart';
import 'package:pixel_remote/data/rfb/rfb_session.dart';
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
    expect(pacer.onFrame(1000).inMicroseconds, 16666 - 5000, reason: 'frame interval dominates');

    pacer.onRequest();
    clock.now = 40000;
    // A 1 MB frame overdraws the bucket by ~750 KB (minus refill): wait until it is paid back.
    final wait = pacer.onFrame(1000000).inMicroseconds;
    expect(wait, greaterThan(700000));
    expect(wait, lessThan(760000));

    pacer.configure(fps: 15, maxMbps: 0);
    pacer.onRequest();
    expect(pacer.onFrame(50000000).inMicroseconds, 66666, reason: 'unlimited bandwidth');
  });

  test('RFB session: auth, decoders, resize, pixel-format switch, input and clipboard', () async {
    final pipe = _Pipe();
    final server = pipe.server;
    final opening = const RfbProtocol(_NoJpeg()).open(pipe, const StreamSettings(), password: () async => 'secret');

    // -- handshake: RFB 3.8 with VNC authentication
    pipe.send(ascii.encode('RFB 003.008\n'));
    expect(ascii.decode(await server.read(12)), 'RFB 003.008\n');
    pipe.send([1, 2]);
    expect(await server.u8(), 2);
    final challenge = Uint8List.fromList(List.generate(16, (i) => i * 7));
    pipe.send(challenge);
    expect(await server.read(16), vncAuthResponse('secret', challenge));
    pipe.send(_u32(0));
    expect(await server.u8(), 1, reason: 'shared ClientInit');
    pipe.send([..._u16(8), ..._u16(4), ...List.filled(16, 0), ..._u32(4), ...ascii.encode('demo')]);
    final RemoteDesktopSession session = await opening;
    expect(session.name, 'demo');

    // -- client setup: SetPixelFormat (32bpp), SetEncodings, full update request
    final pf = await server.read(20);
    expect((pf[0], pf[4], pf[7]), (0, 32, 1), reason: 'type 0, 32 bpp, true colour');
    final encodingCount = ByteData.sublistView(await server.read(4)).getUint16(2);
    final encodings = ByteData.sublistView(await server.read(encodingCount * 4));
    final advertised = [for (var i = 0; i < encodingCount; i++) encodings.getInt32(i * 4)];
    expect(advertised.take(4), [7, 16, 1, 0], reason: 'Tight, ZRLE, CopyRect, Raw');
    expect(advertised, containsAll([-27, -250, -239, -308, -1063131698]), reason: 'JPEG 5, zlib 6, cursor, ExtDesktopSize, ExtClipboard');
    expect((await server.read(10))[1], 0, reason: 'first request is non-incremental');

    // -- one update exercising every decoder
    final zrle = ZLibCodec().encode([
      130, 255, 0, 0, 0, 0, 255, // palette RLE, 2 colours: red, blue
      0 | 128, 5, // 6 × red
      1 | 128, 5, // 6 × blue
    ]);
    final update = [
      0, 0, ..._u16(6),
      ..._rect(0, 0, 2, 1, 0), 10, 20, 30, 0, 40, 50, 60, 0, // Raw
      ..._rect(2, 0, 2, 2, 7), 0x80, 1, 2, 3, // Tight fill
      ..._rect(4, 0, 2, 1, 1), ..._u16(0), ..._u16(0), // CopyRect from (0,0)
      ..._rect(6, 0, 2, 2, 7), 0x40, 1, 1, 9, 9, 9, 7, 7, 7, 0x80, 0x40, // Tight palette, 2 colours
      ..._rect(0, 1, 4, 3, 16), ..._u32(zrle.length), ...zrle, // ZRLE
      ..._rect(0, 0, 8, 4, -308), 1, 0, 0, 0, ..._u32(7), ..._u16(0), ..._u16(0), ..._u16(8), ..._u16(4), ..._u32(0),
    ];
    var frame = session.frames.first;
    pipe.send(update);
    await frame;

    final px = session.frame.rgba.buffer.asUint32List();
    int at(int x, int y) => px[y * 8 + x];
    expect(at(0, 0), _rgb(10, 20, 30));
    expect(at(1, 0), _rgb(40, 50, 60));
    expect(at(3, 0), _rgb(1, 2, 3), reason: "Tight fill (row 1 is overwritten by ZRLE)");
    expect(at(4, 0), _rgb(10, 20, 30), reason: 'CopyRect');
    expect((at(6, 0), at(7, 0), at(6, 1), at(7, 1)), (_rgb(7, 7, 7), _rgb(9, 9, 9), _rgb(9, 9, 9), _rgb(7, 7, 7)));
    expect((at(0, 1), at(1, 2), at(2, 2), at(3, 3)), (_rgb(255, 0, 0), _rgb(255, 0, 0), _rgb(0, 0, 255), _rgb(0, 0, 255)));
    expect(session.canResize, isTrue);

    // -- commands go out in order, before the paced update request
    session
      ..resize(1024, 768)
      ..sendKey(0x61, down: true)
      ..sendPointer(3, 2, 1)
      ..applySettings(const StreamSettings(colorDepth: ColorDepth.high));
    final setSize = await server.read(24);
    // SetDesktopSize 1024×768, one screen keeping the server's screen id 7.
    expect(setSize, [251, 0, 4, 0, 3, 0, 1, 0, 0, 0, 0, 7, 0, 0, 0, 0, 4, 0, 3, 0, 0, 0, 0, 0]);
    expect(await server.read(8), [4, 1, 0, 0, 0, 0, 0, 0x61]);
    expect(await server.read(6), [5, 1, 0, 3, 0, 2]);

    // -- the colour-depth change is applied between updates, followed by a full refresh
    final pf16 = await server.read(20);
    expect((pf16[0], pf16[4]), (0, 16));
    expect((await server.read(10))[1], 0);
    frame = session.frames.first;
    pipe.send([0, 0, ..._u16(1), ..._rect(0, 0, 1, 1, 0), 0x00, 0xF8]); // RGB565 pure red
    await frame;
    expect(session.frame.rgba.buffer.asUint32List()[0], _rgb(255, 0, 0));

    // -- extended clipboard: caps exchange, then UTF-8 text both ways
    final clipboard = session.clipboard.first;
    final caps = [..._u32(1 << 24 | 1), ..._u32(1 << 20)];
    pipe.send([3, 0, 0, 0, ..._u32(-caps.length & 0xffffffff), ...caps]);
    final provided = ZLibCodec().encode([..._u32(7), ...utf8.encode('你好'), 0]);
    final provide = [..._u32(1 << 28 | 1), ...provided];
    pipe.send([3, 0, 0, 0, ..._u32(-provide.length & 0xffffffff), ...provide]);
    expect(await clipboard, '你好');

    // Skip any paced update requests interleaved with the clipboard replies.
    Future<ByteData> nextCut() async {
      while (true) {
        final type = (await server.read(1))[0];
        if (type == 3) {
          await server.read(9);
          continue;
        }
        expect(type, 6);
        final rest = ByteData.sublistView(await server.read(7));
        return ByteData.sublistView(await server.read(-rest.getInt32(3)));
      }
    }

    expect((await nextCut()).getUint32(0) & 1 << 24, isNonZero, reason: 'client caps');
    session.sendClipboard('世界');
    expect((await nextCut()).getUint32(0), 1 << 27 | 1, reason: 'notify');
    pipe.send([3, 0, 0, 0, ..._u32(-4 & 0xffffffff), ..._u32(1 << 25 | 1)]); // request
    final reply = await nextCut();
    expect(reply.getUint32(0), 1 << 28 | 1);
    final body = ZLibCodec().decode(reply.buffer.asUint8List(reply.offsetInBytes + 4));
    expect(utf8.decode(body.sublist(4, body.length - 1)), '世界');

    // -- a server disconnect ends the session with a reason
    await pipe._toClient.close();
    expect((await session.closed)?.kind, RemoteErrorKind.disconnected);
  });

  test('handshake reports unsupported security types', () async {
    final pipe = _Pipe();
    final opening = const RfbProtocol(_NoJpeg()).open(pipe, const StreamSettings(), password: () async => null);
    pipe.send([...ascii.encode('RFB 003.008\n'), 2, 19, 30]);
    await expectLater(
      opening,
      throwsA(isA<RemoteException>().having((e) => e.kind, 'kind', RemoteErrorKind.unsupportedSecurity)),
    );
  });
}
