import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:pixel_remote/domain/entities/keyboard.dart';
import 'package:pixel_remote/presentation/input/keyboard_translator.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  KeyDownEvent down(PhysicalKeyboardKey p, LogicalKeyboardKey l, [String? ch]) =>
      KeyDownEvent(physicalKey: p, logicalKey: l, character: ch, timeStamp: Duration.zero);
  KeyUpEvent up(PhysicalKeyboardKey p, LogicalKeyboardKey l) =>
      KeyUpEvent(physicalKey: p, logicalKey: l, timeStamp: Duration.zero);

  test('characters, specials and CJK map to keysyms', () {
    final t = KeyboardTranslator(isMac: false);
    const id = KeyRemapper.identity;
    expect(t.translate(down(PhysicalKeyboardKey.keyA, LogicalKeyboardKey.keyA, 'a'), id), [(0x61, true)]);
    expect(t.translate(down(PhysicalKeyboardKey.keyB, LogicalKeyboardKey.keyB, 'B'), id), [(0x42, true)]);
    expect(t.translate(down(PhysicalKeyboardKey.enter, LogicalKeyboardKey.enter, '\r'), id), [(0xff0d, true)]);
    expect(t.translate(down(PhysicalKeyboardKey.f5, LogicalKeyboardKey.f5), id), [(0xffc2, true)]);
    expect(t.translate(down(PhysicalKeyboardKey.numpad7, LogicalKeyboardKey.numpad7, '7'), id), [(0xffb7, true)]);
    expect(t.translate(down(PhysicalKeyboardKey.keyZ, LogicalKeyboardKey.keyZ, '中'), id), [(0x01004E2D, true)]);
    expect(t.translate(down(PhysicalKeyboardKey.fn, LogicalKeyboardKey.fn), id), isEmpty);
  });

  test('key-up releases exactly what key-down pressed, even after a mapping change', () {
    final t = KeyboardTranslator(isMac: true);
    final swap = KeyRemapper.resolve(KeyMappingMode.ctrlCmd, local: HostOs.macos, remote: HostOs.linux);
    expect(t.translate(down(PhysicalKeyboardKey.metaLeft, LogicalKeyboardKey.metaLeft), swap), [(Keysym.controlL, true)]);
    expect(t.translate(up(PhysicalKeyboardKey.metaLeft, LogicalKeyboardKey.metaLeft), KeyRemapper.identity),
        [(Keysym.controlL, false)]);
    expect(t.translate(up(PhysicalKeyboardKey.keyQ, LogicalKeyboardKey.keyQ), KeyRemapper.identity), isEmpty);
  });

  test('releaseAll lets go of every held key', () {
    final t = KeyboardTranslator(isMac: false);
    t.translate(down(PhysicalKeyboardKey.shiftLeft, LogicalKeyboardKey.shiftLeft), KeyRemapper.identity);
    t.translate(down(PhysicalKeyboardKey.keyX, LogicalKeyboardKey.keyX, 'X'), KeyRemapper.identity);
    expect(t.releaseAll().toSet(), {(Keysym.shiftL, false), (0x58, false)});
    expect(t.releaseAll(), isEmpty);
  });
}
