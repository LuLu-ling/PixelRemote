import '../entities/keyboard.dart';

enum SecretKind { sshPassword, keyPassphrase, vncPassword, challenge }

enum HostKeyStatus { trusted, unknown, changed }

/// Questions the infrastructure needs a human to answer mid-connection.
abstract interface class UserInteraction {
  /// Returns `null` when the user cancels.
  Future<String?> askSecret(SecretKind kind, String subject);

  Future<bool> confirmHostKey({required String host, required String type, required String fingerprint});
}

abstract interface class HostKeyVerifier {
  Future<HostKeyStatus> check(String host, int port, String type, String fingerprint);
  Future<void> trust(String host, int port, String type, String fingerprint);
}

abstract interface class LocalPlatform {
  HostOs get os;
  String get homeDirectory;
  String get userName;
  String? get agentSocket;
}

abstract interface class WindowController {
  bool get isFullScreen;
  set isFullScreen(bool value);
  set title(String value);
}
