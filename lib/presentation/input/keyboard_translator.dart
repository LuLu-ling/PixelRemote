import 'package:flutter/services.dart';

import '../../domain/entities/keyboard.dart';

/// Turns Flutter key events into X11 keysyms (the RFB key vocabulary).
///
/// The keysym chosen at key-down is remembered per physical key so the
/// matching key-up always releases the same symbol, even if modifiers or
/// the mapping changed in between.
final class KeyboardTranslator {
  KeyboardTranslator({required this.isMac});

  final bool isMac;
  final _down = <PhysicalKeyboardKey, int>{};

  /// Returns `(keysym, down)` pairs to send.
  List<(int, bool)> translate(KeyEvent event, KeyRemapper remapper) {
    if (event is KeyUpEvent) {
      final keysym = _down.remove(event.physicalKey);
      return keysym == null ? const [] : [(keysym, false)];
    }
    final held = _down[event.physicalKey];
    if (held != null) return [(held, true)]; // auto-repeat
    final keysym = keysymFor(event);
    if (keysym == null) return const [];
    return [(_down[event.physicalKey] = remapper.map(keysym), true)];
  }

  /// Releases everything still held, e.g. when the window loses focus.
  List<(int, bool)> releaseAll() {
    final released = [for (final k in _down.values) (k, false)];
    _down.clear();
    return released;
  }

  int? keysymFor(KeyEvent event) {
    final special = _special[event.logicalKey];
    if (special != null) return special;

    // With shortcut modifiers held, send the unmodified key (Ctrl+C, not ETX;
    // ⌥+A, not å) so remote shortcuts work. AltGr still types its character.
    final keys = HardwareKeyboard.instance;
    final altGr = !isMac && keys.isPhysicalKeyPressed(PhysicalKeyboardKey.altRight);
    final shortcut = !altGr && (keys.isControlPressed || keys.isMetaPressed || (isMac && keys.isAltPressed));

    final runes = event.character?.runes;
    if (!shortcut && runes != null && runes.length == 1) {
      final c = runes.first;
      if (c >= 0x20 && c != 0x7f) return _unicode(c);
    }
    final id = event.logicalKey.keyId;
    if ((id & LogicalKeyboardKey.planeMask) == LogicalKeyboardKey.unicodePlane && id >= 0x20) return _unicode(id);
    return null;
  }

  /// Latin-1 maps 1:1; everything else uses the Unicode keysym range.
  static int _unicode(int codePoint) => codePoint < 0x100 ? codePoint : 0x01000000 | codePoint;

  static final Map<LogicalKeyboardKey, int> _special = {
    LogicalKeyboardKey.backspace: 0xff08,
    LogicalKeyboardKey.tab: Keysym.tab,
    LogicalKeyboardKey.enter: 0xff0d,
    LogicalKeyboardKey.escape: 0xff1b,
    LogicalKeyboardKey.delete: Keysym.delete,
    LogicalKeyboardKey.home: 0xff50,
    LogicalKeyboardKey.arrowLeft: 0xff51,
    LogicalKeyboardKey.arrowUp: 0xff52,
    LogicalKeyboardKey.arrowRight: 0xff53,
    LogicalKeyboardKey.arrowDown: 0xff54,
    LogicalKeyboardKey.pageUp: 0xff55,
    LogicalKeyboardKey.pageDown: 0xff56,
    LogicalKeyboardKey.end: 0xff57,
    LogicalKeyboardKey.insert: 0xff63,
    LogicalKeyboardKey.printScreen: Keysym.print,
    LogicalKeyboardKey.pause: 0xff13,
    LogicalKeyboardKey.scrollLock: 0xff14,
    LogicalKeyboardKey.contextMenu: 0xff67,
    LogicalKeyboardKey.numLock: 0xff7f,
    LogicalKeyboardKey.capsLock: 0xffe5,
    LogicalKeyboardKey.shiftLeft: Keysym.shiftL,
    LogicalKeyboardKey.shiftRight: 0xffe2,
    LogicalKeyboardKey.controlLeft: Keysym.controlL,
    LogicalKeyboardKey.controlRight: Keysym.controlR,
    LogicalKeyboardKey.altLeft: Keysym.altL,
    LogicalKeyboardKey.altRight: Keysym.altR,
    LogicalKeyboardKey.metaLeft: Keysym.superL,
    LogicalKeyboardKey.metaRight: Keysym.superR,
    LogicalKeyboardKey.altGraph: 0xfe03,
    LogicalKeyboardKey.numpadEnter: 0xff8d,
    LogicalKeyboardKey.numpadMultiply: 0xffaa,
    LogicalKeyboardKey.numpadAdd: 0xffab,
    LogicalKeyboardKey.numpadSubtract: 0xffad,
    LogicalKeyboardKey.numpadDecimal: 0xffae,
    LogicalKeyboardKey.numpadDivide: 0xffaf,
    LogicalKeyboardKey.numpadEqual: 0xffbd,
    for (final (i, k) in const [
      LogicalKeyboardKey.numpad0, LogicalKeyboardKey.numpad1, LogicalKeyboardKey.numpad2, //
      LogicalKeyboardKey.numpad3, LogicalKeyboardKey.numpad4, LogicalKeyboardKey.numpad5,
      LogicalKeyboardKey.numpad6, LogicalKeyboardKey.numpad7, LogicalKeyboardKey.numpad8,
      LogicalKeyboardKey.numpad9,
    ].indexed)
      k: 0xffb0 + i,
    for (final (i, k) in const [
      LogicalKeyboardKey.f1, LogicalKeyboardKey.f2, LogicalKeyboardKey.f3, LogicalKeyboardKey.f4, //
      LogicalKeyboardKey.f5, LogicalKeyboardKey.f6, LogicalKeyboardKey.f7, LogicalKeyboardKey.f8,
      LogicalKeyboardKey.f9, LogicalKeyboardKey.f10, LogicalKeyboardKey.f11, LogicalKeyboardKey.f12,
      LogicalKeyboardKey.f13, LogicalKeyboardKey.f14, LogicalKeyboardKey.f15, LogicalKeyboardKey.f16,
      LogicalKeyboardKey.f17, LogicalKeyboardKey.f18, LogicalKeyboardKey.f19, LogicalKeyboardKey.f20,
      LogicalKeyboardKey.f21, LogicalKeyboardKey.f22, LogicalKeyboardKey.f23, LogicalKeyboardKey.f24,
    ].indexed)
      k: 0xffbe + i,
  };
}
