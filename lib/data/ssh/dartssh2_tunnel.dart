import 'dart:async';
import 'dart:convert';
import 'dart:typed_data';

import 'package:dartssh2/dartssh2.dart';

import '../../domain/entities/ssh_address.dart';
import '../../domain/errors.dart';
import '../../domain/services/platform_services.dart';
import '../../domain/services/secure_tunnel.dart';
import 'ssh_identities.dart';

/// [TunnelConnector] backed by dartssh2 (pure-Dart SSH-2).
final class Dartssh2TunnelConnector implements TunnelConnector {
  Dartssh2TunnelConnector({required UserInteraction interaction, required this._hostKeys})
      : _interaction = interaction,
        _identities = SshIdentities(interaction);

  final UserInteraction _interaction;
  final HostKeyVerifier _hostKeys;
  final SshIdentities _identities;

  @override
  Future<SecureTunnel> connect(SshEndpoint e) async {
    final SSHSocket socket;
    try {
      socket = await SSHSocket.connect(e.host, e.port, timeout: const Duration(seconds: 10));
    } catch (error) {
      throw RemoteException(RemoteErrorKind.hostUnreachable, '${e.host}:${e.port} — $error');
    }

    RemoteErrorKind? hostKeyFailure;
    final client = SSHClient(
      socket,
      username: e.user,
      identities: await _identities.load(agentSocket: e.agentSocket, files: e.identityFiles),
      keepAliveInterval: const Duration(seconds: 15),
      onVerifyHostKey: (type, fingerprintBytes) async {
        final fingerprint = utf8.decode(fingerprintBytes);
        switch (await _hostKeys.check(e.host, e.port, type, fingerprint)) {
          case HostKeyStatus.trusted:
            return true;
          case HostKeyStatus.changed:
            hostKeyFailure = RemoteErrorKind.hostKeyChanged;
            return false;
          case HostKeyStatus.unknown:
            final ok = await _interaction.confirmHostKey(host: e.label, type: type, fingerprint: fingerprint);
            ok ? await _hostKeys.trust(e.host, e.port, type, fingerprint) : hostKeyFailure = RemoteErrorKind.hostKeyRejected;
            return ok;
        }
      },
      onPasswordRequest: () => _interaction.askSecret(SecretKind.sshPassword, e.label),
      onUserInfoRequest: (request) async {
        final answers = <String>[];
        for (final prompt in request.prompts) {
          final isPassword = prompt.promptText.toLowerCase().contains('password');
          final answer = await _interaction.askSecret(
            isPassword ? SecretKind.sshPassword : SecretKind.challenge,
            isPassword ? e.label : prompt.promptText.trim(),
          );
          if (answer == null) return null;
          answers.add(answer);
        }
        return answers;
      },
    );

    try {
      await client.authenticated;
    } catch (error) {
      client.close();
      throw RemoteException(hostKeyFailure ?? RemoteErrorKind.authFailed, '$error');
    }
    return _Dartssh2Tunnel(client);
  }
}

final class _Dartssh2Tunnel implements SecureTunnel {
  _Dartssh2Tunnel(this._client);

  final SSHClient _client;
  final _spawned = <SSHSession>[];

  @override
  Future<ByteChannel> open(String host, int port) async {
    try {
      return _ForwardChannel(await _client.forwardLocal(host, port));
    } catch (error) {
      throw RemoteException(RemoteErrorKind.vncUnavailable, '$host:$port');
    }
  }

  @override
  Future<String> run(String command) async => utf8.decode(await _client.run(command), allowMalformed: true);

  @override
  Future<void> spawn(String command) async {
    final session = await _client.execute(command);
    // Drain output so a chatty process can never stall on a full SSH window.
    session.stdout.listen(null, onError: (_) {});
    session.stderr.listen(null, onError: (_) {});
    _spawned.add(session);
  }

  @override
  Future<Duration> ping() async {
    final watch = Stopwatch()..start();
    await _client.ping();
    return watch.elapsed;
  }

  @override
  Future<void> get done => _client.done;

  @override
  Future<void> close() async {
    for (final s in _spawned) {
      s.close();
    }
    _client.close();
  }
}

final class _ForwardChannel implements ByteChannel {
  _ForwardChannel(this._channel);

  final SSHForwardChannel _channel;

  @override
  late final Stream<Uint8List> input = _channel.stream;

  @override
  void write(List<int> bytes) => _channel.sink.add(bytes);

  @override
  Future<void> close() => _channel.close();
}
