import 'package:flutter/widgets.dart';
import 'package:window_manager/window_manager.dart';

import '../../domain/services/platform_services.dart';

/// [WindowController] on top of window_manager's native API.
final class NativeWindowController implements WindowController {
  NativeWindowController._(this._window);

  /// Configures the main window; falls back to a no-op where unsupported.
  static WindowController create({required String title, required Size size, required Size minimumSize}) {
    try {
      final window = WindowManager.instance.getCurrent();
      if (window == null) return _NoopWindowController();
      window
        ..title = title
        ..minimumSize = minimumSize.toNative()
        ..setSize(size.toNative(), false)
        ..center();
      return NativeWindowController._(window);
    } catch (_) {
      return _NoopWindowController();
    }
  }

  final Window _window;

  @override
  bool get isFullScreen => _window.isFullScreen;

  @override
  set isFullScreen(bool value) => _window.isFullScreen = value;

  @override
  set title(String value) => _window.title = value;
}

final class _NoopWindowController implements WindowController {
  @override
  bool isFullScreen = false;

  @override
  set title(String value) {}
}
