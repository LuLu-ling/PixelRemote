import 'dart:async';

import '../domain/entities/connection_profile.dart';
import '../domain/entities/keyboard.dart';
import '../domain/entities/ssh_address.dart';
import '../domain/entities/stream_settings.dart';
import '../domain/errors.dart';
import '../domain/services/platform_services.dart';
import '../domain/services/remote_desktop.dart';
import '../domain/services/secure_tunnel.dart';
import 'session_monitor.dart';

enum ConnectStage { resolving, connecting, preparing, tunnelling, negotiating }

/// Everything that makes up one live connection, closed as a unit.
final class ActiveSession {
  ActiveSession({
    required this.profile,
    required this.endpoint,
    required this.tunnel,
    required this.desktop,
    required this.remoteOs,
    required this.monitor,
  });

  final ConnectionProfile profile;
  final SshEndpoint endpoint;
  final SecureTunnel tunnel;
  final RemoteDesktopSession desktop;
  final HostOs remoteOs;
  final SessionMonitor monitor;

  /// Completes with the reason the session ended on its own.
  late final Future<RemoteException?> ended = Future.any([
    desktop.closed,
    tunnel.done.then(
      (_) => const RemoteException(RemoteErrorKind.disconnected),
      onError: (Object e) => RemoteException(RemoteErrorKind.disconnected, '$e'),
    ),
  ]);

  Future<void> close() async {
    monitor.dispose();
    await desktop.close();
    await tunnel.close();
  }
}

/// Use case: SSH address in, live remote desktop out.
final class ConnectSession {
  ConnectSession({
    required this._resolver,
    required this._tunnels,
    required this._protocol,
    required this._interaction,
  });

  static const _vncAuthAttempts = 3;

  final SshEndpointResolver _resolver;
  final TunnelConnector _tunnels;
  final RemoteDesktopProtocol _protocol;
  final UserInteraction _interaction;

  Future<ActiveSession> call(
    ConnectionProfile profile,
    StreamSettings settings, {
    void Function(ConnectStage stage)? onStage,
  }) async {
    final stage = onStage ?? (_) {};
    stage(ConnectStage.resolving);
    final address = SshAddress.tryParse(profile.address);
    if (address == null) throw RemoteException(RemoteErrorKind.invalidAddress, profile.address);
    final endpoint = _resolver.resolve(address, identityFile: profile.identityFile);

    stage(ConnectStage.connecting);
    final tunnel = await _guard(() => _tunnels.connect(endpoint));
    try {
      stage(ConnectStage.preparing);
      final remoteOs = await _detectOs(tunnel);
      final startCommand = profile.startCommand?.trim() ?? '';
      if (startCommand.isNotEmpty) await tunnel.spawn(startCommand);

      for (var attempt = 1;; attempt++) {
        stage(ConnectStage.tunnelling);
        final channel = MeteredChannel(await _openVnc(tunnel, profile, retry: startCommand.isNotEmpty));
        stage(ConnectStage.negotiating);
        try {
          final desktop = await _guard(() => _protocol.open(
                channel,
                settings,
                password: () => _interaction.askSecret(SecretKind.vncPassword, endpoint.host),
              ));
          final monitor = SessionMonitor(tunnel: tunnel, traffic: channel, desktop: desktop)..start();
          return ActiveSession(
            profile: profile,
            endpoint: endpoint,
            tunnel: tunnel,
            desktop: desktop,
            remoteOs: remoteOs,
            monitor: monitor,
          );
        } on RemoteException catch (e) {
          if (e.kind != RemoteErrorKind.vncAuthFailed || attempt >= _vncAuthAttempts) rethrow;
        }
      }
    } catch (_) {
      await tunnel.close();
      rethrow;
    }
  }

  /// A freshly launched server needs a moment before it accepts connections.
  static Future<ByteChannel> _openVnc(SecureTunnel tunnel, ConnectionProfile p, {required bool retry}) async {
    for (var attempt = 0;; attempt++) {
      try {
        return await tunnel.open(p.vncHost, p.vncPort);
      } on RemoteException catch (e) {
        if (!retry || attempt >= 10 || e.kind != RemoteErrorKind.vncUnavailable) rethrow;
        await Future<void>.delayed(const Duration(milliseconds: 500));
      }
    }
  }

  static Future<HostOs> _detectOs(SecureTunnel tunnel) async {
    Future<String> run(String command) async =>
        (await tunnel.run(command).timeout(const Duration(seconds: 5))).toLowerCase();
    try {
      final uname = await run('uname -s');
      if (uname.contains('darwin')) return HostOs.macos;
      if (uname.contains('linux') || uname.contains('bsd')) return HostOs.linux;
      if (RegExp('windows|mingw|msys|cygwin|not recognized').hasMatch(uname)) return HostOs.windows;
      if ((await run('ver')).contains('windows')) return HostOs.windows;
    } catch (_) {
      // Detection is best effort; "unknown" disables automatic key mapping.
    }
    return HostOs.unknown;
  }

  static Future<T> _guard<T>(Future<T> Function() body) async {
    try {
      return await body();
    } on RemoteException {
      rethrow;
    } catch (e) {
      throw RemoteException(RemoteErrorKind.protocol, '$e');
    }
  }
}
