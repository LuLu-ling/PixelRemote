import 'dart:async';
import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:pixel_remote/application/connection_log.dart';
import 'package:pixel_remote/application/managed_desktop.dart';
import 'package:pixel_remote/domain/entities/stream_settings.dart';
import 'package:pixel_remote/domain/errors.dart';
import 'package:pixel_remote/domain/services/remote_desktop.dart';

final class _Desktop implements RemoteDesktopSession, FrameView {
  _Desktop(this.depth);

  final ColorDepth depth;
  final _frames = StreamController<void>.broadcast(sync: true);
  final _closed = Completer<RemoteException?>();
  final applied = <StreamSettings>[];
  bool closedByViewer = false;

  void emitFrame() => _frames.add(null);
  void drop() => _closed.isCompleted ? null : _closed.complete(const RemoteException(RemoteErrorKind.disconnected));

  @override
  int get width => 4;
  @override
  int get height => 4;
  @override
  Uint8List get rgba => Uint8List(64);
  @override
  String get name => 'fake ${depth.bits}';
  @override
  FrameView get frame => this;
  @override
  Stream<void> get frames => _frames.stream;
  @override
  Stream<RemoteCursor> get cursors => const Stream.empty();
  @override
  Stream<String> get clipboard => const Stream.empty();
  @override
  Future<RemoteException?> get closed => _closed.future;
  @override
  void sendKey(int keysym, {required bool down}) {}
  @override
  void sendPointer(int x, int y, int buttons) {}
  @override
  void sendClipboard(String text) {}
  @override
  void applySettings(StreamSettings settings) => applied.add(settings);
  @override
  void refresh() {}
  @override
  Map<String, int> takeEncodingStats() => const {};
  @override
  Future<void> close() async {
    closedByViewer = true;
    if (!_closed.isCompleted) _closed.complete(null);
  }
}

void main() {
  late List<_Desktop> opened;
  late ManagedDesktop desktop;

  Future<void> settle() => Future<void>.delayed(Duration.zero);

  setUp(() async {
    opened = [];
    desktop = await ManagedDesktop.start(
      (s) async => _Desktop(s.colorDepth)..also(opened.add),
      const StreamSettings(),
      ConnectionLog(),
    );
  });

  test('switches colour depth make-before-break', () async {
    desktop.applySettings(const StreamSettings(colorDepth: ColorDepth.low));
    await settle();
    expect(opened.map((d) => d.depth), [ColorDepth.full, ColorDepth.low]);
    expect(desktop.name, 'fake 24', reason: 'old stream stays live until the new one has a frame');

    final redraw = desktop.frames.first;
    opened[1].emitFrame();
    await redraw;
    await settle();
    expect(desktop.name, 'fake 8');
    expect(opened[0].closedByViewer, isTrue);
    expect(opened[0].applied.last.colorDepth, ColorDepth.full, reason: 'a live stream never sees a depth change');
  });

  test('keeps the old stream when the server rejects the new depth', () async {
    final rejection = desktop.rejections.first;
    desktop.applySettings(const StreamSettings(colorDepth: ColorDepth.low));
    await settle();
    opened[1].drop(); // e.g. the server closes the connection after SetPixelFormat
    expect(await rejection, (rejected: ColorDepth.low, kept: ColorDepth.full));
    expect(desktop.name, 'fake 24');
    var ended = false;
    unawaited(desktop.closed.then((_) => ended = true));
    await settle();
    expect(ended, isFalse);
  });

  test('survives a single-viewer server that drops the old stream on reconnect', () async {
    desktop.applySettings(const StreamSettings(colorDepth: ColorDepth.high));
    await settle();
    opened[0].drop();
    opened[1].emitFrame();
    await settle();
    expect(desktop.name, 'fake 16');
    var ended = false;
    unawaited(desktop.closed.then((_) => ended = true));
    await settle();
    expect(ended, isFalse);
  });

  test('ends the session when the old stream drops and the new one fails', () async {
    desktop.applySettings(const StreamSettings(colorDepth: ColorDepth.high));
    await settle();
    opened[0].drop();
    opened[1].drop();
    expect((await desktop.closed)?.kind, RemoteErrorKind.disconnected);
  });

  test('switching back before the new stream is ready cancels the switch', () async {
    desktop.applySettings(const StreamSettings(colorDepth: ColorDepth.low));
    await settle();
    desktop.applySettings(const StreamSettings());
    opened[1].emitFrame();
    await settle();
    expect(desktop.name, 'fake 24');
    expect(opened[1].closedByViewer, isTrue);
  });
}

extension<T> on T {
  T also(void Function(T) f) {
    f(this);
    return this;
  }
}
