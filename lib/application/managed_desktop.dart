import 'dart:async';

import '../domain/entities/stream_settings.dart';
import '../domain/errors.dart';
import '../domain/services/remote_desktop.dart';
import '../domain/services/session_log.dart';

typedef DesktopOpener = Future<RemoteDesktopSession> Function(StreamSettings settings);
typedef DepthRejection = ({ColorDepth rejected, ColorDepth kept});

/// Decorator that keeps one live [RemoteDesktopSession] and replaces it when a
/// setting can only take effect on a new connection (the colour depth).
///
/// Switching is make-before-break: the new connection is opened next to the
/// old one and swapped in only after it delivers its first frame. If the
/// server rejects it, the old connection carries on and [rejections] reports
/// which depth was kept, so the session is never lost to a settings change.
final class ManagedDesktop implements RemoteDesktopSession {
  ManagedDesktop._(this._open, this._current, this._settings, this._log) : _depth = _settings.colorDepth {
    _attach(_current);
  }

  static Future<ManagedDesktop> start(DesktopOpener open, StreamSettings settings, SessionLog log) async =>
      ManagedDesktop._(open, await open(settings), settings, log);

  static const _src = 'session', _firstFrameTimeout = Duration(seconds: 10);

  final DesktopOpener _open;
  final SessionLog _log;
  final _frames = StreamController<void>.broadcast(sync: true);
  final _cursors = StreamController<RemoteCursor>.broadcast();
  final _clipboard = StreamController<String>.broadcast();
  final _rejections = StreamController<DepthRejection>.broadcast();
  final _closed = Completer<RemoteException?>();
  List<StreamSubscription<Object?>> _subscriptions = const [];

  RemoteDesktopSession _current;
  StreamSettings _settings;
  ColorDepth _depth; // what the live connection actually uses
  (int, int)? _lastResize;
  int _generation = 0, _switches = 0;
  RemoteDesktopSession? _dropped; // a live stream that closed while a switch was running
  RemoteException? _dropReason;

  Stream<DepthRejection> get rejections => _rejections.stream;

  @override
  String get name => _current.name;

  @override
  FrameView get frame => _current.frame;

  @override
  Stream<void> get frames => _frames.stream;

  @override
  Stream<RemoteCursor> get cursors => _cursors.stream;

  @override
  Stream<String> get clipboard => _clipboard.stream;

  @override
  bool get canResize => _current.canResize;

  @override
  Future<RemoteException?> get closed => _closed.future;

  @override
  void sendKey(int keysym, {required bool down}) => _current.sendKey(keysym, down: down);

  @override
  void sendPointer(int x, int y, int buttons) => _current.sendPointer(x, y, buttons);

  @override
  void sendClipboard(String text) => _current.sendClipboard(text);

  @override
  void refresh() => _current.refresh();

  @override
  Map<String, int> takeEncodingStats() => _current.takeEncodingStats();

  @override
  void resize(int width, int height) {
    _lastResize = (width, height);
    _current.resize(width, height);
  }

  @override
  void applySettings(StreamSettings settings) {
    _settings = settings;
    _current.applySettings(settings.copyWith(colorDepth: _depth));
    if (settings.colorDepth == _depth) {
      _generation++; // cancels a switch that is no longer wanted
    } else {
      unawaited(_switchTo(settings.colorDepth));
    }
  }

  @override
  Future<void> close() async {
    _generation++;
    await _current.close();
    _finish(null);
  }

  Future<void> _switchTo(ColorDepth target) async {
    final generation = ++_generation;
    final kept = _depth;
    _log.info(_src, 'Colour depth ${kept.bits}-bit → ${target.bits}-bit: opening a new stream alongside the current one');
    _switches++;
    RemoteDesktopSession? fresh;
    try {
      fresh = await _open(_settings.copyWith(colorDepth: target));
      final firstFrame = fresh.frames.first;
      final early = fresh.closed.then((reason) => throw reason ?? const RemoteException(RemoteErrorKind.disconnected));
      await Future.any([firstFrame, early]).timeout(_firstFrameTimeout);
      if (generation != _generation || _closed.isCompleted) {
        await fresh.close();
        return;
      }
      final old = _current;
      _current = fresh;
      _depth = target;
      _attach(fresh);
      fresh.applySettings(_settings.copyWith(colorDepth: target));
      if (_lastResize case (final w, final h)) fresh.resize(w, h);
      _log.info(_src, 'Now streaming in ${target.bits}-bit colour');
      if (!_frames.isClosed) _frames.add(null); // show the new framebuffer right away
      await old.close();
    } catch (e) {
      await fresh?.close();
      if (generation != _generation) return;
      _log.warn(_src, 'The server did not accept ${target.bits}-bit colour ($e); keeping ${kept.bits}-bit');
      _settings = _settings.copyWith(colorDepth: kept);
      if (!_rejections.isClosed) _rejections.add((rejected: target, kept: kept));
    } finally {
      if (--_switches == 0 && _dropped != null) {
        if (identical(_dropped, _current)) _finish(_dropReason);
        _dropped = _dropReason = null;
      }
    }
  }

  void _attach(RemoteDesktopSession s) {
    for (final sub in _subscriptions) {
      sub.cancel();
    }
    _subscriptions = [
      s.frames.listen((_) => _frames.isClosed ? null : _frames.add(null)),
      s.cursors.listen((c) => _cursors.isClosed ? null : _cursors.add(c)),
      s.clipboard.listen((t) => _clipboard.isClosed ? null : _clipboard.add(t)),
    ];
    s.closed.then((reason) {
      if (!identical(s, _current)) return;
      if (_switches == 0) return _finish(reason);
      // A server that allows only one viewer drops the old stream when the new
      // one connects; let the switch decide whether the session survives.
      _dropped = s;
      _dropReason = reason ?? const RemoteException(RemoteErrorKind.disconnected);
    });
  }

  void _finish(RemoteException? reason) {
    if (_closed.isCompleted) return;
    _closed.complete(reason);
    for (final sub in _subscriptions) {
      sub.cancel();
    }
    // Deferred: this may run inside a (synchronous) frame event.
    scheduleMicrotask(() {
      _frames.close();
      _cursors.close();
      _clipboard.close();
      _rejections.close();
    });
  }
}
