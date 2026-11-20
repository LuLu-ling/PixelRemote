/// What the user types: `[ssh://][user@]host[:port]`, `user@[::1]:22`, or an
/// alias defined in ~/.ssh/config.
final class SshAddress {
  const SshAddress({required this.host, this.user, this.port});

  final String host;
  final String? user;
  final int? port;

  static SshAddress? tryParse(String input) {
    var s = input.trim();
    if (s.startsWith('ssh://')) s = s.substring(6);
    if (s.endsWith('/')) s = s.substring(0, s.length - 1);

    String? user;
    final at = s.lastIndexOf('@');
    if (at >= 0) {
      user = s.substring(0, at);
      s = s.substring(at + 1);
      if (user.isEmpty) return null;
    }

    int? port;
    if (s.startsWith('[')) {
      final close = s.indexOf(']');
      if (close < 0) return null;
      final rest = s.substring(close + 1);
      if (rest.isNotEmpty) {
        if (!rest.startsWith(':')) return null;
        port = int.tryParse(rest.substring(1));
        if (port == null) return null;
      }
      s = s.substring(1, close);
    } else if (':'.allMatches(s).length == 1) {
      final i = s.indexOf(':');
      port = int.tryParse(s.substring(i + 1));
      if (port == null) return null;
      s = s.substring(0, i);
    }

    if (s.isEmpty || s.contains(RegExp(r'\s'))) return null;
    if (port != null && (port < 1 || port > 65535)) return null;
    return SshAddress(host: s, user: user, port: port);
  }

  @override
  String toString() => '${user == null ? '' : '$user@'}$host${port == null ? '' : ':$port'}';
}

/// A fully resolved SSH destination (after applying ~/.ssh/config).
final class SshEndpoint {
  const SshEndpoint({
    required this.host,
    required this.port,
    required this.user,
    this.identityFiles = const [],
    this.agentSocket,
  });

  final String host;
  final int port;
  final String user;
  final List<String> identityFiles;
  final String? agentSocket;

  String get label => '$user@$host${port == 22 ? '' : ':$port'}';
}
