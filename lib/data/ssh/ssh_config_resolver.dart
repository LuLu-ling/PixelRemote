import 'dart:convert';
import 'dart:io';

import '../../domain/entities/ssh_address.dart';
import '../../domain/services/platform_services.dart';
import '../../domain/services/secure_tunnel.dart';
import '../platform/io_local_platform.dart';

/// Resolves aliases and defaults from ~/.ssh/config (Host, HostName, User,
/// Port, IdentityFile, IdentityAgent), so `myserver` works as it does in ssh.
final class SshConfigResolver implements SshEndpointResolver {
  SshConfigResolver(this._platform, {this._configText});

  final LocalPlatform _platform;
  final String? _configText;

  static const _defaultKeys = ['id_ed25519', 'id_ecdsa', 'id_rsa'];

  @override
  SshEndpoint resolve(SshAddress address, {String? identityFile}) {
    final o = _optionsFor(address.host);
    final agent = o['identityagent']?.first;
    return SshEndpoint(
      host: o['hostname']?.first.replaceAll('%h', address.host) ?? address.host,
      port: address.port ?? int.tryParse(o['port']?.first ?? '') ?? 22,
      user: address.user ?? o['user']?.first ?? _platform.userName,
      identityFiles: {
        if (identityFile != null && identityFile.trim().isNotEmpty) _expand(identityFile.trim()),
        ...?o['identityfile']?.map(_expand),
        for (final name in _defaultKeys) joinPath([_platform.homeDirectory, '.ssh', name]),
      }.toList(),
      agentSocket: switch (agent) {
        null || 'SSH_AUTH_SOCK' => _platform.agentSocket,
        'none' => null,
        final path => _expand(path),
      },
    );
  }

  /// First value wins (as in ssh_config(5)); IdentityFile accumulates.
  Map<String, List<String>> _optionsFor(String alias) {
    final options = <String, List<String>>{};
    var active = true;
    for (final raw in const LineSplitter().convert(_configText ?? _readConfig())) {
      final m = RegExp(r'^\s*(\w+)(?:\s*=\s*|\s+)(.+?)\s*$').firstMatch(raw);
      if (m == null || raw.trimLeft().startsWith('#')) continue;
      final key = m[1]!.toLowerCase();
      final value = m[2]!;
      if (key == 'host') {
        active = matchesHostPatterns(alias, value.split(RegExp(r'\s+')).map(_unquote));
      } else if (key == 'match') {
        active = false; // Match blocks need runtime evaluation; skip them safely.
      } else if (active) {
        key == 'identityfile' ? (options[key] ??= []).add(_unquote(value)) : options.putIfAbsent(key, () => [_unquote(value)]);
      }
    }
    return options;
  }

  String _readConfig() {
    try {
      final file = File(joinPath([_platform.homeDirectory, '.ssh', 'config']));
      return file.existsSync() ? file.readAsStringSync() : '';
    } on FileSystemException {
      return '';
    }
  }

  String _expand(String path) {
    final home = _platform.homeDirectory;
    final p = _unquote(path).replaceAll('%d', home).replaceAll('%u', _platform.userName);
    return p == '~' || p.startsWith('~/') ? home + p.substring(1) : p;
  }

  static String _unquote(String s) => s.length >= 2 && s.startsWith('"') && s.endsWith('"') ? s.substring(1, s.length - 1) : s;
}
