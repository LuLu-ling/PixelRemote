import 'dart:async';
import 'dart:math';
import 'dart:ui' as ui;

import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../../application/session_commands.dart';
import '../../domain/entities/keyboard.dart';
import '../../domain/services/remote_desktop.dart';
import '../input/keyboard_translator.dart';

/// Renders the remote framebuffer (aspect-fit) and the remote cursor, and
/// turns local pointer and keyboard input into [SessionCommand]s.
class RemoteView extends StatefulWidget {
  const RemoteView({
    super.key,
    required this.desktop,
    required this.remapper,
    required this.isMac,
    required this.focusNode,
    required this.onCommand,
    this.onPointerAt,
  });

  final RemoteDesktopSession desktop;
  final KeyRemapper remapper;
  final bool isMac;
  final FocusNode focusNode;
  final ValueChanged<SessionCommand> onCommand;

  final ValueChanged<Offset>? onPointerAt;

  @override
  State<RemoteView> createState() => _RemoteViewState();
}

class _RemoteViewState extends State<RemoteView> {
  static const _scrollStep = 40.0;

  late final KeyboardTranslator _keys = KeyboardTranslator(isMac: widget.isMac);
  late final AppLifecycleListener _lifecycle;
  final _pointer = ValueNotifier<Offset?>(null);
  final _subscriptions = <StreamSubscription<Object?>>[];

  ui.Image? _frame, _cursor;
  Offset _hotspot = Offset.zero;
  bool _remoteCursor = false, _converting = false, _dirty = false;
  Rect _viewRect = Rect.zero;
  int _buttons = 0;
  Offset _scroll = Offset.zero;

  @override
  void initState() {
    super.initState();
    _subscriptions
      ..add(widget.desktop.frames.listen((_) => _onFrame()))
      ..add(widget.desktop.cursors.listen(_onCursor));
    _lifecycle = AppLifecycleListener(onInactive: _releaseKeys, onHide: _releaseKeys);
    widget.focusNode.addListener(_onFocusChange);
    _onFrame();
  }

  @override
  void dispose() {
    for (final s in _subscriptions) {
      s.cancel();
    }
    _lifecycle.dispose();
    widget.focusNode.removeListener(_onFocusChange);
    _releaseKeys();
    _pointer.dispose();
    _frame?.dispose();
    _cursor?.dispose();
    super.dispose();
  }

  // ---- rendering -------------------------------------------------------------

  /// Latest-frame-wins: at most one conversion in flight; frames arriving
  /// meanwhile collapse into a single follow-up.
  void _onFrame() {
    if (_converting) {
      _dirty = true;
      return;
    }
    unawaited(_convert());
  }

  Future<void> _convert() async {
    final f = widget.desktop.frame;
    if (f.width == 0 || f.height == 0) return;
    _converting = true;
    _dirty = false;
    try {
      final image = await _toImage(f.rgba, f.width, f.height);
      if (!mounted) return image.dispose();
      setState(() {
        _frame?.dispose();
        _frame = image;
      });
    } finally {
      _converting = false;
    }
    if (_dirty && mounted) _onFrame();
  }

  Future<void> _onCursor(RemoteCursor c) async {
    final image = c.isHidden ? null : await _toImage(c.rgba, c.width, c.height);
    if (!mounted) return image?.dispose();
    setState(() {
      _cursor?.dispose();
      _cursor = image;
      _hotspot = Offset(c.hotX.toDouble(), c.hotY.toDouble());
      _remoteCursor = true;
    });
  }

  /// The pixels are copied synchronously, so the framebuffer may keep changing.
  static Future<ui.Image> _toImage(Uint8List rgba, int width, int height) async {
    final buffer = await ui.ImmutableBuffer.fromUint8List(rgba);
    final descriptor = ui.ImageDescriptor.raw(buffer, width: width, height: height, pixelFormat: ui.PixelFormat.rgba8888);
    final codec = await descriptor.instantiateCodec();
    final frame = await codec.getNextFrame();
    codec.dispose();
    descriptor.dispose();
    buffer.dispose();
    return frame.image;
  }

  // ---- input -----------------------------------------------------------------

  void _send(SessionCommand command) => widget.onCommand(command);

  KeyEventResult _onKey(FocusNode node, KeyEvent event) {
    for (final (keysym, down) in _keys.translate(event, widget.remapper)) {
      _send(KeyCommand(keysym, down: down));
    }
    return KeyEventResult.handled;
  }

  void _releaseKeys() {
    for (final (keysym, down) in _keys.releaseAll()) {
      _send(KeyCommand(keysym, down: down));
    }
  }

  void _onFocusChange() {
    if (!widget.focusNode.hasFocus) _releaseKeys();
  }

  (int, int)? _toRemote(Offset local) {
    final f = widget.desktop.frame;
    if (_viewRect.isEmpty || f.width == 0) return null;
    return (
      ((local.dx - _viewRect.left) / _viewRect.width * f.width).floor().clamp(0, f.width - 1),
      ((local.dy - _viewRect.top) / _viewRect.height * f.height).floor().clamp(0, f.height - 1),
    );
  }

  /// Flutter button bits → RFB mask (1 left, 2 middle, 4 right).
  static int _mask(int buttons) =>
      (buttons & kPrimaryButton != 0 ? 1 : 0) |
      (buttons & kMiddleMouseButton != 0 ? 2 : 0) |
      (buttons & kSecondaryButton != 0 ? 4 : 0);

  void _onPointer(PointerEvent e) {
    widget.onPointerAt?.call(e.localPosition);
    _pointer.value = e.localPosition;
    if (e is PointerDownEvent && !widget.focusNode.hasFocus) widget.focusNode.requestFocus();
    final p = _toRemote(e.localPosition);
    if (p == null) return;
    _buttons = _mask(e.buttons);
    _send(PointerCommand(p.$1, p.$2, _buttons));
  }

  void _onSignal(PointerSignalEvent e) {
    if (e is PointerScrollEvent) _wheel(e.localPosition, e.scrollDelta, discrete: e.kind == PointerDeviceKind.mouse);
  }

  /// Trackpads deliver continuous deltas; accumulate them into wheel steps.
  void _wheel(Offset at, Offset delta, {required bool discrete}) {
    final p = _toRemote(at);
    if (p == null) return;
    _scroll += delta;
    var dx = (_scroll.dx / _scrollStep).truncate(), dy = (_scroll.dy / _scrollStep).truncate();
    if (discrete && dx == 0 && dy == 0) {
      dx = delta.dx.sign.toInt();
      dy = delta.dy.sign.toInt();
    }
    if (dx == 0 && dy == 0) return;
    _scroll = discrete ? Offset.zero : _scroll - Offset(dx * _scrollStep, dy * _scrollStep);
    _send(ScrollCommand(p.$1, p.$2, _buttons, dx: dx, dy: dy));
  }

  // ---- layout ----------------------------------------------------------------

  static Rect _fit(Size box, int w, int h) {
    if (w == 0 || h == 0) return Rect.zero;
    final scale = min(box.width / w, box.height / h);
    final size = Size(w * scale, h * scale);
    return Offset((box.width - size.width) / 2, (box.height - size.height) / 2) & size;
  }

  @override
  Widget build(BuildContext context) {
    return Focus(
      focusNode: widget.focusNode,
      autofocus: true,
      onKeyEvent: _onKey,
      child: LayoutBuilder(
        builder: (context, constraints) {
          final size = constraints.biggest;
          final f = widget.desktop.frame;
          _viewRect = _fit(size, f.width, f.height);
          return MouseRegion(
            cursor: _remoteCursor ? SystemMouseCursors.none : SystemMouseCursors.basic,
            onExit: (_) => _pointer.value = null,
            child: Listener(
              onPointerDown: _onPointer,
              onPointerMove: _onPointer,
              onPointerUp: _onPointer,
              onPointerHover: _onPointer,
              onPointerSignal: _onSignal,
              onPointerPanZoomUpdate: (e) => _wheel(e.localPosition, -e.panDelta, discrete: false),
              child: CustomPaint(
                size: size,
                painter: _FramePainter(_frame, _viewRect),
                foregroundPainter: _CursorPainter(
                  _pointer,
                  _cursor,
                  _hotspot,
                  f.width == 0 ? 1 : _viewRect.width / f.width,
                ),
              ),
            ),
          );
        },
      ),
    );
  }
}

class _FramePainter extends CustomPainter {
  _FramePainter(this.image, this.target);

  final ui.Image? image;
  final Rect target;

  @override
  void paint(Canvas canvas, Size size) {
    final img = image;
    if (img == null) return;
    final source = Rect.fromLTWH(0, 0, img.width.toDouble(), img.height.toDouble());
    final exact = (target.width - img.width).abs() < 0.5 && (target.height - img.height).abs() < 0.5;
    canvas.drawImageRect(img, source, target, Paint()..filterQuality = exact ? FilterQuality.none : FilterQuality.medium);
  }

  @override
  bool shouldRepaint(_FramePainter old) => old.image != image || old.target != target;
}

/// Draws the remote cursor at the local pointer, so it moves with zero lag.
class _CursorPainter extends CustomPainter {
  _CursorPainter(this.pointer, this.image, this.hotspot, this.scale) : super(repaint: pointer);

  final ValueNotifier<Offset?> pointer;
  final ui.Image? image;
  final Offset hotspot;
  final double scale;

  @override
  void paint(Canvas canvas, Size size) {
    final at = pointer.value, img = image;
    if (at == null || img == null) return;
    canvas
      ..save()
      ..translate(at.dx, at.dy)
      ..scale(scale)
      ..drawImage(img, -hotspot, Paint()..filterQuality = FilterQuality.medium)
      ..restore();
  }

  @override
  bool shouldRepaint(_CursorPainter old) => old.image != image || old.scale != scale || old.hotspot != hotspot;
}
