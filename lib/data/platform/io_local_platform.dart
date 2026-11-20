import 'dart:io';

import '../../domain/entities/keyboard.dart';
import '../../domain/services/platform_services.dart';

final class IoLocalPlatform implements LocalPlatform {
  const IoLocalPlatform();

  @override
  HostOs get os => Platform.isMacOS
      ? HostOs.macos
      : Platform.isWindows
          ? HostOs.windows
          : Platform.isLinux
              ? HostOs.linux
              : HostOs.unknown;

  @override
  String get homeDirectory => Platform.environment[Platform.isWindows ? 'USERPROFILE' : 'HOME'] ?? '.';

  @override
  String get userName => Platform.environment['USER'] ?? Platform.environment['USERNAME'] ?? 'root';

  @override
  String? get agentSocket => Platform.isWindows ? null : Platform.environment['SSH_AUTH_SOCK'];
}

String joinPath(Iterable<String> parts) => parts.join(Platform.pathSeparator);

/// OpenSSH-style host pattern list: `*` and `?` wildcards, `!` negation.
bool matchesHostPatterns(String host, Iterable<String> patterns) {
  var matched = false;
  for (final p in patterns) {
    final negate = p.startsWith('!');
    final glob = negate ? p.substring(1) : p;
    final regex = RegExp(
      '^${RegExp.escape(glob).replaceAll(r'\*', '.*').replaceAll(r'\?', '.')}\$',
      caseSensitive: false,
    );
    if (regex.hasMatch(host)) {
      if (negate) return false;
      matched = true;
    }
  }
  return matched;
}
