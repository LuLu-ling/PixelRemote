import 'package:flutter_test/flutter_test.dart';
import 'package:pixel_remote/domain/entities/app_preferences.dart';
import 'package:pixel_remote/domain/entities/keyboard.dart';
import 'package:pixel_remote/domain/entities/ssh_address.dart';
import 'package:pixel_remote/domain/entities/stream_settings.dart';

void main() {
  group('SshAddress.tryParse', () {
    test('accepts the usual forms', () {
      final a = SshAddress.tryParse('alice@example.com:2222')!;
      expect((a.user, a.host, a.port), ('alice', 'example.com', 2222));

      final b = SshAddress.tryParse('  ssh://bob@10.0.0.5/ ')!;
      expect((b.user, b.host, b.port), ('bob', '10.0.0.5', null));

      final c = SshAddress.tryParse('carol@[fe80::1]:22')!;
      expect((c.user, c.host, c.port), ('carol', 'fe80::1', 22));

      final d = SshAddress.tryParse('fe80::1')!;
      expect((d.host, d.port), ('fe80::1', null));

      expect(SshAddress.tryParse('myalias')!.host, 'myalias');
    });

    test('rejects malformed input', () {
      for (final bad in ['', '@host', 'host:abc', 'host:70000', 'a b', 'user@[::1', 'u@[::1]x']) {
        expect(SshAddress.tryParse(bad), isNull, reason: bad);
      }
    });
  });

  group('KeyRemapper', () {
    test('auto swaps Ctrl and ⌘ only across the Mac/PC boundary', () {
      expect(KeyRemapper.resolve(KeyMappingMode.auto, local: HostOs.macos, remote: HostOs.linux).effective,
          KeyMappingMode.ctrlCmd);
      expect(KeyRemapper.resolve(KeyMappingMode.auto, local: HostOs.windows, remote: HostOs.macos).effective,
          KeyMappingMode.ctrlCmd);
      expect(KeyRemapper.resolve(KeyMappingMode.auto, local: HostOs.macos, remote: HostOs.macos).effective,
          KeyMappingMode.off);
      expect(KeyRemapper.resolve(KeyMappingMode.auto, local: HostOs.macos, remote: HostOs.unknown).effective,
          KeyMappingMode.off);
    });

    test('ctrlCmd swaps both sides; letters pass through', () {
      final r = KeyRemapper.resolve(KeyMappingMode.ctrlCmd, local: HostOs.macos, remote: HostOs.linux);
      expect(r.map(Keysym.superL), Keysym.controlL);
      expect(r.map(Keysym.controlL), Keysym.superL);
      expect(r.map(Keysym.superR), Keysym.controlR);
      expect(r.map(0x63), 0x63);
    });

    test('altCmd swaps Alt and ⌘', () {
      final r = KeyRemapper.resolve(KeyMappingMode.altCmd, local: HostOs.windows, remote: HostOs.macos);
      expect(r.map(Keysym.altL), Keysym.superL);
      expect(r.map(Keysym.superL), Keysym.altL);
    });
  });

  test('preferences survive a JSON round trip', () {
    const prefs = AppPreferences(
      themeMode: AppThemeMode.dark,
      languageCode: 'zh',
      keyMapping: KeyMappingMode.altCmd,
      showStats: false,
      stream: StreamSettings(
        quality: ImageQuality.lossless,
        colorDepth: ColorDepth.high,
        frameRate: 144,
        resolution: Resolution(2560, 1440),
        maxBandwidthMbps: 20,
      ),
    );
    final back = AppPreferences.fromJson(prefs.toJson());
    expect(back.toJson(), prefs.toJson());
    expect(back.stream, prefs.stream);
    expect(Resolution.decode('window'), Resolution.matchWindow);
    expect(StreamSettings.fromJson({'frameRate': 7}).frameRate, 60, reason: 'unknown rates fall back');
  });
}
