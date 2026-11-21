import 'dart:async';

import '../domain/entities/connection_profile.dart';
import '../domain/entities/keyboard.dart';
import '../domain/entities/ssh_address.dart';
import '../domain/entities/stream_settings.dart';
import '../domain/errors.dart';
import '../domain/services/platform_services.dart';
import '../domain/services/remote_desktop.dart';
import '../domain/services/secure_tunnel.dart';
import '../domain/services/session_log.dart';
import 'connection_log.dart';
import 'managed_desktop.dart';
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
    required this.log,
    Stream<DepthRejection>? rejections,
  }) : rejections = rejections ?? const Stream.empty();

  final ConnectionProfile profile;
  final SshEndpoint endpoint;
  final SecureTunnel tunnel;
  final RemoteDesktopSession desktop;
  final HostOs remoteOs;
  final SessionMonitor monitor;
  final ConnectionLog log;

  /// Colour depths the server refused (the session kept running on [DepthRejection.kept]).
  final Stream<DepthRejection> rejections;

  /// Completes with the reason the session ended on its own.
  late final Future<RemoteException?> ended = Future.any([
    desktop.closed,
    tunnel.done.then(
      (_) => const RemoteException(RemoteErrorKind.disconnected, 'SSH connection closed'),
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

  static const _src = 'connect', _vncAuthAttempts = 3;

  final SshEndpointResolver _resolver;
  final TunnelConnector _tunnels;
  final RemoteDesktopProtocol _protocol;
  final UserInteraction _interaction;

  Future<ActiveSession> call(
    ConnectionProfile profile,
    StreamSettings settings, {
    required ConnectionLog log,
    void Function(ConnectStage stage)? onStage,
  }) async {
    var connecting = true;
    void stage(ConnectStage s) => connecting ? onStage?.call(s) : null;
    final watch = Stopwatch()..start();

    stage(ConnectStage.resolving);
    final address = SshAddress.tryParse(profile.address);
    if (address == null) throw RemoteException(RemoteErrorKind.invalidAddress, profile.address);
    final endpoint = _resolver.resolve(address, identityFile: profile.identityFile);
    log.info(_src, '"${profile.address}" resolves to ${endpoint.user}@${endpoint.host}:${endpoint.port}');
    log.debug(_src, 'Key files: ${endpoint.identityFiles.join(', ')}; ssh-agent: ${endpoint.agentSocket ?? 'none'}');

    stage(ConnectStage.connecting);
    final tunnel = await _guard(() => _tunnels.connect(endpoint, log));
    try {
      stage(ConnectStage.preparing);
      final remoteOs = await _detectOs(tunnel);
      log.info(_src, 'Remote OS: ${remoteOs.name}');
      final startCommand = profile.startCommand?.trim() ?? '';
      if (startCommand.isNotEmpty) await tunnel.spawn(startCommand);

      // Remembered for the session so reopening a stream doesn't ask again.
      String? vncPassword;
      final meter = TrafficMeter();
      Future<RemoteDesktopSession> openDesktop(StreamSettings s) async {
        for (var attempt = 1;; attempt++) {
          stage(ConnectStage.tunnelling);
          final channel = MeteredChannel(await _openVnc(tunnel, profile, retry: startCommand.isNotEmpty), meter);
          stage(ConnectStage.negotiating);
          try {
            return await _guard(() => _protocol.open(
                  channel,
                  s,
                  log: log,
                  password: () async =>
                      vncPassword ??= await _interaction.askSecret(SecretKind.vncPassword, endpoint.host),
                ));
          } on RemoteException catch (e) {
            if (e.kind != RemoteErrorKind.vncAuthFailed || attempt >= _vncAuthAttempts) rethrow;
            log.warn(_src, 'VNC password rejected (${e.detail ?? 'no reason given'}); asking again');
            vncPassword = null;
          }
        }
      }

      final desktop = await ManagedDesktop.start(openDesktop, settings, log);
      connecting = false;
      log.info(_src, 'Connected in ${watch.elapsedMilliseconds} ms');
      return ActiveSession(
        profile: profile,
        endpoint: endpoint,
        tunnel: tunnel,
        desktop: desktop,
        remoteOs: remoteOs,
        monitor: SessionMonitor(tunnel: tunnel, traffic: meter, desktop: desktop)..start(),
        log: log,
        rejections: desktop.rejections,
      );
    } catch (e) {
      log.error(_src, 'Connection failed: $e');
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
