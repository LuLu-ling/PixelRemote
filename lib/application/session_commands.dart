import '../core/command.dart';
import '../domain/entities/stream_settings.dart';
import '../domain/services/remote_desktop.dart';

/// Every viewer action against a live session is one of these commands,
/// dispatched through the session's [CommandInvoker].
typedef SessionCommand = Command<RemoteDesktopSession>;

final class KeyCommand implements SessionCommand {
  const KeyCommand(this.keysym, {required this.down});

  final int keysym;
  final bool down;

  @override
  void execute(RemoteDesktopSession s) => s.sendKey(keysym, down: down);
}

/// Presses [keysyms] in order and releases them in reverse (e.g. Ctrl+Alt+Del).
final class KeyComboCommand implements SessionCommand {
  const KeyComboCommand(this.keysyms);

  final List<int> keysyms;

  @override
  void execute(RemoteDesktopSession s) {
    for (final k in keysyms) {
      s.sendKey(k, down: true);
    }
    for (final k in keysyms.reversed) {
      s.sendKey(k, down: false);
    }
  }
}

final class PointerCommand implements SessionCommand {
  const PointerCommand(this.x, this.y, this.buttons);

  final int x, y, buttons;

  @override
  void execute(RemoteDesktopSession s) => s.sendPointer(x, y, buttons);
}

/// Wheel steps become clicks of RFB buttons 4–7 (up, down, left, right).
final class ScrollCommand implements SessionCommand {
  const ScrollCommand(this.x, this.y, this.buttons, {this.dx = 0, this.dy = 0});

  final int x, y, buttons, dx, dy;

  @override
  void execute(RemoteDesktopSession s) {
    void click(int mask, int steps) {
      for (var i = 0; i < steps.abs(); i++) {
        s.sendPointer(x, y, buttons | mask);
        s.sendPointer(x, y, buttons);
      }
    }

    click(dy < 0 ? 8 : 16, dy);
    click(dx < 0 ? 32 : 64, dx);
  }
}

final class ClipboardCommand implements SessionCommand {
  const ClipboardCommand(this.text);

  final String text;

  @override
  void execute(RemoteDesktopSession s) => s.sendClipboard(text);
}

final class ApplySettingsCommand implements SessionCommand {
  const ApplySettingsCommand(this.settings);

  final StreamSettings settings;

  @override
  void execute(RemoteDesktopSession s) => s.applySettings(settings);
}

final class ResizeCommand implements SessionCommand {
  const ResizeCommand(this.width, this.height);

  final int width, height;

  @override
  void execute(RemoteDesktopSession s) => s.resize(width, height);
}

final class RefreshCommand implements SessionCommand {
  const RefreshCommand();

  @override
  void execute(RemoteDesktopSession s) => s.refresh();
}
