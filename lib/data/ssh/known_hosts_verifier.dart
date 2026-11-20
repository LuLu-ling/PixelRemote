import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:pointycastle/export.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../../domain/services/platform_services.dart';
import '../platform/io_local_platform.dart';

/// Trust-on-first-use host key checking. Honours the user's OpenSSH
/// known_hosts (read-only, hashed entries included) plus the app's own store.
final class KnownHostsVerifier implements HostKeyVerifier {
  KnownHostsVerifier(this._prefs, String homeDirectory, {this._knownHostsText})
      : _knownHostsPath = joinPath([homeDirectory, '.ssh', 'known_hosts']);

  static const storageKey = 'trusted_host_keys.v1';

  final SharedPreferencesWithCache _prefs;
  final String _knownHostsPath;
  final String? _knownHostsText;

  @override
  Future<HostKeyStatus> check(String host, int port, String type, String fingerprint) async {
    final stored = _trusted()[_id(host, port, type)];
    if (stored != null) return stored == fingerprint ? HostKeyStatus.trusted : HostKeyStatus.changed;
    return _checkOpenSsh(port == 22 ? host : '[$host]:$port', _family(type), fingerprint);
  }

  @override
  Future<void> trust(String host, int port, String type, String fingerprint) =>
      _prefs.setString(storageKey, jsonEncode({..._trusted(), _id(host, port, type): fingerprint}));

  /// OpenSSH-style `SHA256:<base64>` fingerprint of a wire-format public key.
  static String fingerprintOf(Uint8List keyBlob) =>
      'SHA256:${base64.encode(SHA256Digest().process(keyBlob)).replaceAll('=', '')}';

  HostKeyStatus _checkOpenSsh(String name, String family, String fingerprint) {
    var sawFamily = false;
    for (final line in LineSplitter.split(_knownHostsText ?? _readKnownHosts())) {
      final f = line.trim().split(RegExp(r'\s+'));
      if (f.length < 3 || f[0].startsWith('#') || f[0].startsWith('@')) continue;
      if (_family(f[1]) != family || !_hostMatches(f[0], name)) continue;
      sawFamily = true;
      try {
        if (fingerprintOf(base64.decode(f[2])) == fingerprint) return HostKeyStatus.trusted;
      } on FormatException {
        continue;
      }
    }
    return sawFamily ? HostKeyStatus.changed : HostKeyStatus.unknown;
  }

  static bool _hostMatches(String field, String name) {
    if (!field.startsWith('|1|')) return matchesHostPatterns(name, field.split(','));
    final parts = field.split('|');
    if (parts.length != 4) return false;
    try {
      final mac = HMac(SHA1Digest(), 64)..init(KeyParameter(base64.decode(parts[2])));
      return base64.encode(mac.process(utf8.encode(name))) == parts[3];
    } on FormatException {
      return false;
    }
  }

  Map<String, String> _trusted() {
    try {
      return (jsonDecode(_prefs.getString(storageKey) ?? '{}') as Map).cast<String, String>();
    } on FormatException {
      return {};
    }
  }

  String _readKnownHosts() {
    try {
      return File(_knownHostsPath).readAsStringSync();
    } on FileSystemException {
      return '';
    }
  }

  static String _id(String host, int port, String type) => '$host:$port ${_family(type)}';

  /// RSA host keys negotiate as rsa-sha2-* but are stored as ssh-rsa.
  static String _family(String type) => type.startsWith('rsa-sha2-') ? 'ssh-rsa' : type;
}
