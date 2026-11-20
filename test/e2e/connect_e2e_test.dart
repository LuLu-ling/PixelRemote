// End-to-end check of the real pipeline (ssh config → SSH → tunnel → RFB)
// against a live host. Opt-in:
//
//   E2E_SSH=user@host flutter test test/e2e
//
// Optional: E2E_VNC_PORT (default 5900), E2E_VNC_PASSWORD, and
// E2E_TRUST_NEW_HOST_KEY=1 to accept an unknown host key for this run only
// (kept in memory, never written to ~/.ssh or the app's store).
// SSH authentication is key/agent only; this test never supplies a password.
import 'dart:io';
import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:pixel_remote/application/connect_session.dart';
import 'package:pixel_remote/data/platform/io_local_platform.dart';
import 'package:pixel_remote/data/rfb/decoders/rect_decoder.dart';
import 'package:pixel_remote/data/rfb/rfb_session.dart';
import 'package:pixel_remote/data/ssh/dartssh2_tunnel.dart';
import 'package:pixel_remote/data/ssh/known_hosts_verifier.dart';
import 'package:pixel_remote/data/ssh/ssh_config_resolver.dart';
import 'package:pixel_remote/domain/entities/connection_profile.dart';
import 'package:pixel_remote/domain/entities/stream_settings.dart';
import 'package:pixel_remote/domain/errors.dart';
import 'package:pixel_remote/domain/services/platform_services.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:shared_preferences_platform_interface/in_memory_shared_preferences_async.dart';
import 'package:shared_preferences_platform_interface/shared_preferences_async_platform_interface.dart';

final _env = Platform.environment;

final class _Unattended implements UserInteraction {
  @override
  Future<String?> askSecret(SecretKind kind, String subject) async =>
      kind == SecretKind.vncPassword ? _env['E2E_VNC_PASSWORD'] : null;

  @override
  Future<bool> confirmHostKey({required String host, required String type, required String fingerprint}) async {
    stdout.writeln('host key for $host: $type $fingerprint');
    return _env['E2E_TRUST_NEW_HOST_KEY'] == '1';
  }
}

final class _NoJpeg implements JpegCodec {
  const _NoJpeg();
  @override
  Future<Uint32List> decode(Uint8List jpeg, int width, int height) => throw UnimplementedError('JPEG is not decoded headless');
}

void main() {
  final target = _env['E2E_SSH'];

  test('connects through SSH and negotiates RFB', () async {
    SharedPreferencesAsyncPlatform.instance = InMemorySharedPreferencesAsync.empty();
    final prefs = await SharedPreferencesWithCache.create(cacheOptions: const SharedPreferencesWithCacheOptions());
    const platform = IoLocalPlatform();
    final interaction = _Unattended();
    final connect = ConnectSession(
      resolver: SshConfigResolver(platform),
      tunnels: Dartssh2TunnelConnector(interaction: interaction, hostKeys: KnownHostsVerifier(prefs, platform.homeDirectory)),
      protocol: const RfbProtocol(_NoJpeg()),
      interaction: interaction,
    );
    final profile = ConnectionProfile(
      id: 'e2e',
      address: target!,
      vncPort: int.tryParse(_env['E2E_VNC_PORT'] ?? '') ?? 5900,
    );
    // Lossless keeps the server from choosing JPEG, which needs the engine codec.
    const settings = StreamSettings(quality: ImageQuality.lossless, frameRate: 30);

    final stages = <ConnectStage>[];
    try {
      final session = await connect(profile, settings, onStage: stages.add);
      final firstFrame = session.desktop.frames.first;
      await firstFrame.timeout(const Duration(seconds: 15));
      final f = session.desktop.frame;
      stdout.writeln('CONNECTED "${session.desktop.name}" ${f.width}×${f.height}, remote OS ${session.remoteOs.name}');
      expect(f.width, greaterThan(0));
      await session.close();
    } on RemoteException catch (e) {
      stdout.writeln('stopped after ${stages.map((s) => s.name).join(' → ')}: $e');
      // Reaching RFB negotiation proves SSH, auth and tunnelling all worked.
      expect(stages.last, ConnectStage.negotiating, reason: '$e');
      expect(e.kind, isIn([RemoteErrorKind.unsupportedSecurity, RemoteErrorKind.cancelled, RemoteErrorKind.vncAuthFailed]));
    }
  }, skip: target == null ? 'set E2E_SSH=user@host to run' : false, timeout: const Timeout(Duration(minutes: 1)));
}
