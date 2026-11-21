import 'dart:async';
import 'dart:convert';
import 'dart:typed_data';

import 'package:dartssh2/dartssh2.dart';

import '../../domain/entities/ssh_address.dart';
import '../../domain/errors.dart';
import '../../domain/services/platform_services.dart';
import '../../domain/services/secure_tunnel.dart';
import '../../domain/services/session_log.dart';
import 'ssh_identities.dart';

/// [TunnelConnector] backed by dartssh2 (pure-Dart SSH-2).
final class Dartssh2TunnelConnector implements TunnelConnector {
  Dartssh2TunnelConnector({required UserInteraction interaction, required this._hostKeys})
      : _interaction = interaction,
        _identities = SshIdentities(interaction);

  static const _src = 'ssh';

  /// OpenSSH's own preference order. It matters a great deal here: in pure
  /// Dart, AES-GCM (dartssh2's default first choice) tops out near 12 Mbit/s,
  /// which throttles the whole session, while ChaCha20-Poly1305 runs at
  /// 300+ Mbit/s and AES-CTR + HMAC at 100+ Mbit/s.
  static const algorithms = SSHAlgorithms(
    cipher: [
      SSHCipherType.chacha20poly1305,
      SSHCipherType.aes128ctr,
      SSHCipherType.aes256ctr,
      SSHCipherType.aes128gcm,
      SSHCipherType.aes256gcm,
    ],
  );

  final UserInteraction _interaction;
  final HostKeyVerifier _hostKeys;
  final SshIdentities _identities;

  @override
  Future<SecureTunnel> connect(SshEndpoint e, SessionLog log) async {
    final watch = Stopwatch()..start();
    log.info(_src, 'Connecting to ${e.host}:${e.port} as ${e.user}');
    final SSHSocket socket;
    try {
      socket = await SSHSocket.connect(e.host, e.port, timeout: const Duration(seconds: 10));
    } catch (error) {
      log.error(_src, 'TCP connection failed: $error');
      throw RemoteException(RemoteErrorKind.hostUnreachable, '${e.host}:${e.port} — $error');
    }
    log.info(_src, 'TCP connected in ${watch.elapsedMilliseconds} ms');

    final agentKeys = await _identities.fromAgent(e.agentSocket);
    final fileKeys = await _identities.fromFiles(e.identityFiles);
    final identities = [...agentKeys, ...fileKeys];
    log.info(_src, 'Offering ${agentKeys.length} ssh-agent key(s) and ${fileKeys.length} key file(s)');

    RemoteErrorKind? hostKeyFailure;
    final client = SSHClient(
      socket,
      username: e.user,
      algorithms: algorithms,
      identities: identities,
      keepAliveInterval: const Duration(seconds: 15),
      printDebug: _debugTranslator(log),
      onVerifyHostKey: (type, fingerprintBytes) async {
        final fingerprint = utf8.decode(fingerprintBytes);
        switch (await _hostKeys.check(e.host, e.port, type, fingerprint)) {
          case HostKeyStatus.trusted:
            log.info(_src, 'Host key $type $fingerprint is trusted');
            return true;
          case HostKeyStatus.changed:
            log.error(_src, 'Host key $type $fingerprint does not match the known key: refusing');
            hostKeyFailure = RemoteErrorKind.hostKeyChanged;
            return false;
          case HostKeyStatus.unknown:
            log.info(_src, 'New host key $type $fingerprint: asking the user');
            final ok = await _interaction.confirmHostKey(host: e.label, type: type, fingerprint: fingerprint);
            ok ? await _hostKeys.trust(e.host, e.port, type, fingerprint) : hostKeyFailure = RemoteErrorKind.hostKeyRejected;
            log.info(_src, ok ? 'Host key trusted by the user' : 'Host key rejected by the user');
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
      log.error(_src, 'Authentication failed: $error');
      client.close();
      throw RemoteException(hostKeyFailure ?? RemoteErrorKind.authFailed, '$error');
    }
    log.info(_src, 'Authenticated as ${e.user}; SSH ready after ${watch.elapsedMilliseconds} ms');
    return _Dartssh2Tunnel(client, log);
  }

  /// Turns the interesting parts of dartssh2's debug chatter (versions,
  /// negotiated algorithms, auth methods) into log lines.
  static void Function(String?) _debugTranslator(SessionLog log) {
    const labels = {
      'remoteVersion': 'Server version',
      'kexType': 'Key exchange',
      'hostkeyType': 'Host key algorithm',
      'clientCipherType': 'Cipher client→server',
      'serverCipherType': 'Cipher server→client',
      'clientMacType': 'MAC client→server',
      'serverMacType': 'MAC server→client',
    };
    var aead = false;
    String? lastMethod;
    return (message) {
      if (message == null) return;
      final setting = RegExp(r'^SSHTransport\._(\w+)(?: = |: )(.*)$').firstMatch(message);
      final label = labels[setting?[1]];
      if (setting != null && label != null) {
        final value = setting[1] == 'remoteVersion'
            ? setting[2]!.replaceAll('"', '')
            : RegExp(r'\(([^)]*)\)').firstMatch(setting[2]!)?[1] ?? setting[2]!;
        if (setting[1] == 'serverCipherType') aead = value.contains('gcm') || value.contains('chacha20');
        if (label.startsWith('MAC') && aead) return; // authenticated ciphers carry their own MAC
        log.info(_src, '$label: $value');
        return;
      }
      final method = RegExp(r'^SSHClient\._authWith(\w+)$').firstMatch(message)?[1];
      if (method != null && method != lastMethod) {
        lastMethod = method;
        log.info(_src, 'Trying $method authentication');
      } else if (message.startsWith('Probing public key')) {
        log.debug(_src, message);
      } else if (message == 'SSHClient._handleUserauthFailure') {
        log.debug(_src, 'Server rejected that attempt');
      }
    };
  }
}

final class _Dartssh2Tunnel implements SecureTunnel {
  _Dartssh2Tunnel(this._client, this._log);

  final SSHClient _client;
  final SessionLog _log;
  final _spawned = <SSHSession>[];

  @override
  Future<ByteChannel> open(String host, int port) async {
    try {
      final channel = _ForwardChannel(await _client.forwardLocal(host, port));
      _log.info('tunnel', 'Opened channel to $host:$port on the remote side');
      return channel;
    } catch (error) {
      _log.warn('tunnel', 'Channel to $host:$port refused: $error');
      throw RemoteException(RemoteErrorKind.vncUnavailable, '$host:$port');
    }
  }

  @override
  Future<String> run(String command) async => utf8.decode(await _client.run(command), allowMalformed: true);

  @override
  Future<void> spawn(String command) async {
    final session = await _client.execute(command);
    _log.info('tunnel', 'Started remote command: $command');
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
