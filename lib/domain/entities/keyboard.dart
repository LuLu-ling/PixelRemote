enum HostOs {
  macos,
  windows,
  linux,
  unknown;

  bool get isMac => this == macos;
}

enum KeyMappingMode { auto, off, ctrlCmd, altCmd }

/// X11 keysyms (the RFB key vocabulary) referenced outside the key tables.
abstract final class Keysym {
  static const shiftL = 0xffe1;
  static const controlL = 0xffe3;
  static const controlR = 0xffe4;
  static const altL = 0xffe9;
  static const altR = 0xffea;
  static const superL = 0xffeb;
  static const superR = 0xffec;
  static const tab = 0xff09;
  static const delete = 0xffff;
  static const print = 0xff61;
}

/// Translates modifier keysyms between macOS and PC conventions.
/// ⌘ travels as Super, which macOS VNC servers treat as Command.
final class KeyRemapper {
  const KeyRemapper._(this.effective, this._table);

  factory KeyRemapper.resolve(KeyMappingMode mode, {required HostOs local, required HostOs remote}) {
    final effective = mode != KeyMappingMode.auto
        ? mode
        : remote != HostOs.unknown && local.isMac != remote.isMac
            ? KeyMappingMode.ctrlCmd
            : KeyMappingMode.off;
    return KeyRemapper._(effective, switch (effective) {
      KeyMappingMode.ctrlCmd => _swap(Keysym.controlL, Keysym.controlR),
      KeyMappingMode.altCmd => _swap(Keysym.altL, Keysym.altR),
      _ => const {},
    });
  }

  static const identity = KeyRemapper._(KeyMappingMode.off, {});

  final KeyMappingMode effective;
  final Map<int, int> _table;

  int map(int keysym) => _table[keysym] ?? keysym;

  static Map<int, int> _swap(int left, int right) => {
        left: Keysym.superL,
        Keysym.superL: left,
        right: Keysym.superR,
        Keysym.superR: right,
      };
}
