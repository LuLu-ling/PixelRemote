import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:dartssh2/dartssh2.dart';

import '../../domain/services/platform_services.dart';

/// Builds the identities offered during public-key authentication: keys held
/// by ssh-agent first, then key files. Encrypted keys stay locked until the
/// server actually accepts their public half, so passphrases are only asked
/// for when they matter.
final class SshIdentities {
  SshIdentities(this._interaction);

  final UserInteraction _interaction;

  Future<List<SSHIdentity>> fromAgent(String? socketPath) async =>
      socketPath == null ? const [] : _agentIdentities(socketPath);

  Future<List<SSHIdentity>> fromFiles(List<String> paths) async => [
        for (final path in paths) ...await _fileIdentities(path),
      ];

  // ---- key files -----------------------------------------------------------

  Future<List<SSHIdentity>> _fileIdentities(String path) async {
    try {
      final file = File(path);
      if (!file.existsSync()) return const [];
      final pem = await file.readAsString();
      if (!SSHKeyPair.isEncryptedPem(pem)) return SSHKeyPair.fromPem(pem);

      final pub = File('$path.pub');
      if (!pub.existsSync()) {
        final pass = await _interaction.askSecret(SecretKind.keyPassphrase, path);
        return pass == null ? const [] : SSHKeyPair.fromPem(pem, pass);
      }
      final blob = base64.decode(pub.readAsStringSync().trim().split(RegExp(r'\s+'))[1]);
      final keyType = SSHHostKey.getType(blob);
      List<SSHKeyPair>? unlocked;
      return [
        SSHIdentity.custom(
          type: _algorithm(keyType),
          publicKey: SSHRawHostKey(blob),
          shouldProbe: true,
          signer: (data) async {
            try {
              if (unlocked == null) {
                final pass = await _interaction.askSecret(SecretKind.keyPassphrase, path);
                if (pass == null) return _rejected(keyType);
                unlocked = SSHKeyPair.fromPem(pem, pass);
              }
              return unlocked!.first.sign(data);
            } catch (_) {
              return _rejected(keyType);
            }
          },
        ),
      ];
    } catch (_) {
      return const []; // Unreadable or unsupported key: skip it, as OpenSSH does.
    }
  }

  // ---- ssh-agent (draft-miller-ssh-agent) ----------------------------------

  static const _requestIdentities = 11, _identitiesAnswer = 12, _signRequest = 13, _signResponse = 14;
  static const _rsaSha256Flag = 2;

  Future<List<SSHIdentity>> _agentIdentities(String socketPath) async {
    try {
      final reply = await _agentCall(socketPath, Uint8List.fromList([_requestIdentities]));
      if (reply.isEmpty || reply[0] != _identitiesAnswer) return const [];
      final r = _WireReader(reply, 1);
      return [
        for (var i = r.u32(); i > 0; i--) _agentIdentity(socketPath, r.bytes(), utf8.decode(r.bytes(), allowMalformed: true)),
      ];
    } catch (_) {
      return const [];
    }
  }

  SSHIdentity _agentIdentity(String socketPath, Uint8List blob, String comment) {
    final keyType = SSHHostKey.getType(blob);
    return SSHIdentity.custom(
      type: _algorithm(keyType),
      publicKey: SSHRawHostKey(blob),
      comment: comment,
      shouldProbe: true,
      signer: (data) async {
        try {
          final request = BytesBuilder()
            ..addByte(_signRequest)
            ..add(_string(blob))
            ..add(_string(data))
            ..add(_u32(keyType == 'ssh-rsa' ? _rsaSha256Flag : 0));
          final reply = await _agentCall(socketPath, request.toBytes());
          if (reply.isEmpty || reply[0] != _signResponse) return _rejected(keyType);
          return SSHRawSignature(_WireReader(reply, 1).bytes());
        } catch (_) {
          return _rejected(keyType);
        }
      },
    );
  }

  static Future<Uint8List> _agentCall(String socketPath, Uint8List payload) async {
    final socket = await Socket.connect(
      InternetAddress(socketPath, type: InternetAddressType.unix),
      0,
      timeout: const Duration(seconds: 3),
    );
    try {
      socket.add([..._u32(payload.length), ...payload]);
      final buffer = BytesBuilder(copy: false);
      await for (final chunk in socket.timeout(const Duration(seconds: 30))) {
        buffer.add(chunk);
        if (buffer.length < 4) continue;
        final bytes = buffer.toBytes();
        final length = ByteData.sublistView(bytes).getUint32(0);
        if (bytes.length >= length + 4) return bytes.sublist(4, length + 4);
      }
      throw const SocketException('ssh-agent closed the connection');
    } finally {
      socket.destroy();
    }
  }

  // ---- wire helpers --------------------------------------------------------

  /// Modern servers reject SHA-1 `ssh-rsa` signatures, so RSA keys sign as rsa-sha2-256.
  static String _algorithm(String keyType) => keyType == 'ssh-rsa' ? 'rsa-sha2-256' : keyType;

  /// A well-formed but invalid signature: the server rejects it and moves on
  /// to the next auth method. Signers must never throw inside dartssh2.
  static SSHSignature _rejected(String keyType) =>
      SSHRawSignature(Uint8List.fromList([..._string(utf8.encode(_algorithm(keyType))), ..._string(const [])]));

  static Uint8List _u32(int v) => Uint8List(4)..buffer.asByteData().setUint32(0, v);
  static List<int> _string(List<int> b) => [..._u32(b.length), ...b];
}

final class _WireReader {
  _WireReader(this._b, this._o);

  final Uint8List _b;
  int _o;

  int u32() {
    final v = ByteData.sublistView(_b, _o, _o + 4).getUint32(0);
    _o += 4;
    return v;
  }

  Uint8List bytes() {
    final n = u32();
    return Uint8List.sublistView(_b, _o, _o += n);
  }
}
